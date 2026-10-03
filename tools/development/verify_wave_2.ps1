[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $GodotExecutable,

    [switch] $SkipRenderedPlaytest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('lfw2-' + [Guid]::NewGuid().ToString('N'))))
$expectedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (-not $tempRoot.StartsWith($expectedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a validation directory outside system temporary storage: $tempRoot"
}
$evidenceRoot = Join-Path $repositoryRoot '.verification\wave2'
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA

function Assert-GodotRun {
    param(
        [string] $Name,
        [object[]] $Output,
        [int] $ExitCode,
        [string] $Marker
    )
    $Output | ForEach-Object { Write-Output $_ }
    $outputText = $Output -join [Environment]::NewLine
    if ($ExitCode -ne 0 -or $outputText -match '(?m)^(SCRIPT ERROR|ERROR:)') {
        throw "$Name failed with exit code $ExitCode."
    }
    if (-not [string]::IsNullOrEmpty($Marker) -and $outputText -notmatch [regex]::Escape($Marker)) {
        throw "$Name did not emit $Marker."
    }
}

$versionOutput = @(& $godotPath --version 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw 'Godot version check failed.'
}
$version = ($versionOutput | Select-Object -First 1).ToString().Trim()
if ($version -match '^4\.(6\.3|7\.1)(\.|$)') {
    throw "Godot $version is blocked for Leyforge automation."
}

New-Item -ItemType Directory -Path (Join-Path $tempRoot 'profile\appdata') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempRoot 'profile\localappdata') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempRoot 'unit') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempRoot 'worlds') -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$env:APPDATA = Join-Path $tempRoot 'profile\appdata'
$env:LOCALAPPDATA = Join-Path $tempRoot 'profile\localappdata'

try {
    Write-Output "GODOT_VERSION=$version"
    Write-Output "PROJECT_PATH=$repositoryRoot"
    Write-Output "ISOLATED_SAVE_ROOT=$tempRoot"

    $importOutput = @(& $godotPath --headless --editor --path $repositoryRoot --quit 2>&1)
    Assert-GodotRun -Name 'Wave 2 script import' -Output $importOutput -ExitCode $LASTEXITCODE

    $unitRoot = Join-Path $tempRoot 'unit'
    $unitOutput = @(
        & $godotPath --headless --path $repositoryRoot --script 'res://tests/wave_2/wave_2_test_runner.gd' -- "--wave2-test-root=$unitRoot" 2>&1
    )
    Assert-GodotRun -Name 'Wave 2 focused tests' -Output $unitOutput -ExitCode $LASTEXITCODE -Marker 'WAVE_2_TEST_PASS'

    $unsafeOutput = @(
        & $godotPath --headless --path $repositoryRoot -- --world-id=unsafe "--world-root=$unitRoot" 2>&1
    )
    Assert-GodotRun -Name 'Unsafe saved player fallback' -Output $unsafeOutput -ExitCode $LASTEXITCODE -Marker 'WAVE_2_PLAYER_FALLBACK'
    if (($unsafeOutput -join [Environment]::NewLine) -notmatch 'LEYFORGE_WAVE_1_RUNTIME_READY') {
        throw 'Unsafe saved player did not reach a ready fallback spawn.'
    }

    $corruptPath = Join-Path $unitRoot 'corrupt\world.json'
    $corruptHashBefore = (Get-FileHash -LiteralPath $corruptPath -Algorithm SHA256).Hash
    $savedErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $corruptOutput = @(
            & $godotPath --headless --path $repositoryRoot -- --world-id=corrupt "--world-root=$unitRoot" 2>&1
        )
        $corruptExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorPreference
    }
    $corruptOutput | ForEach-Object { Write-Output $_ }
    if ($corruptExit -ne 1 -or ($corruptOutput -join [Environment]::NewLine) -notmatch 'Malformed world save envelope') {
        throw 'Corrupt disposable save was not clearly rejected by startup.'
    }
    if ((Get-FileHash -LiteralPath $corruptPath -Algorithm SHA256).Hash -ne $corruptHashBefore) {
        throw 'Failed startup changed the corrupt authoritative save.'
    }
    Write-Output 'WAVE_2_CORRUPT_STARTUP_REJECTED'

    if ($SkipRenderedPlaytest) {
        Write-Output 'WAVE_2_RENDERED_PLAYTEST_SKIPPED'
    }
    else {
        $worldRoot = Join-Path $tempRoot 'worlds'
        $runA = @(
            & $godotPath --path $repositoryRoot -- --wave2-playtest --wave2-run=A --world-id=wave2_acceptance "--world-root=$worldRoot" --seed=184552221 "--wave2-playtest-out=$evidenceRoot" 2>&1
        )
        Assert-GodotRun -Name 'Wave 2 rendered create/edit/save' -Output $runA -ExitCode $LASTEXITCODE -Marker 'WAVE_2_RENDERED_A_PASS'

        $runB = @(
            & $godotPath --path $repositoryRoot -- --wave2-playtest --wave2-run=B --world-id=wave2_acceptance "--world-root=$worldRoot" "--wave2-playtest-out=$evidenceRoot" 2>&1
        )
        Assert-GodotRun -Name 'Wave 2 rendered process restart' -Output $runB -ExitCode $LASTEXITCODE -Marker 'WAVE_2_RENDERED_B_PASS'

        $runC = @(
            & $godotPath --path $repositoryRoot -- --wave2-playtest --wave2-run=C --world-id=wave2_isolation "--world-root=$worldRoot" --seed=184552221 "--wave2-playtest-out=$evidenceRoot" 2>&1
        )
        Assert-GodotRun -Name 'Wave 2 rendered same-seed isolation' -Output $runC -ExitCode $LASTEXITCODE -Marker 'WAVE_2_RENDERED_C_PASS'

        foreach ($phase in @('A', 'B', 'C')) {
            $reportPath = Join-Path $evidenceRoot "run_$phase.json"
            if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
                throw "Missing Wave 2 rendered report: $reportPath"
            }
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            if (-not $report.passed) {
                throw "Wave 2 rendered phase $phase reported failure."
            }
        }
        $createReport = Get-Content -LiteralPath (Join-Path $evidenceRoot 'run_A.json') -Raw | ConvertFrom-Json
        if (-not $createReport.new_edits_streamed_out_and_back) {
            throw 'Wave 2 newly edited terrain did not survive streaming before save.'
        }
        $restartReport = Get-Content -LiteralPath (Join-Path $evidenceRoot 'run_B.json') -Raw | ConvertFrom-Json
        if (-not $restartReport.streamed_out_and_back -or $restartReport.restored_edit_count -lt 7) {
            throw 'Wave 2 rendered restart did not prove streamed edit restoration.'
        }
        foreach ($image in @(
            '01_world_a_before.png',
            '02_world_a_after.png',
            '03_world_a_restarted.png',
            '04_world_a_streamed_back.png',
            '05_isolated_world.png'
        )) {
            $imagePath = Join-Path $evidenceRoot $image
            if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or (Get-Item -LiteralPath $imagePath).Length -le 0) {
                throw "Missing Wave 2 rendered image: $imagePath"
            }
        }
        Write-Output "WAVE_2_RENDERED_EVIDENCE=$evidenceRoot"
    }
    Write-Output 'WAVE_2_VALIDATION_PASS'
}
finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($expectedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTempRoot)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
