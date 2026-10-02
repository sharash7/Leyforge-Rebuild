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
$profileRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('lfw1-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$profileRoot = [System.IO.Path]::GetFullPath($profileRoot)
$expectedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.verification\wave1'))
$expectedEvidencePrefix = $repositoryRoot.TrimEnd('\') + '\'

if (-not $profileRoot.StartsWith($expectedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create a validation profile outside the system temporary directory: $profileRoot"
}
if (-not $evidenceRoot.StartsWith($expectedEvidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage evidence outside the repository: $evidenceRoot"
}

function Assert-GodotRun {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object[]] $Output,

        [Parameter(Mandatory = $true)]
        [int] $ExitCode,

        [string[]] $RequiredMarkers = @()
    )

    $Output | ForEach-Object { Write-Output $_ }
    $text = $Output -join [Environment]::NewLine
    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode."
    }
    if ($text -match '(?m)^(SCRIPT ERROR|ERROR:)') {
        throw "$Name reported a Godot error."
    }
    foreach ($marker in $RequiredMarkers) {
        if ($text -notmatch [regex]::Escape($marker)) {
            throw "$Name did not emit required marker: $marker"
        }
    }
}

$versionOutput = @(& $godotPath --version 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Godot version check failed with exit code $LASTEXITCODE."
}

$version = ($versionOutput | Select-Object -First 1).ToString().Trim()
if ($version -match '^4\.(6\.3|7\.1)(\.|$)') {
    throw "Godot $version is blocked for Leyforge automation."
}

if (Test-Path -LiteralPath $evidenceRoot) {
    Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $profileRoot 'appdata') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $profileRoot 'localappdata') -Force | Out-Null
$env:APPDATA = Join-Path $profileRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $profileRoot 'localappdata'

try {
    Write-Output "GODOT_VERSION=$version"
    Write-Output "PROJECT_PATH=$repositoryRoot"

    $wave0Gate = Join-Path $repositoryRoot 'tools\development\verify_wave_0.ps1'
    $wave0Output = @(
        & powershell -NoProfile -ExecutionPolicy Bypass -File $wave0Gate -GodotExecutable $godotPath 2>&1
    )
    Assert-GodotRun -Name 'Wave 0 regression gate' -Output $wave0Output -ExitCode $LASTEXITCODE -RequiredMarkers @(
        'WAVE_0_VALIDATION_PASS'
    )

    $testOutput = @(
        & $godotPath --headless --path $repositoryRoot --script 'res://tests/wave_1/wave_1_test_runner.gd' 2>&1
    )
    Assert-GodotRun -Name 'Wave 1 focused tests' -Output $testOutput -ExitCode $LASTEXITCODE -RequiredMarkers @(
        'WAVE_1_TEST_PASS'
    )

    $smokeOutput = @(& $godotPath --headless --path $repositoryRoot 2>&1)
    Assert-GodotRun -Name 'Wave 1 streamed runtime smoke' -Output $smokeOutput -ExitCode $LASTEXITCODE -RequiredMarkers @(
        'LEYFORGE_WAVE_0_BOOTSTRAP_READY',
        'LEYFORGE_VOXEL_PLUGIN_READY class=VoxelTerrain',
        'LEYFORGE_WAVE_1_RUNTIME_READY'
    )

    if ($SkipRenderedPlaytest) {
        Write-Output 'WAVE_1_RENDERED_PLAYTEST_SKIPPED'
    }
    else {
        $playtestOutput = @(
            & $godotPath --path $repositoryRoot -- --wave1-playtest "--wave1-playtest-out=$evidenceRoot" 2>&1
        )
        Assert-GodotRun -Name 'Wave 1 rendered playtest' -Output $playtestOutput -ExitCode $LASTEXITCODE -RequiredMarkers @(
            'WAVE_1_PLAYTEST_PASS'
        )

        $expectedEvidence = @(
            (Join-Path $evidenceRoot '01_spawn.png'),
            (Join-Path $evidenceRoot '02_boundary_place.png'),
            (Join-Path $evidenceRoot '03_after_boundary_break.png'),
            (Join-Path $evidenceRoot 'playtest_report.json')
        )
        foreach ($evidencePath in $expectedEvidence) {
            if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
                throw "Rendered playtest did not create evidence: $evidencePath"
            }
            if ((Get-Item -LiteralPath $evidencePath).Length -le 0) {
                throw "Rendered playtest evidence is empty: $evidencePath"
            }
        }

        $playtestReport = Get-Content -LiteralPath (Join-Path $evidenceRoot 'playtest_report.json') -Raw |
            ConvertFrom-Json
        if (-not $playtestReport.passed) {
            throw 'Rendered playtest report did not record a pass.'
        }
        Write-Output "WAVE_1_RENDERED_EVIDENCE=$evidenceRoot"
    }

    Write-Output 'WAVE_1_VALIDATION_PASS'
}
finally {
    if (Test-Path -LiteralPath $profileRoot) {
        $profileRemoved = $false
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            if (-not (Test-Path -LiteralPath $profileRoot)) {
                $profileRemoved = $true
                break
            }
            try {
                Remove-Item -LiteralPath $profileRoot -Recurse -Force -ErrorAction Stop
                $profileRemoved = $true
                break
            }
            catch {
                if ($attempt -lt 10) {
                    Start-Sleep -Milliseconds 300
                }
            }
        }
        if (-not $profileRemoved -and (Test-Path -LiteralPath $profileRoot)) {
            Write-Warning "Could not completely remove temporary validation profile: $profileRoot"
        }
    }
}
