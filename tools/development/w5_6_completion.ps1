# Invoked inside verify_wave_5_part_6's retained evidence/isolation scope.
$ownerProject = Join-Path $tempRoot 'owner-project'
New-Item -ItemType Directory -Force $ownerProject | Out-Null
foreach ($relative in $manifest.Keys) {
    $target = Join-Path $ownerProject $relative
    New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item (Join-Path $testProject $relative) $target
}
$ownerInfo = New-Object Diagnostics.ProcessStartInfo
$ownerInfo.FileName = 'powershell.exe'
$ownerInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tests\networking\w5_6_owner_launch.ps1') + '" -ProjectPath "' + $ownerProject + '" -FixtureRoot "' + (Join-Path $tempRoot 'owner-fixture') + '" -EvidenceRoot "' + $evidenceRoot + '"'
$ownerInfo.UseShellExecute = $false; $ownerInfo.CreateNoWindow = $true
$ownerInfo.RedirectStandardOutput = $true; $ownerInfo.RedirectStandardError = $true
$ownerProcess = New-Object Diagnostics.Process; $ownerProcess.StartInfo = $ownerInfo
[void]$ownerProcess.Start()
$ownerStdout = $ownerProcess.StandardOutput.ReadToEndAsync(); $ownerStderr = $ownerProcess.StandardError.ReadToEndAsync()
if (-not $ownerProcess.WaitForExit(240000)) { $ownerProcess.Kill(); throw 'W5.6 owner-launch timeout' }
$ownerText = $ownerStdout.Result + $ownerStderr.Result
[IO.File]::WriteAllText((Join-Path $evidenceRoot 'owner_launch.log'),$ownerText)
Check ($ownerProcess.ExitCode -eq 0 -and $ownerText -match 'W5_6_OWNER_LAUNCH_PASS') "W5.6 exact launcher failure: $ownerText"
$ownerReceipt = Read-Report 'owner_launch'
Check ($ownerReceipt.passed -and $ownerReceipt.clean_cache) 'Owner launch missing clean-cache proof'
$gate.owner_launch = $true; $gate.owner_launch_checks = $ownerReceipt.checks
Write-Output 'W5_6_OWNER_LAUNCH_PASS'
if (-not $SkipRegression) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tools\development\verify_wave_5_part_5.ps1') + '" -GodotExecutable "' + $godotPath + '"'
    $info.WorkingDirectory = $testProject; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.EnvironmentVariables['APPDATA'] = Join-Path $tempRoot 'regression-appdata'
    $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $tempRoot 'regression-localappdata'
    $prior = New-Object Diagnostics.Process; $prior.StartInfo = $info
    [void]$prior.Start()
    $stdout = $prior.StandardOutput.ReadToEndAsync(); $stderr = $prior.StandardError.ReadToEndAsync()
    if (-not $prior.WaitForExit(1800000)) { $prior.Kill(); throw 'Complete W5.5 and prior regression timeout' }
    $text = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w55.log'),$text)
    $priorRoot = Join-Path $testProject '.verification\wave5\w5_5'
    if (Test-Path $priorRoot) {
        & robocopy.exe $priorRoot (Join-Path $evidenceRoot 'regression_w55') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
        Check ($LASTEXITCODE -lt 8) 'Retain complete regression evidence'
    }
    Check ($prior.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_5_VALIDATION_PASS') 'W5.5 complete regression failed'
    $priorRun = Get-ChildItem (Join-Path $evidenceRoot 'regression_w55') -Directory | Sort-Object Name | Select-Object -Last 1
    $priorGate = Get-Content (Join-Path $priorRun.FullName 'gate.json') -Raw | ConvertFrom-Json
    Check ($priorGate.certified -and $priorGate.passed) 'Complete prior receipt uncertified'
    $gate.regressions = 'Wave 0,1,2,3,4; W5.1,W5.2,W5.3,W5.4,W5.5 PASS'
    $gate.full_shared_loop = $priorGate.real_process_paths
}
foreach ($relative in $workingManifest.Keys) { Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $workingManifest[$relative]) "Source changed during verification: $relative" }
$gate.snapshot_matches_source = $true; $gate.passed = $true; $gate.certified = -not $SkipRegression
Write-Output 'WAVE_5_PART_6_VALIDATION_PASS'
