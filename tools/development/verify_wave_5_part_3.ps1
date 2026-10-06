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
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.3 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_3\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf53-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
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
    Start-Run $Name @('--path',$testProject,'--script','res://tests/networking/w5_3_process.gd','--',"--session=$Mode","--port=$Port","--world-id=proof-world",'--seed=184552221',"--proof-dir=$evidenceRoot","--proof-name=$Name","--proof-fault=$Fault","--proof-hold=$Hold") $ProfileName
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
$checks = 0
function Assert([bool] $Condition, [string] $Message) { $script:checks++; Check $Condition $Message }
function Wait-Ready([string] $Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    do {
        $report = Read-Report $Name
        if ($report -and $report.ready) { Assert $report.passed "$Name assertions"; return $report }
        if ($processes[$Name].process.HasExited) { Finish-Run $Name; throw "$Name exited before world ready" }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name world readiness timeout"
}
function Command([string] $Name, [hashtable] $Value) {
    $before = Read-Report $Name
    $count = @($before.commands).Count
    $target = Join-Path $evidenceRoot "$Name.command.json"
    [IO.File]::WriteAllText($target + '.pending',($Value | ConvertTo-Json -Compress))
    [IO.File]::Move($target + '.pending',$target)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $report = Read-Report $Name
        if ($report -and @($report.commands).Count -gt $count) { Assert $report.passed "$Name command assertions"; return $report }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name command timeout: $($Value.op)"
}
function Body($HostReport,[string] $Id) { return $HostReport.bodies.PSObject.Properties[$Id].Value }
function Distance($A,$B) {
    return [Math]::Sqrt([Math]::Pow(($A[0]-$B[0]),2)+[Math]::Pow(($A[1]-$B[1]),2)+[Math]::Pow(($A[2]-$B[2]),2))
}
function HorizontalSpeed($State) { return [Math]::Sqrt([Math]::Pow($State.velocity[0],2)+[Math]::Pow($State.velocity[2],2)) }
function Wait-Converged([string] $Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $report = Read-Report $Name
        if ($report -and $report.error -lt 0.12 -and $report.grounded -and (HorizontalSpeed $report) -lt 0.1) { return $report }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name convergence failed"
}

try {
    $inventoryPath = Join-Path $repositoryRoot '.verification_snapshot_inventory.json'
    $usingSnapshot = Test-Path -LiteralPath $inventoryPath
    if ($usingSnapshot) { $paths = Get-Content $inventoryPath -Raw | ConvertFrom-Json } else {
        $paths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons docs AGENTS.md)
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
    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_3_focused.gd','--',("--fixture=" + (Join-Path $tempRoot 'focused-fixture')),"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    $focused = Read-Report 'focused'
    Check $focused.passed 'Focused tests failed'
    $gate.focused_checks = $focused.checks
    $gate.input_bytes = $focused.input_bytes
    $gate.eight_player_snapshot_bytes = $focused.eight_player_snapshot_bytes


    Start-Probe 'host' 'HOST' 'host'
    $hostStart = Wait-Ready 'host'
    Start-Probe 'client' 'JOIN' 'client'
    $client = Wait-Ready 'client'
    $id = $client.player_id
    $two = Wait-Bindings 2
    Assert ($client.pid -ne $two.pid -and $id -ne $two.player_id) 'Distinct real processes and identities'
    Assert ($client.no_authority -and $client.no_world_save -and $client.world.network_protocol_version -eq 6) 'JOIN current protocol / no authority'
    Assert (@($client.avatars).Count -eq 1) 'JOIN sees host presence'
    [void] (Command 'host' @{op='screenshot';player_id=$id})
    [void] (Command 'client' @{op='screenshot';player_id=$two.player_id})
    $body = Body $two $id
    Assert ($body.ready -and $body.viewer_exists -and $body.loaded) 'Physical authoritative body and collision interest'
    Assert ((Distance $body.state.position $two.position) -ge 0.85) 'Distinct safe physical spawns'
    $gate.enet_two_process = $true
    [void] (Command 'client' @{op='prediction'})
    Start-Sleep -Milliseconds 500
    $prediction = Read-Report 'client'
    Assert ($prediction.prediction.displacement -gt 0.01 -and $prediction.prediction.sequence_after -eq $prediction.prediction.sequence_before) 'Predicted body moves before input acknowledgement'
    [void] (Command 'client' @{op='move';direction='stop'})
    $converged = Wait-Converged 'client'
    $movementStart = (Body (Read-Report 'host') $id).state.position
    [void] (Command 'host' @{op='inventory';open=$true})
    [void] (Command 'client' @{op='move';direction='move_forward';sprint=$true;jump=$true})
    Start-Sleep -Seconds 3
    $movingHost = Read-Report 'host'
    $movingBody = Body $movingHost $id
    Assert ($movingHost.inventory_open -and -not $movingHost.paused -and $movingBody.accepted -gt 5) 'Inventory open / network and physics continue'
    Assert ((Distance $movementStart $movingBody.state.position) -gt 3) 'Client movement changes authoritative transform with host UI open'
    $trace = Get-Content (Join-Path $evidenceRoot 'host-trace.json') -Raw | ConvertFrom-Json
    $jumpStates = @($trace | ForEach-Object { $_.bodies.PSObject.Properties[$id].Value.state } | Where-Object { $_ -and $_.velocity[1] -gt 2 })
    Assert ($jumpStates.Count -gt 0) 'Remote jump uses physical body'
    $gate.inventory_network = $true
    [void] (Command 'client' @{op='move';direction='stop'})
    [void] (Command 'host' @{op='inventory';open=$false})
    $stop = Wait-Converged 'client'
    Assert ($stop.error -lt 0.12) 'Stop converges'
    $gate.final_convergence_error = $stop.error
    $gate.normal_prediction_error = $stop.maximum_error
    Assert ($stop.maximum_error -lt 2.0) 'Localhost normal prediction divergence stays bounded'
    [void] (Command 'host' @{op='screenshot';player_id=$id})
    [void] (Command 'client' @{op='screenshot';player_id=(Read-Report 'host').player_id})
    $beforeDrift = (Body (Read-Report 'host') $id).state.position
    [void] (Command 'client' @{op='drift'})
    Start-Sleep -Seconds 1
    $corrected = Wait-Converged 'client'
    $afterDrift = (Body (Read-Report 'host') $id).state.position
    Assert ($corrected.corrections -ge 1 -and $corrected.maximum_error -ge 3) 'Injected drift actually corrected'
    Assert ((Distance $beforeDrift $afterDrift) -lt 0.12 -and $corrected.error -lt 0.12) 'Client position injection never moves host authority'
    $gate.drift_correction = $true
    $gate.maximum_prediction_error = $corrected.maximum_error
    $gate.injected_drift_final_error = $corrected.error
    $jumpTick = (Read-Report 'host').tick
    [void] (Command 'client' @{op='held_jump'})
    Start-Sleep -Milliseconds 2500
    $jumpTrace = Get-Content (Join-Path $evidenceRoot 'host-trace.json') -Raw | ConvertFrom-Json
    $upward = $false
    $jumpEdges = 0
    foreach ($slice in @($jumpTrace | Where-Object { $_.tick -gt $jumpTick })) {
        $jumpState = $slice.bodies.PSObject.Properties[$id].Value.state
        $rising = $jumpState -and $jumpState.velocity[1] -gt 1
        if ($rising -and -not $upward) { $jumpEdges++ }
        $upward = $rising
    }
    Assert ($jumpEdges -eq 1 -and (Body (Read-Report 'host') $id).state.grounded) 'Held last jump packet produces one jump, then lands without repetition'
    $gate.jump_edge = $true
    [void] (Command 'client' @{op='resume'})
    [void] (Wait-Converged 'client')
    $rejectedBefore = (Read-Report 'host').rejected_packets
    [void] (Command 'client' @{op='stale'})
    Start-Sleep -Milliseconds 500
    $staleHost = Read-Report 'host'
    Assert ($staleHost.rejected_packets -ge $rejectedBefore+2) 'Duplicate and stale packets rejected over real transport'
    [void] (Command 'client' @{op='invalid';player_id=$staleHost.player_id})
    Start-Sleep -Milliseconds 300
    Assert ((Read-Report 'host').rejected_packets -gt $staleHost.rejected_packets) 'Forged actor packet rejected'
    [void] (Command 'client' @{op='resume'})
    [void] (Command 'client' @{op='move';direction='move_right';sprint=$true})
    Start-Sleep -Milliseconds 600
    [void] (Command 'client' @{op='input_loss'})
    Start-Sleep -Milliseconds 900
    $lossHost = Read-Report 'host'
    $lossBody = Body $lossHost $id
    Assert ($lossBody.input_age -gt 0.25 -and (HorizontalSpeed $lossBody.state) -lt 0.1) 'Input loss stops horizontal sprint after timeout'
    Assert ($lossBody.loaded -and $lossBody.state.grounded) 'Input timeout preserves gravity/collision'
    $gate.input_timeout = $true
    [void] (Command 'client' @{op='resume'})
    [void] (Wait-Converged 'client')
    # Move the HOST's real interest origin away; the remote body's actual viewer
    # must support continued input-driven walking without any remote teleport.
    [void] (Command 'host' @{op='snapshot_loss';enable=$true})
    [void] (Command 'host' @{op='host_distance';player_id=$id;distance=180})
    Start-Sleep -Seconds 1
    $farClient = Read-Report 'client'
    $farHost = Read-Report 'host'
    $farBody = Body $farHost $id
    Assert ((Distance $farHost.position $farBody.state.position) -gt 128) 'Remote outside host local view and leave radius'
    Assert (@($farClient.avatars).Count -eq 0 -and -not $farBody.visible) 'Reliable presence leave succeeds despite snapshot suppression'
    Assert ($farBody.viewer_exists -and $farBody.loaded) 'Remote interest persists when visually irrelevant'
    $leaveCount = @($farClient.presence | Where-Object { $_.kind -eq 'leave' }).Count
    [void] (Command 'host' @{op='snapshot_loss';enable=$false})
    [void] (Command 'client' @{op='move';direction='move_back';jump=$true})
    $farStart = $farBody.state.position
    Start-Sleep -Seconds 3
    $supported = Read-Report 'host'
    $supportedBody = Body $supported $id
    Assert ($supportedBody.loaded -and $supportedBody.viewer_exists -and $supportedBody.state.position[1] -gt 10) 'Remote collision remains supported independently of host camera'
    Assert ((Distance $farStart $supportedBody.state.position) -gt 3) 'Real client walks beyond host local terrain interest'
    [void] (Command 'client' @{op='move';direction='stop'})
    [void] (Wait-Converged 'client')
    [void] (Command 'host' @{op='host_distance';player_id=$id;distance=112})
    Start-Sleep -Seconds 1
    $gap = Read-Report 'client'
    Assert (@($gap.avatars).Count -eq 0 -and @($gap.presence | Where-Object { $_.kind -eq 'leave' }).Count -eq $leaveCount) 'Hysteresis gap has no enter/leave thrashing'
    [void] (Command 'host' @{op='host_distance';player_id=$id;distance=12})
    Start-Sleep -Seconds 1
    $near = Read-Report 'client'
    Assert (@($near.avatars).Count -eq 1 -and @($near.presence | Where-Object { $_.kind -eq 'enter' }).Count -eq 1) 'Reliable re-enter creates host avatar once'
    $gate.relevance_hysteresis = $true
    $gate.remote_streaming = $true
    $gate.remote_streaming_distance = Distance $supported.position $supportedBody.state.position
    Start-Probe 'third' 'JOIN' 'third'
    $third = Wait-Ready 'third'
    $three = Wait-Bindings 3
    Assert ($third.player_id -ne $id -and @($three.bodies.PSObject.Properties).Count -eq 2) 'Third identity owns separate body'
    [void] (Command 'third' @{op='move';direction='move_left';jump=$true})
    $thirdStart = (Body $three $third.player_id).state.position
    Start-Sleep -Seconds 1
    [void] (Command 'third' @{op='move';direction='stop'})
    $independent = Read-Report 'host'
    Assert ((Distance $thirdStart (Body $independent $third.player_id).state.position) -gt 0.3) 'Third identity moves independently'
    Assert ((HorizontalSpeed (Body $independent $id).state) -lt 0.1) 'Third movement never controls Client 2'
    $sets = @($independent.relevant.PSObject.Properties)
    Assert ($sets.Count -eq 2 -and $sets[0].Name -ne $sets[1].Name) 'Relevance is stored per destination peer'
    $gate.third_identity = $true
    Stop-Probe 'third'
    [void] (Wait-Bindings 2)
    [void] (Command 'client' @{op='move';direction='move_forward'})
    Start-Sleep -Milliseconds 500
    $lastMoving = Body (Read-Report 'host') $id
    Assert ((HorizontalSpeed $lastMoving.state) -gt 1) 'Disconnect occurs during authoritative movement'
    $finalBeforeLeave = $lastMoving.state.position
    Stop-Probe 'client'
    $left = Wait-Bindings 1
    Assert (@($left.bodies.PSObject.Properties).Count -eq 0 -and @($left.roster).Count -eq 3) 'Disconnect removes live bodies/viewers, retains durable roster'
    $retained = @($left.roster | Where-Object player_id -eq $id)[0]
    Assert ((Distance $finalBeforeLeave $retained.transform.position) -lt 1.0) 'Disconnect captures final authoritative transform'
    Start-Probe 'reconnect' 'JOIN' 'client'
    $reconnect = Wait-Ready 'reconnect'
    $rejoined = Wait-Bindings 2
    Assert ($reconnect.player_id -eq $id -and @($rejoined.roster).Count -eq 3) 'Reconnect same character, no duplicate roster'
    # Check the exact restored transform before legitimate post-spawn gravity.
    # The natural walking route may disconnect while stepping off a one-cell ledge.
    Assert ((Distance $retained.transform.position (Body $rejoined $id).spawn_transform.position) -lt 0.15) 'Reconnect restores final authoritative position'
    $restoredBody = Body $rejoined $id
    Assert ($restoredBody.ready -and $restoredBody.loaded) 'Restored body retains streamed collision support'
    $retainedHorizontal = @($retained.transform.position[0],0,$retained.transform.position[2])
    $restoredHorizontal = @($restoredBody.state.position[0],0,$restoredBody.state.position[2])
    Assert ((Distance $retainedHorizontal $restoredHorizontal) -lt 0.15) 'Reconnect has no horizontal spawn relocation'
    $gate.reconnect = $true
    [void] (Command 'host' @{op='save'})
    $savedBody = (Body (Read-Report 'host') $id).state.position
    Stop-Probe 'host'
    $disconnected = Wait-State 'reconnect' 'DISCONNECTED'
    Assert ($disconnected.reason -eq 'server_disconnected' -and $disconnected.no_world_save) 'Server disconnect freezes client without saving'
    Finish-Run 'reconnect'
    Start-Probe 'reload' 'HOST' 'host' '' -1 25654
    [void] (Wait-Ready 'reload')
    Start-Probe 'reload_client' 'JOIN' 'client' '' -1 25654
    $reloadClient = Wait-Ready 'reload_client'
    $reloadHost = Read-Report 'reload'
    Assert ($reloadClient.player_id -eq $id -and @($reloadHost.roster).Count -eq 3) 'Fresh process restores same world-local record'
    Assert ((Distance $savedBody (Body $reloadHost $id).state.position) -lt 0.15) 'Host save/reload retains authoritative remote transform'
    Assert ($reloadClient.no_authority -and $reloadClient.no_world_save) 'Client save negative after move/reconnect/reload'
    $gate.host_save_reload = $true
    $gate.client_save_negative = $true
    Stop-Probe 'reload_client'
    Stop-Probe 'reload'
    $gate.real_process_checks = $checks

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
    $ownerInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tests\networking\w5_3_owner_launch.ps1') + '" -ProjectPath "' + $ownerProject + '" -FixtureRoot "' + (Join-Path $tempRoot 'owner-fixture') + '" -EvidenceRoot "' + $evidenceRoot + '"'
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
    Check ($ownerProcess.ExitCode -eq 0 -and $ownerText -match 'W5_3_OWNER_LAUNCH_PASS') "Owner-launch verification failed: $ownerText"
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
        $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tools\development\verify_wave_5_part_2.ps1') + '" -GodotExecutable "' + $godotPath + '"'
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
        if (-not $prior.WaitForExit(1200000)) { $prior.Kill(); throw 'W5.2 and earlier regressions timed out.' }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w52.log'),$text)
        $priorRoot = Join-Path $testProject '.verification\wave5\w5_2'
        if (Test-Path $priorRoot) { Copy-Item $priorRoot (Join-Path $evidenceRoot 'regression_w52') -Recurse }
        Check ($prior.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_2_VALIDATION_PASS') 'W5.2 complete regression failed'
        $priorRun = Get-ChildItem (Join-Path $evidenceRoot 'regression_w52') -Directory | Sort-Object Name | Select-Object -Last 1
        $priorReceipt = Get-Item -LiteralPath (Join-Path $priorRun.FullName 'gate.json')
        $priorGate = Get-Content $priorReceipt.FullName -Raw | ConvertFrom-Json
        Check ($priorGate.certified -and $priorGate.passed) 'W5.2 receipt uncertified'
        $gate.regressions = 'Wave 0, 1, 2, 3, 4, W5.1 and W5.2 PASS'
    }
    foreach ($relative in $manifest.Keys) { Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $manifest[$relative]) "Source changed during run: $relative" }
    if ($usingSnapshot) { $finalPaths = Get-Content $inventoryPath -Raw | ConvertFrom-Json } else { $finalPaths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons docs AGENTS.md) }
    Check (@(Compare-Object $paths $finalPaths).Count -eq 0) 'Source inventory changed during run'
    $gate.snapshot_matches_source = $true
    $gate.client_authority_separation = $true
    $gate.passed = $true
    $gate.certified = -not $SkipRegression
    Write-Output 'WAVE_5_PART_3_VALIDATION_PASS'
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
    Write-Output "WAVE_5_PART_3_EVIDENCE=$evidenceRoot"
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved)) { try { Remove-Item -LiteralPath $resolved -Recurse -Force } catch { Write-Warning ("Temporary cleanup incomplete at " + $resolved + ": " + $_.Exception.Message) } }
}
