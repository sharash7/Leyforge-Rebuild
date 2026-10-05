[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
    [switch] $SkipRegression
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
# Pin the approved runner before executing it.
$approved = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.2 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_2\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf52-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$testProject = Join-Path $tempRoot 'project'
New-Item -ItemType Directory -Force $evidenceRoot,$testProject | Out-Null
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$processes = @{}
$gate = @{passed=$false;certified=$false;timestamp_utc=[DateTime]::UtcNow.ToString('o');runner=$godotPath;runner_sha256=(Get-FileHash $godotPath).Hash;manual_acceptance='PENDING_OWNER'}
function Check([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Start-Run([string] $Name, [string[]] $Arguments, [string] $ProfileName = $Name) {
    $app = Join-Path $tempRoot ($ProfileName + '-appdata')
    $local = Join-Path $tempRoot ($ProfileName + '-localappdata')
    New-Item -ItemType Directory -Force $app,$local | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $godotPath
    $info.WorkingDirectory = $testProject
    $info.Arguments = (@($Arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['APPDATA'] = $app
    $info.EnvironmentVariables['LOCALAPPDATA'] = $local
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    [void] $proc.Start()
    $processes[$Name] = @{process=$proc;stdout=$proc.StandardOutput.ReadToEndAsync();stderr=$proc.StandardError.ReadToEndAsync()}
}
function Finish-Run([string] $Name, [int] $ExpectedExit = 0, [int] $Timeout = 30000) {
    $entry = $processes[$Name]
    $proc = $entry.process
    if (-not $proc.WaitForExit($Timeout)) { $proc.Kill(); $proc.WaitForExit(); throw "$Name timed out." }
    $text = $entry.stdout.Result + $entry.stderr.Result
    [IO.File]::WriteAllText((Join-Path $evidenceRoot "$Name.log"),$text)
    Check ($proc.ExitCode -eq $ExpectedExit) "$Name exit $($proc.ExitCode): $text"
    if ($ExpectedExit -eq 0) { Check ($text -notmatch '(?m)^\s*(SCRIPT ERROR|ERROR:)') "$Name engine error: $text" }
    Write-Output "$Name PASS"
}
function Read-Report([string] $Name) {
    $file = Join-Path $evidenceRoot "$Name.json"
    # Atomic replacement can briefly expose no readable target on Windows.
    # Retry current bytes boundedly; never substitute a cached or passing report.
    foreach ($attempt in 1..6) {
        try {
            $stream = [IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $reader = New-Object IO.StreamReader($stream)
            try { $report = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            if ($null -ne $report) { return $report }
        } catch {}
        Start-Sleep -Milliseconds 50
    }
    return $null
}
function Wait-State([string] $Name, [string] $State) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $report = Read-Report $Name
        if ($report -and $report.state -eq $State) { Check $report.passed "$Name internal assertions: $($report.failures)"; return $report }
        if ($processes[$Name].process.HasExited) { Finish-Run $Name; throw "$Name exited without $State" }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name did not reach $State"
}
function Start-Probe([string] $Name, [string] $Mode, [string] $ProfileName, [string] $Fault = '', [double] $Hold = -1, [int] $Port = 25652) {
    Start-Run $Name @('--headless','--max-fps','60','--path',$testProject,'--script','res://tests/networking/w5_2_process.gd','--',"--session=$Mode","--port=$Port","--world-id=proof-world",'--seed=184552221',"--proof-dir=$evidenceRoot","--proof-name=$Name","--proof-fault=$Fault","--proof-hold=$Hold") $ProfileName
}
function Stop-Probe([string] $Name) {
    [IO.File]::WriteAllText((Join-Path $evidenceRoot "$Name.stop"),'stop')
    Finish-Run $Name
}
function Wait-Bindings([int] $Count) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $hostReport = Read-Report 'host'
        if ($hostReport -and @($hostReport.bindings.PSObject.Properties).Count -eq $Count) { Check $hostReport.passed 'Host admission invariants failed'; return $hostReport }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Host did not reach $Count bindings."
}
try {
    $inventoryPath = Join-Path $repositoryRoot '.verification_snapshot_inventory.json'
    $usingSnapshot = Test-Path -LiteralPath $inventoryPath
    if ($usingSnapshot) { $paths = Get-Content $inventoryPath -Raw | ConvertFrom-Json } else {
        $paths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons)
        Check ($LASTEXITCODE -eq 0) 'Snapshot inventory failed'
    }
    $manifest = @{}
    foreach ($relative in $paths) {
        if (-not $usingSnapshot -and $relative.StartsWith('addons/') -and @(& git -C $repositoryRoot ls-files -- $relative).Count -eq 0) { continue }
        $source = Join-Path $repositoryRoot $relative
        $target = Join-Path $testProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
        $manifest[$relative] = (Get-FileHash -LiteralPath $source).Hash
        Check ((Get-FileHash -LiteralPath $target).Hash -eq $manifest[$relative]) "Snapshot mismatch $relative"
    }
    @($manifest.Keys) | ConvertTo-Json | Set-Content (Join-Path $testProject '.verification_snapshot_inventory.json') -Encoding UTF8
    $manifest | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'source_manifest.json') -Encoding UTF8
    Start-Run 'import' @('--headless','--editor','--path',$testProject,'--quit')
    Finish-Run 'import' 0 180000
    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_2_focused.gd','--',("--fixture=" + (Join-Path $tempRoot 'focused-fixture')),"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    $focused = Read-Report 'focused'
    Check $focused.passed 'Focused tests failed'
    $gate.focused_checks = $focused.checks

    Start-Probe 'host' 'HOST' 'host'
    $hostStart = Wait-State 'host' 'HOSTING'
    Check ($hostStart.peer_id -eq 1) 'Host transport peer ID'
    Start-Probe 'client' 'JOIN' 'client'
    $client = Wait-State 'client' 'CONNECTED'
    $two = Wait-Bindings 2
    Check ($client.pid -ne $two.pid -and $client.peer_id -ne 1) 'Two actual distinct OS processes and peers'
    Check ($client.player_id -ne $two.owner -and $client.player_id -cmatch '^[0-9a-f]{32}$') 'Distinct stable identities'
    Check ($client.world.world_id -eq 'proof-world' -and $client.client_world_save_absent -and $client.client_has_no_authority) 'World manifest and no client save'
    Check ($client.states -contains 'CONNECTING' -and $client.states -contains 'AUTHENTICATING') 'Client state sequence'
    $gate.enet_two_process = $true

    Start-Probe 'duplicate' 'JOIN' 'client'
    $duplicate = Wait-State 'duplicate' 'REJECTED'
    Check ($duplicate.reason -eq 'duplicate_identity') 'Duplicate reason'
    Finish-Run 'duplicate'
    [void] (Wait-Bindings 2)
    [void] (Wait-State 'client' 'CONNECTED')
    $rejections = @{}
    foreach ($fault in @('protocol_mismatch','build_mismatch','save_schema_mismatch','content_version_mismatch','content_hash_mismatch','worldgen_unsupported','invalid_identity','malformed_handshake','oversized_handshake')) {
        Start-Probe $fault 'JOIN' ('fault-' + $fault) $fault
        $rejected = Wait-State $fault 'REJECTED'
        $expected = if ($fault -eq 'oversized_handshake') { 'malformed_handshake' } else { $fault }
        Check ($rejected.reason -eq $expected) "$fault wrong rejection: $($rejected.reason)"
        Finish-Run $fault
        $unchanged = Wait-Bindings 2
        Check (@($unchanged.roster).Count -eq 2) "$fault created a character"
        [void] (Wait-State 'client' 'CONNECTED')
        $rejections[$fault] = $rejected.reason
    }
    Start-Probe 'auth_timeout' 'JOIN' 'silent-client' 'auth_timeout'
    $timeout = Wait-State 'auth_timeout' 'CONNECTION_FAILED'
    Check ($timeout.reason -eq 'auth_timeout') 'Auth timeout reason'
    Finish-Run 'auth_timeout'
    $timeoutHost = Wait-Bindings 2
    Check (@($timeoutHost.roster).Count -eq 2) 'Timeout admitted character'
    $gate.auth_timeout = $true

    # Port conflict uses normal production bootstrap, without test injection.
    Start-Run 'port_conflict' @('--headless','--path',$testProject,'--','--session=HOST','--port=25652','--world-id=conflicting-world')
    Finish-Run 'port_conflict' 1
    Check (-not (Test-Path (Join-Path $tempRoot 'port_conflict-appdata\Godot\app_userdata\Leyforge\worlds\conflicting-world\world.json'))) 'Conflict wrote save'
    Start-Probe 'connection_failure' 'JOIN' 'no-host' '' -1 25653
    $failed = Wait-State 'connection_failure' 'CONNECTION_FAILED'
    Check ($failed.reason -eq 'connection_failed' -and $failed.client_world_save_absent) 'No-host failure safe'
    Finish-Run 'connection_failure'

    Stop-Probe 'client'
    $left = Wait-Bindings 1
    Check (@($left.roster).Count -eq 2) 'Disconnect removed durable character'
    Start-Probe 'reconnect' 'JOIN' 'client'
    $reconnect = Wait-State 'reconnect' 'CONNECTED'
    $rejoined = Wait-Bindings 2
    Check ($reconnect.player_id -eq $client.player_id -and @($rejoined.roster).Count -eq 2) 'Stable reconnect roster'
    Check (@($rejoined.events | Where-Object { $_.kind -eq 'admitted' -and $_.existing }).Count -eq 1) 'Reconnect uses same record object'
    $gate.reconnect = $true
    Start-Probe 'distinct' 'JOIN' 'distinct'
    $distinct = Wait-State 'distinct' 'CONNECTED'
    Check ($distinct.player_id -ne $client.player_id) 'Distinct third identity'
    [void] (Wait-Bindings 3)
    foreach ($number in 4..8) {
        Start-Probe "capacity$number" 'JOIN' "capacity$number"
        [void] (Wait-State "capacity$number" 'CONNECTED')
    }
    $fullHost = Wait-Bindings 8
    Start-Probe 'server_full' 'JOIN' 'ninth-player'
    $full = Wait-State 'server_full' 'REJECTED'
    Check ($full.reason -eq 'server_full') 'Server capacity rejection'
    Finish-Run 'server_full'
    $fullHost = Wait-Bindings 8
    Check (@($fullHost.roster).Count -eq 8) 'Server-full added a character'
    $rejections['server_full'] = $full.reason
    $rejections | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'incompatibility_results.json') -Encoding UTF8
    Stop-Probe 'distinct'
    foreach ($number in 4..8) { Stop-Probe "capacity$number" }
    [void] (Wait-Bindings 2)
    [IO.File]::WriteAllText((Join-Path $evidenceRoot 'host.save'),'save')
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do { $saved = Read-Report 'host'; if ($saved.saved) { break }; Start-Sleep -Milliseconds 100 } while ([DateTime]::UtcNow -lt $deadline)
    Check $saved.saved 'Normal host save failed'
    Stop-Probe 'host'
    $disconnected = Wait-State 'reconnect' 'DISCONNECTED'
    Check ($disconnected.reason -eq 'server_disconnected') 'Host disconnect reason'
    Finish-Run 'reconnect'
    $gate.server_disconnect = $true
    Start-Probe 'reload' 'HOST' 'host' '' -1 25654
    $reload = Wait-State 'reload' 'HOSTING'
    Check (@($reload.roster).Count -eq 8 -and $reload.owner -eq $hostStart.owner) 'Fresh host reload roster/owner'
    Check (@($reload.roster | Where-Object player_id -eq $client.player_id).Count -eq 1) 'Client durable record survived host process restart'
    Stop-Probe 'reload'
    $gate.host_save_reload = $true
    $gate.client_save_negative = $true

    # Exercise both exact graphical launchers; use a fresh external project cache.
    $ownerProject = Join-Path $tempRoot 'owner-project'
    New-Item -ItemType Directory -Force $ownerProject | Out-Null
    foreach ($relative in $manifest.Keys) {
        $target = Join-Path $ownerProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item (Join-Path $testProject $relative) $target
    }
    $ownerInfo = New-Object Diagnostics.ProcessStartInfo
    $ownerInfo.FileName = 'powershell.exe'
    $ownerInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tests\networking\w5_2_owner_launch.ps1') + '" -ProjectPath "' + $ownerProject + '" -FixtureRoot "' + (Join-Path $tempRoot 'owner-fixture') + '" -EvidenceRoot "' + $evidenceRoot + '"'
    $ownerInfo.UseShellExecute = $false
    $ownerInfo.CreateNoWindow = $true
    $ownerInfo.RedirectStandardOutput = $true
    $ownerInfo.RedirectStandardError = $true
    $ownerProcess = New-Object Diagnostics.Process
    $ownerProcess.StartInfo = $ownerInfo
    [void] $ownerProcess.Start()
    $ownerStdout = $ownerProcess.StandardOutput.ReadToEndAsync()
    $ownerStderr = $ownerProcess.StandardError.ReadToEndAsync()
    if (-not $ownerProcess.WaitForExit(240000)) { $ownerProcess.Kill(); throw 'Owner-launch verification timeout' }
    $ownerText = $ownerStdout.Result + $ownerStderr.Result
    [IO.File]::WriteAllText((Join-Path $evidenceRoot 'owner_launch.log'),$ownerText)
    Check ($ownerProcess.ExitCode -eq 0 -and $ownerText -match 'W5_2_OWNER_LAUNCH_PASS') "Owner-launch verification failed: $ownerText"
    $ownerReceipt = Read-Report 'owner_launch'
    Check ($ownerReceipt.passed -and $ownerReceipt.clean_cache) 'Owner launch lacks clean-cache proof'
    $gate.owner_launch = $true
    $gate.owner_launch_checks = $ownerReceipt.checks
    Write-Output 'OWNER_LAUNCH PASS'
    $rpcSource = Get-ChildItem (Join-Path $testProject 'src') -Filter *.gd -Recurse
    foreach ($file in $rpcSource) {
        $text = Get-Content $file.FullName -Raw
        Check ($text -notmatch '@rpc|MultiplayerSpawner|MultiplayerSynchronizer') "W5.3 gameplay replication appeared: $($file.FullName)"
        if ($file.FullName -notlike '*networking\network_session.gd') { Check ($text -notmatch 'ENetMultiplayerPeer') 'ENet escaped session boundary' }
    }
    if (-not $SkipRegression) {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = 'powershell.exe'
        $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tools\development\verify_wave_5_part_1.ps1') + '" -GodotExecutable "' + $godotPath + '"'
        $info.WorkingDirectory = $testProject
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.EnvironmentVariables['APPDATA'] = Join-Path $tempRoot 'regression-appdata'
        $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $tempRoot 'regression-localappdata'
        $prior = New-Object Diagnostics.Process
        $prior.StartInfo = $info
        [void] $prior.Start()
        $stdout = $prior.StandardOutput.ReadToEndAsync()
        $stderr = $prior.StandardError.ReadToEndAsync()
        if (-not $prior.WaitForExit(900000)) { $prior.Kill(); throw 'W5.1 and earlier regressions timed out.' }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w51.log'),$text)
        $priorRoot = Join-Path $testProject '.verification\wave5\w5_1'
        if (Test-Path $priorRoot) { Copy-Item $priorRoot (Join-Path $evidenceRoot 'regression_w51') -Recurse }
        Check ($prior.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_1_VALIDATION_PASS') 'W5.1 complete regression failed'
        $priorRun = Get-ChildItem (Join-Path $evidenceRoot 'regression_w51') -Directory | Sort-Object Name | Select-Object -Last 1
        $priorReceipt = Get-Item -LiteralPath (Join-Path $priorRun.FullName 'gate.json')
        $priorGate = Get-Content $priorReceipt.FullName -Raw | ConvertFrom-Json
        Check ($priorGate.certified -and $priorGate.passed) 'W5.1 receipt uncertified'
        $gate.regressions = 'Wave 0, 1, 2, 3, 4 and W5.1 PASS'
    }
    foreach ($relative in $manifest.Keys) { Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $manifest[$relative]) "Source changed during run: $relative" }
    if ($usingSnapshot) { $finalPaths = Get-Content $inventoryPath -Raw | ConvertFrom-Json } else { $finalPaths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons) }
    Check (@(Compare-Object $paths $finalPaths).Count -eq 0) 'Source inventory changed during run'
    $gate.snapshot_matches_source = $true
    $gate.no_resource_replication = $true
    $gate.passed = $true
    $gate.certified = -not $SkipRegression
    Write-Output 'WAVE_5_PART_2_VALIDATION_PASS'
} catch {
    $gate.failure = $_.Exception.Message
    throw
} finally {
    foreach ($name in $processes.Keys) {
        $entry = $processes[$name]
        if (-not $entry.process.HasExited) { $entry.process.Kill(); $entry.process.WaitForExit() }
        $text = $entry.stdout.Result + $entry.stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.log"),$text)
    }
    $gate | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidenceRoot 'gate.json') -Encoding UTF8
    Write-Output "WAVE_5_PART_2_EVIDENCE=$evidenceRoot"
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved)) { try { Remove-Item -LiteralPath $resolved -Recurse -Force } catch { Write-Warning ("Temporary cleanup incomplete at " + $resolved + ": " + $_.Exception.Message) } }
}