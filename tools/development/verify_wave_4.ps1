[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
    [switch] $SkipRenderedPlaytest,
    [switch] $SkipRegression
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
if ($godotPath.EndsWith('.disabled', [StringComparison]::OrdinalIgnoreCase)) { throw 'Quarantined executables cannot be used.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave4\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('lfw4-' + [Guid]::NewGuid().ToString('N'))))
$expectedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (-not $tempRoot.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid external test root.' }
$testProject = Join-Path $tempRoot "project"
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $evidenceRoot,"$tempRoot\appdata","$tempRoot\localappdata","$tempRoot\unit","$tempRoot\worlds" -Force | Out-Null

function Invoke-Godot {
    param([string] $Name, [string[]] $Arguments, [string] $Marker)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $godotPath
    $startInfo.WorkingDirectory = $testProject
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
    # Snapshot canonical working files into external temporary storage. This avoids
    # imports/native-library copies touching a project open in the owner's editor.
    $paths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate verification snapshot.' }
    $manifest = @{}
    foreach ($relative in $paths) {
        if ($relative.StartsWith("addons/") -and (@(& git -C $repositoryRoot ls-files -- $relative)).Count -eq 0) { continue }
        $source = Join-Path $repositoryRoot $relative
        $target = [IO.Path]::GetFullPath((Join-Path $testProject $relative))
        if (-not $target.StartsWith($testProject.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid snapshot path.' }
        New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) { throw "Snapshot byte mismatch: $relative" }
        $manifest[$relative] = $sourceHash
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'source_manifest.json') -Encoding UTF8
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
    Invoke-Godot 'import' @('--headless','--editor','--path',$testProject,'--quit') ''
    $unit = "$tempRoot\unit"
    Invoke-Godot 'focused' @('--headless','--path',$testProject,'--script','res://tests/wave_4/wave_4_test_runner.gd','--','--wave4-focused','--wave4-test-survival',"--wave4-test-root=$unit","--wave4-test-out=$evidenceRoot") 'WAVE_4_TEST_PASS'
    $focused = Get-Content -LiteralPath (Join-Path $evidenceRoot 'focused.json') -Raw | ConvertFrom-Json
    if (-not $focused.passed) { throw 'Focused report failed.' }
    $gate.focused_checks = $focused.checks
    $gate.rendered_checks = 0
    if (-not $SkipRenderedPlaytest) {
        $worldRoot = "$tempRoot\worlds"

        foreach ($phase in @('A','B','C','D','M1','N1','M2','N2')) {
            $id = if ($phase -eq 'D') { 'wave4_isolation' } elseif ($phase -in @('M1','N1')) { 'rendered_v1' } elseif ($phase -in @('M2','N2')) { 'rendered_v2' } else { 'wave4_acceptance' }
            $selectedRoot = if ($phase -in @('M1','N1','M2','N2')) { $unit } else { $worldRoot }
            Invoke-Godot "rendered_$phase" @('--path',$testProject,'--','--wave4-playtest',"--wave4-run=$phase","--world-id=$id","--world-root=$selectedRoot",'--seed=184552221',"--wave4-playtest-out=$evidenceRoot") "WAVE_4_RENDERED_${phase}_PASS"
            $report = Get-Content -LiteralPath (Join-Path $evidenceRoot "run_$phase.json") -Raw | ConvertFrom-Json
            if (-not $report.passed) { throw "Rendered report $phase failed." }
            if ($report.survival_profile -ne 'Standard' -or $report.survival_acceleration) { throw "Rendered manual candidate must use Standard production timing." }
            $gate.rendered_checks += $report.checks
        }
        foreach ($frame in @('01_gathering.png','02_crafting.png','03_workstation.png','04_shelter.png','05_survival.png','06_saved.png','07_restart.png','08_completed.png','09_isolation.png','10_migration_v1.png','11_migration_v2.png','12_drop_before.png','12_drop_motion.png','13_furnace_completed.png','14_resource_scale.png','15_personal_grid.png','16_workbench_grid.png','17_tree_variation.png','18_generated_woodland.png','19_partial_tree_grounded_drop.png','20_placed_heartwood.png','21_distant_woodland.png','22_drop_resettled.png')) {
            $path = Join-Path $evidenceRoot $frame
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -le 0) { throw "Missing rendered frame $frame" }
        }
        $gate.rendered = $true
        $gate.manual_acceptance = 'PENDING_OWNER'
        $gate.survival_profile = 'Standard'
        $gate.survival_acceleration = $false
    } else {
        Write-Output 'WAVE_4_RENDERED_SKIPPED; FULL EXIT GATE NOT CERTIFIED'
    }
    if (-not $SkipRegression) {
        foreach ($wave in @('0','1','2','3')) {
            $gatePath = Join-Path $testProject "tools\development\verify_wave_$wave.ps1"
            $priorInfo = New-Object Diagnostics.ProcessStartInfo
            $priorInfo.FileName = 'powershell.exe'
            $priorInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $gatePath + '" -GodotExecutable "' + $godotPath + '"'
            $priorInfo.WorkingDirectory = $testProject
            $priorInfo.UseShellExecute = $false
            $priorInfo.CreateNoWindow = $true
            $priorInfo.RedirectStandardOutput = $true
            $priorInfo.RedirectStandardError = $true
            $prior = New-Object Diagnostics.Process
            $prior.StartInfo = $priorInfo
            [void] $prior.Start()
            $priorStdout = $prior.StandardOutput.ReadToEndAsync()
            $priorStderr = $prior.StandardError.ReadToEndAsync()
            if (-not $prior.WaitForExit(180000)) {
                $prior.Kill(); $prior.WaitForExit()
                throw "Wave $wave regression timed out; no passing receipt."
            }
            $priorText = $priorStdout.Result + $priorStderr.Result
            [IO.File]::WriteAllText((Join-Path $evidenceRoot "regression_wave_$wave.log"), $priorText)
            # Historical gates validate their expected corrupt-startup stderr.
            # Transport strings without reinterpreting native ErrorRecords here.
            if ($prior.ExitCode -ne 0 -or $priorText -notmatch "WAVE_${wave}_VALIDATION_PASS") { throw "Wave $wave regression failed." }
            $priorEvidence = Join-Path $testProject ".verification\wave$wave"
            if (Test-Path -LiteralPath $priorEvidence) { Copy-Item -LiteralPath $priorEvidence -Destination (Join-Path $evidenceRoot "regression_wave_$wave") -Recurse }
            $gate["wave_$wave"] = 'PASS'
            Write-Output "WAVE_${wave}_REGRESSION_PASS"
        }
        $gate.regressions = $true
    } else { $gate.regressions = $false }
    foreach ($relative in $manifest.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $repositoryRoot $relative) -Algorithm SHA256).Hash -ne $manifest[$relative]) { throw "Source changed during verification: $relative" }
    }
    $gate.project_snapshot = $testProject
    $gate.snapshot_matches_source = $true
    $gate.certified = $gate.rendered -and $gate.regressions
    $gate.passed = $true
    Write-Output 'WAVE_4_VALIDATION_PASS'
} finally {
    Write-Output "WAVE_4_EVIDENCE=$evidenceRoot"
    $gate | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'gate.json') -Encoding UTF8
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
