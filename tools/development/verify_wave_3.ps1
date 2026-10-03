[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
    [switch] $SkipRenderedPlaytest
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
if ($godotPath.EndsWith('.disabled', [StringComparison]::OrdinalIgnoreCase)) { throw 'Quarantined executables cannot be used.' }
$evidenceRoot = Join-Path $repositoryRoot '.verification\wave3'
$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('lfw3-' + [Guid]::NewGuid().ToString('N'))))
$expectedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (-not $tempRoot.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid external test root.' }
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $evidenceRoot,"$tempRoot\appdata","$tempRoot\localappdata","$tempRoot\unit","$tempRoot\worlds" -Force | Out-Null

function Invoke-Godot {
    param([string] $Name, [string[]] $Arguments, [string] $Marker)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $godotPath
    $startInfo.WorkingDirectory = $repositoryRoot
    $startInfo.Arguments = (($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    [void] $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(180000)) {
        $process.Kill()
        $process.WaitForExit()
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$Name.log"), $text)
        throw "$Name timed out; no passing receipt."
    }
    $text = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $evidenceRoot "$Name.log"), $text)
    Write-Output $text
    if ($process.ExitCode -ne 0 -or $text -match '(?m)^(SCRIPT ERROR|ERROR:)') { throw "$Name failed: exit $($process.ExitCode)." }
    if ($Marker -and $text -notmatch [regex]::Escape($Marker)) { throw "$Name lacks $Marker." }
}
$gate = @{ passed=$false; rendered=$false; isolated_root=$tempRoot; timestamp_utc=[DateTime]::UtcNow.ToString('o') }
try {
    $env:APPDATA = "$tempRoot\appdata"
    $env:LOCALAPPDATA = "$tempRoot\localappdata"
    $versionOutput = @(& $godotPath --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Version query failed.' }
    $version = $versionOutput[0].ToString().Trim()
    if ($version -match '^4\.(6\.3|7\.1)(\.|$)') { throw "Blocked Godot version: $version" }
    $gate.runner = $godotPath
    $gate.version = $version
    $gate.runner_sha256 = (Get-FileHash -LiteralPath $godotPath -Algorithm SHA256).Hash
    Write-Output "GODOT_VERSION=$version"
    Invoke-Godot 'import' @('--headless','--editor','--path',$repositoryRoot,'--quit') ''
    $unit = "$tempRoot\unit"
    Invoke-Godot 'focused' @('--headless','--path',$repositoryRoot,'--script','res://tests/wave_3/wave_3_test_runner.gd','--',"--wave3-test-root=$unit","--wave3-test-out=$evidenceRoot") 'WAVE_3_TEST_PASS'
    $focused = Get-Content -LiteralPath (Join-Path $evidenceRoot 'focused.json') -Raw | ConvertFrom-Json
    if (-not $focused.passed) { throw 'Focused report failed.' }
    $gate.focused_checks = $focused.checks
    if (-not $SkipRenderedPlaytest) {
        $worldRoot = "$tempRoot\worlds"
        $content = "$unit\test_content.json"
        foreach ($phase in @('A','B','C','M','N')) {
            $id = if ($phase -eq 'C') { 'wave3_isolation' } elseif ($phase -in @('M','N')) { 'rendered_migration' } else { 'wave3_acceptance' }
            $selectedRoot = if ($phase -in @('M','N')) { $unit } else { $worldRoot }
            Invoke-Godot "rendered_$phase" @('--path',$repositoryRoot,'--','--wave3-playtest',"--wave3-run=$phase","--world-id=$id","--world-root=$selectedRoot",'--seed=184552221',"--wave3-test-content=$content","--wave3-playtest-out=$evidenceRoot") "WAVE_3_RENDERED_${phase}_PASS"
            $report = Get-Content -LiteralPath (Join-Path $evidenceRoot "run_$phase.json") -Raw | ConvertFrom-Json
            if (-not $report.passed) { throw "Rendered report $phase failed." }
        }
        foreach ($frame in @('01_physical_drop.png','02_inventory_hotbar.png','03_placement_consumed.png','04_storage.png','05_saved_world.png','06_restarted_inventory.png','07_streamed_back.png','08_isolated_world.png','09_migrated_v1.png','10_migrated_restart.png')) {
            $path = Join-Path $evidenceRoot $frame
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -le 0) { throw "Missing rendered frame $frame" }
        }
        $gate.rendered = $true
    } else {
        Write-Output 'WAVE_3_RENDERED_SKIPPED; FULL EXIT GATE NOT CERTIFIED'
    }
    $gate.passed = $true
    Write-Output 'WAVE_3_VALIDATION_PASS'
} finally {
    $gate | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'gate.json') -Encoding UTF8
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
