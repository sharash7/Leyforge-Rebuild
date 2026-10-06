[CmdletBinding()]
param(
    [string] $GodotExecutable = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
    [switch] $SkipRegression,
    [string] $CertifiedRegressionEvidence = ''
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
# Pin the approved runner before executing it.
$approved = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.7 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_7\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf57-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$testProject = Join-Path $tempRoot 'project'
New-Item -ItemType Directory -Force $evidenceRoot,$testProject | Out-Null
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$processes = @{}
$gate = @{passed=$false;certified=$false;timestamp_utc=[DateTime]::UtcNow.ToString('o');runner=$godotPath;runner_sha256=(Get-FileHash $godotPath).Hash;manual_acceptance='PENDING_OWNER'}
function Check([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Start-Run([string] $Name, [string[]] $Arguments, [string] $ProfileName = $Name, [string] $Executable = $godotPath) {
    $app = Join-Path $tempRoot ($ProfileName + '-appdata')
    $local = Join-Path $tempRoot ($ProfileName + '-localappdata')
    New-Item -ItemType Directory -Force $app,$local | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
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
 Start-Run $Name @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $testProject 'tests/networking/w5_7_launch.ps1'),'-ProjectPath',$testProject,'-ProofDir',$evidenceRoot,'-ProofName',$Name,'-Mode',$Mode,'-Port',"$Port") $ProfileName 'powershell.exe'
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

function Read-GitBytes([string] $Relative) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'git.exe'
    $info.WorkingDirectory = $repositoryRoot
    $info.Arguments = 'show HEAD:' + $Relative
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    [void] $proc.Start()
    $buffer = New-Object IO.MemoryStream
    $proc.StandardOutput.BaseStream.CopyTo($buffer)
    $proc.WaitForExit()
    Check ($proc.ExitCode -eq 0) "Cannot project HEAD:$Relative"
    return ,$buffer.ToArray()
}


function Wait-Condition([string] $Name, [scriptblock] $Predicate, [string] $Label, [int] $Seconds = 12) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $report = Read-Report $Name
        if ($report -and (& $Predicate $report)) { Assert $report.passed $Label; return $report }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Label timeout"
}

function Assert([bool] $Condition,[string] $Message) { $script:checks++; Check $Condition $Message }
function Wait-Resources([string] $Name) { Wait-Condition $Name {param($r) $r.ready -and $r.resource_ready -and $r.survival_ready} "$Name fully ready" 60 }
function Wait-Ended([string] $Name) {
 $r=Wait-Condition $Name {param($r) $r.state -eq 'DISCONNECTED' -and -not $r.terrain_exists -and -not $r.player_exists -and $r.ended_visible} "$Name entire gameplay removed" 12
 Assert ($r.no_world_save -and $r.no_authority -and $r.teardown.input_disabled -and $r.teardown.replicas_removed -and $r.world_node_count -eq 0) "$Name teardown/save prohibition"
 return $r
}
function Record([string] $Name,[string] $Suffix) {
 $r=Read-Report $Name
 $r | ConvertTo-Json -Depth 32 | Set-Content (Join-Path $evidenceRoot "$Name-$Suffix.json") -Encoding UTF8
 return $r
}
function Stop-Probe([string] $Name) {
 [IO.File]::WriteAllText((Join-Path $evidenceRoot "$Name.stop"),'stop')
 Finish-Run $Name
}
$checks=0
$soak=@()

try {
    $snapshotInventory = Join-Path $repositoryRoot '.verification_snapshot_inventory.json'
    $usingSnapshot = Test-Path $snapshotInventory
    $paths = if ($usingSnapshot) { @(Get-Content $snapshotInventory -Raw | ConvertFrom-Json) } else { @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons docs AGENTS.md | Where-Object { $_ -notlike '*.gd.uid' -or @(& git -C $repositoryRoot ls-files -- $_).Count -gt 0 }) }
    $manifest = @{}
    $workingManifest = @{}
    $edits = if ($usingSnapshot) { $paths } else { @(& git -C $repositoryRoot diff HEAD --name-only) + @(& git -C $repositoryRoot ls-files --others --exclude-standard) }
    foreach ($relative in $paths) {
        $source = Join-Path $repositoryRoot $relative
        $target = Join-Path $testProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        $workingManifest[$relative] = (Get-FileHash -LiteralPath $source).Hash
        if ($usingSnapshot) {
            Copy-Item -LiteralPath $source -Destination $target
        } elseif ($relative -eq 'project.godot') {
            $text = [Text.Encoding]::UTF8.GetString((Read-GitBytes $relative))
            $text = [regex]::Replace($text,'config/version="[^"]+"','config/version="0.5.9-wave5-w5.7"')
            [IO.File]::WriteAllText($target,$text,(New-Object Text.UTF8Encoding($false)))
        } elseif ($relative -eq 'scenes/main/wave_1_playground.tscn' -or $relative -notin $edits) {
            [IO.File]::WriteAllBytes($target,(Read-GitBytes $relative))
        } else {
            $text = [IO.File]::ReadAllText($source).Replace("`r`n","`n")
            [IO.File]::WriteAllText($target,$text,(New-Object Text.UTF8Encoding($false)))
        }
        $manifest[$relative] = (Get-FileHash -LiteralPath $target).Hash
    }
    @($manifest.Keys) | ConvertTo-Json | Set-Content (Join-Path $testProject '.verification_snapshot_inventory.json') -Encoding UTF8
    $manifest | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'source_manifest.json') -Encoding UTF8
    $workingManifest | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'working_source_manifest.json') -Encoding UTF8
    $gate.publication_projection = $true
    Start-Run 'import' @('--headless','--editor','--path',$testProject,'--quit')
    Finish-Run 'import' 0 180000


    $gate.import_pass=$true
    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_7_focused.gd','--',"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    Check (Read-Report 'focused').passed 'Focused W5.7 matrix failed'
    $gate.focused_checks=(Read-Report 'focused').checks

    . (Join-Path $PSScriptRoot 'w5_7_owner_fixture.ps1')
    Start-Probe 'host' 'HOST' 'host' '' -1 25658
    [void](Wait-Resources 'host')
    $legacyProject=Join-Path $tempRoot 'accepted-w56'
    New-Item -ItemType Directory -Force $legacyProject | Out-Null
    $archive=Join-Path $tempRoot 'accepted-w56.tar'
    & git -C $repositoryRoot archive --format=tar --output=$archive cced5167004e3056c150bbd16fee25252c665843
    Check ($LASTEXITCODE -eq 0) 'Archive immutable accepted W5.6 source outside repo'
    & tar.exe -xf $archive -C $legacyProject
    Check ($LASTEXITCODE -eq 0) 'Extract historical protocol-5 client'
    Start-Run 'legacy-import' @('--headless','--editor','--path',$legacyProject,'--quit')
    Finish-Run 'legacy-import' 0 180000
    Start-Run 'legacy-client' @('--headless','--path',$legacyProject,'--script','res://tests/networking/w5_2_process.gd','--','--session=JOIN','--address=127.0.0.1','--port=25658',"--proof-dir=$evidenceRoot",'--proof-name=legacy-client')
    Finish-Run 'legacy-client' 0 20000
    $legacy=Read-Report 'legacy-client'
    Assert ($legacy.state -eq 'REJECTED' -and $legacy.reason -eq 'protocol_mismatch' -and $legacy.client_has_no_authority -and $legacy.client_world_save_absent) 'Actual accepted protocol-5 W5.6 OS process rejects cleanly'
    $gate.legacy_protocol5_client=$true
    $arena=Command 'host' @{op='arena'}; $y=[int]$arena.commands[-1].y
    $bench=Command 'host' @{op='repair_fixture';cell=@(0,$y,0)}
    $storage=Command 'host' @{op='repair_fixture';cell=@(-2,$y,0);content='leyforge:storage_box'}
    $kiln=Command 'host' @{op='resource_fixture';kind='kiln';cell=@(2,$y,-2)}
    Start-Probe 'client' 'JOIN' 'client' '' -1 25658
    $client=Wait-Resources 'client'; $id=$client.player_id; $clientPid=$client.pid
    $identityFile=Get-ChildItem (Join-Path $tempRoot 'client-appdata') -Recurse -Filter wave5-client-2.json | Select-Object -First 1
    Assert ($null -ne $identityFile) 'Isolated durable Client 2 profile exists'
    $identityHash=(Get-FileHash -LiteralPath $identityFile.FullName).Hash
    Start-Probe 'third' 'JOIN' 'third' '' -1 25658
    $third=Wait-Resources 'third';$thirdId=$third.player_id
    [void](Command 'host' @{op='survival_hold_tick';hold=$true})
    [void](Command 'host' @{op='w57_record_fixture';player_id=$id})
    [void](Command 'host' @{op='repair_items';player_id=$id})
    [void](Wait-Condition 'client' {param($r) $r.survival.thirst -eq 37} 'Client restores non-default survival')
    $before=Record 'client' 'before-soak'
    [void](Command 'client' @{op='resource';operation='select';args=@{slot=0}})
    $committed=Read-Report 'host'
    foreach($cycle in 1..10){
        $hostCycleBefore=Read-Report 'host'
        $live=Record 'client' "cycle-$cycle-live"
        $leaveStarted=[DateTime]::UtcNow
        [void](Command 'client' @{op='w57_leave'})
        $ended=Wait-Ended 'client'
        $h=Wait-Condition 'host' {param($r) @($r.bindings.PSObject.Properties).Count -eq 2 -and @($r.bodies.PSObject.Properties).Count -eq 1} "cycle $cycle removes live body and viewer"
        Assert ($h.characters.PSObject.Properties[$id] -and @($h.roster).Count -eq 3) "cycle $cycle retains one character"
        Assert ($h.personal_hash -ne '') "cycle $cycle host remains playable"
        $leaveMsec=([DateTime]::UtcNow-$leaveStarted).TotalMilliseconds
        $joinStarted=[DateTime]::UtcNow
        [void](Command 'client' @{op='w57_reconnect'})
        $rejoined=Wait-Resources 'client'
        Assert ($rejoined.pid -eq $clientPid -and $rejoined.player_id -eq $id -and $rejoined.generation -gt $live.generation) "cycle $cycle same process identity fresh generation"
        Assert ($rejoined.world_node_count -eq $live.world_node_count) "cycle $cycle no growing presentation nodes"
        Assert ($rejoined.personal_hash -eq $live.personal_hash -and $rejoined.survival.thirst -eq 37 -and $rejoined.personal.equipment[0].durability -eq 7) "cycle $cycle exact personal/tool/survival"
        [void](Command 'client' @{op='w57_stale_callback'})
        $callback=Read-Report 'client';Assert $callback.commands[-1].unchanged "cycle $cycle old callbacks cannot tear down rebuilt world"
        [void](Wait-Condition 'third' {param($r) $r.avatars -contains $id} "cycle $cycle fresh presence")
        $h=Read-Report 'host';Assert (@($h.bodies.PSObject.Properties).Count -eq 2 -and @($h.roster).Count -eq 3 -and $h.instances_unique) "cycle $cycle no ghost or duplicate identity"
        Assert (($h.totals | ConvertTo-Json -Compress) -eq ($hostCycleBefore.totals | ConvertTo-Json -Compress)) "cycle $cycle conserved whole-world resource total"
        $soak+=@{leave_teardown_msec=$leaveMsec;world_ready_msec=([DateTime]::UtcNow-$joinStarted).TotalMilliseconds;handshake_msec=$rejoined.lifecycle_metrics.handshake_msec;control_metrics=$rejoined.lifecycle_metrics;cycle=$cycle;pid=$rejoined.pid;generation=$rejoined.generation;bindings=$h.bindings;body_count=@($h.bodies.PSObject.Properties).Count;character_count=@($h.roster).Count;inventory_hash=$rejoined.personal_hash;totals=$h.totals}
    }
    [void](Command 'client' @{op='retry'})
    Start-Sleep -Milliseconds 400
    Assert ((Read-Report 'host').resource_commits -eq $committed.resource_commits) 'Exact completed retry survives same-host reconnect without second mutation'
    $soak | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $evidenceRoot 'reconnect-soak.json')
    # A resource mutation commits while its result is deliberately lost. New
    # bootstrap restores HOST truth; old pending requests are disposable.
    [void](Command 'host' @{op='resource_pause_pickup';active=$true})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),5.5)})
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(-2.5,($y+0.05),5.5)})
    Start-Sleep -Milliseconds 500
    $lostBefore=Read-Report 'host'
    $sent=Command 'client' @{op='w57_commit_without_result'}
    Assert $sent.commands[-1].sent 'Lost-result drop sent through ENet'
    $lostCommitted=Wait-Condition 'host' {param($r) $r.resource_commits -gt $lostBefore.resource_commits} 'Lost-result resource drop committed'
    [void](Wait-Condition 'client' {param($r) $r.dropped_results -gt 0 -and $r.pending_count -eq 1} 'Committed result lost before leave')
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    [void](Command 'client' @{op='w57_reconnect'});$fresh=Wait-Resources 'client'
    Assert ($fresh.pending_count -eq 0) 'New generation discards previous pending transaction'
    $conserved=Read-Report 'host'
    Assert (($conserved.totals|ConvertTo-Json -Compress) -eq ($lostBefore.totals|ConvertTo-Json -Compress)) 'Lost result conserves entire resource graph'
    [void](Command 'client' @{op='retry'});Start-Sleep -Milliseconds 400
    Assert ((Read-Report 'host').resource_commits -eq $lostCommitted.resource_commits) 'Committed lost-result retry has no duplicate drop'
    [void](Command 'client' @{op='w57_pending'})
    $unsentBefore=Read-Report 'host'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    [void](Command 'client' @{op='w57_reconnect'});$fresh=Wait-Resources 'client'
    Assert ($fresh.pending_count -eq 0 -and (Read-Report 'host').resource_commits -eq $unsentBefore.resource_commits) 'Unsent command never replays across reconnect'
    # Real held gathering is interrupted before its completion boundary.
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),3.5)})
    Start-Sleep -Milliseconds 500
    [void](Command 'client' @{op='look';cell=@(3,$y,0)})
    Start-Sleep -Milliseconds 300
    $harvestBefore=Read-Report 'host'
    [void](Command 'client' @{op='harvest_input';active=$true})
    $partial=Wait-Condition 'host' {param($r) $null -ne $r.held_actions.PSObject.Properties[$id] -and $r.held_actions.$id.work -gt 0 -and $r.held_actions.$id.work -lt $r.held_actions.$id.seconds} 'Actual held voxel harvest has partial progress'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    Start-Sleep -Milliseconds 1500
    $cancelled=Read-Report 'host'
    Assert ($null -eq $cancelled.held_actions.PSObject.Properties[$id]) 'Disconnect cancels partial held harvest'
    Assert (($cancelled.totals|ConvertTo-Json -Compress) -eq ($harvestBefore.totals|ConvertTo-Json -Compress)) 'Cancelled harvest produces no resource or delayed completion'
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    Start-Sleep -Milliseconds 1200
    Assert ($null -eq (Read-Report 'host').held_actions.PSObject.Properties[$id]) 'Reconnect never resumes the old held input'
    $harvestCommitted=Command 'client' @{op='gather_one';cell=@(3,$y,0)}
    Assert $harvestCommitted.commands[-1].removed 'Normal held harvest completes once before leave'
    $afterHarvest=Read-Report 'host'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    Assert (((Read-Report 'host').totals|ConvertTo-Json -Compress) -eq ($afterHarvest.totals|ConvertTo-Json -Compress)) 'Committed harvest output survives reconnect exactly once'
    # Restore a worn canonical tool after this intentional wear test.
    [void](Command 'host' @{op='w57_record_fixture';player_id=$id})
    # Valid remote rest over ENet, followed by leave and shared world advancement.
    $shelter=Command 'host' @{op='survival_shelter';player_id=$id}
    $rest=Command 'client' @{op='survival_rest';target=$shelter.commands[-1].target}
    Assert $rest.commands[-1].result.success 'Remote rest begins normally'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    $absent=Wait-Condition 'host' {param($r) @($r.bindings.PSObject.Properties).Count -eq 2} 'Resting client left'
    Assert ($null -eq $absent.rests.PSObject.Properties[$id] -and $null -eq $absent.held_actions.PSObject.Properties[$id]) 'Leave cancels transient rest and held actions'
    $biology=$absent.characters.$id.survival|ConvertTo-Json -Compress
    [void](Command 'host' @{op='actor_position';player_id=(Read-Report 'host').player_id;position=@(2.5,($y+0.05),0.5)})
    [void](Command 'host' @{op='resource';operation='start_process';args=@{target=$kiln.commands[-1].id;recipe='leyforge:charcoal_burn'}})
    $beforeTick=Read-Report 'host'
    [void](Command 'host' @{op='survival_step';seconds=30})
    $afterTick=Read-Report 'host'
    Assert (($afterTick.characters.$id.survival|ConvertTo-Json -Compress) -eq $biology) 'Absent character biology frozen while world advances'
    Assert ([Math]::Abs(($afterTick.elapsed-$beforeTick.elapsed)-30) -lt 0.01) 'Exactly one shared world clock advances'
    $station=$afterTick.resource_streams.PSObject.Properties['object/'+$kiln.commands[-1].id].Value.station
    Assert ($station.output[0].content -eq 'leyforge:charcoal' -and $station.output[0].quantity -eq 2) 'Shared kiln completes while client absent'
    [void](Command 'client' @{op='w57_reconnect'});$fresh=Wait-Resources 'client'
    Assert (-not $fresh.survival.resting) 'Reconnect does not resume rest'
    $freshStation=$fresh.resource_streams.PSObject.Properties['object/'+$kiln.commands[-1].id].Value.station
    Assert ($freshStation.output[0].quantity -eq 2) 'Fresh bootstrap sees completed shared kiln'
    # Accepted W5.6 death/recovery must survive a new connection generation.
    $death=Command 'host' @{op='survival_damage';player_id=$id;amount=100}
    Assert $death.commands[-1].success 'Authoritative fatal damage accepted'
    [void](Command 'host' @{op='survival_step';seconds=0})
    $recovery=Wait-Condition 'client' {param($r) $r.survival.health -eq 50} 'Death safe recovery authoritative bootstrap'
    $recoveryHost=Read-Report 'host'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    [void](Command 'client' @{op='w57_reconnect'});$fresh=Wait-Resources 'client'
    Assert ($fresh.survival.health -eq $recovery.survival.health -and $fresh.personal_hash -eq $recovery.personal_hash) 'Death-recovered character survives reconnect without pre-death resources'
    $currentRecovery=Read-Report 'host'
    Assert ([Math]::Abs($currentRecovery.characters.$id.transform.position[0]-$recoveryHost.characters.$id.transform.position[0]) -lt 0.15 -and [Math]::Abs($currentRecovery.characters.$id.transform.position[2]-$recoveryHost.characters.$id.transform.position[2]) -lt 0.15) 'Reconnect retains recovered authoritative transform'
    [void](Command 'host' @{op='w57_record_fixture';player_id=$id})
    # Full-backpack staging remains in authoritative memory and prevents host loss.
    [void](Command 'host' @{op='w57_stage_full';player_id=$id})
    $stage=Record 'host' 'full-staging'
    $blocked=Command 'host' @{op='w57_shutdown_blocked'}
    Assert (-not $blocked.commands[-1].accepted -and $blocked.state -eq 'HOSTING' -and -not $blocked.shutdown_fence) 'Save-blocked host quit returns to active authority'
    Assert ((Read-Report 'client').state -eq 'CONNECTED') 'Save failure retains connected client'
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    $h=Wait-Condition 'host' {param($r) @($r.bindings.PSObject.Properties).Count -eq 2} 'Staged client left'
    Assert ($null -ne $h.grids.PSObject.Properties[$id]) 'Full-backpack leave retains grid'
    $blocked=Command 'host' @{op='w57_shutdown_blocked'}
    Assert (-not $blocked.commands[-1].accepted) 'Inactive unresolved grid also blocks host save'
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    $r=Read-Report 'client';Assert ($null -ne $r.resource_streams.PSObject.Properties["grid/$id"]) 'Fresh reconnect recovers retained grid'
    [void](Command 'host' @{op='w57_resolve_capacity';player_id=$id})
    Start-Sleep -Milliseconds 500
    $r=Command 'client' @{op='resource';operation='close_grid';args=@{}}
    Assert $r.commands[-1].result.success 'Player safely resolves staging after capacity available'
    # Absent clients must rebuild current edits and shared functional state.
    [void](Command 'client' @{op='w57_leave'});[void](Wait-Ended 'client')
    [void](Wait-Condition 'host' {param($r) @($r.bindings.PSObject.Properties).Count -eq 2} 'Absent edit boundary')
    [void](Command 'host' @{op='edit';cell=@(4,$y,0);block='leyforge:oak_planks'})
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    $r=Read-Report 'client'
    Assert (@($r.overrides | Where-Object { $_.block -eq 'leyforge:oak_planks' -and $_.position[0] -eq 4 }).Count -eq 1) 'Fresh initial sync includes edits while absent'
    $saveMeasure=Command 'host' @{op='w57_save_measure'}
    Assert $saveMeasure.commands[-1].saved 'F5 graph snapshot succeeds with connected clients'
    $gate.save_msec=$saveMeasure.commands[-1].save_msec
    $saved=Record 'host' 'saved-before-f10'
    [void](Command 'client' @{op='w57_ui';manual=$true})
    [void](Command 'host' @{op='repair_key';code=73})
    # Use actual F10 input; unlike a direct save-and-quit method this tests routing.
    [IO.File]::WriteAllText((Join-Path $evidenceRoot 'host.command.json'),(@{op='w57_f10'}|ConvertTo-Json -Compress))
    $gracefulStarted=[DateTime]::UtcNow
    Finish-Run 'host' 0 20000
    $ended=Wait-Ended 'client';Assert ($ended.reason -eq 'host_shutdown') 'HOST F10 session-closing fact'
    $gate.graceful_loss_teardown_msec=([DateTime]::UtcNow-$gracefulStarted).TotalMilliseconds
    [void](Wait-Ended 'third')
    [void](Record 'client' 'host-f10-ended');[void](Record 'third' 'host-f10-ended')
    Start-Probe 'host-restart' 'HOST' 'host' '' -1 25658
    $h=Wait-Resources 'host-restart'
    Assert ($h.loaded_graph_hash -eq $saved.saved_graph_hash) 'Graceful restart restores exact saved authoritative graph'
    Assert (@($h.roster).Count -eq 3 -and $h.characters.$id.resources.equipment[0].durability -eq 7) 'Graceful host restart preserves both durable clients and tool'
    [void](Command 'client' @{op='w57_reconnect'});$r=Wait-Resources 'client'
    Assert ($r.pid -eq $clientPid -and $r.player_id -eq $id) 'Reconnect after host process restart'
    [void](Command 'third' @{op='w57_reconnect'});[void](Wait-Resources 'third')
    # Real OS WM_CLOSE, with a fully synchronized active JOIN.
    $windowHost=Get-Process -Id $h.pid
    Assert ($windowHost.CloseMainWindow()) 'OS window-X request delivered'
    Finish-Run 'host-restart' 0 20000
    $ended=Wait-Ended 'client';Assert ($ended.reason -eq 'host_shutdown') 'HOST window X saves then ends joined gameplay'
    [void](Record 'client' 'window-x-ended');[void](Wait-Ended 'third')
    Start-Probe 'host-crash' 'HOST' 'host' '' -1 25658
    $h=Wait-Resources 'host-crash'
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    [void](Command 'third' @{op='w57_reconnect'});[void](Wait-Resources 'third')
    # Explicit saved checkpoint plus unsaved voxel mutation.
    [void](Command 'host-crash' @{op='save'})
    $crashSaved=Record 'host-crash' 'crash-checkpoint'
    [void](Command 'host-crash' @{op='edit';cell=@(5,$y,0);block='leyforge:oak_planks'})
    [void](Command 'host-crash' @{op='actor_position';player_id=$id;position=@(3.5,($y+50),3.5)})
    [void](Command 'client' @{op='move'})
    $falling=Wait-Condition 'client' {param($r) $r.velocity[1] -lt -1} 'Actual JOIN moving/falling before authority loss'
    [void](Command 'client' @{op='w57_ui'})
    [void](Command 'client' @{op='w57_pending'})
    $atLoss=Record 'client' 'moving-falling-pending-before-kill'
    Assert ($atLoss.velocity[1] -lt -1 -and $atLoss.pending_count -eq 1) 'Client is actually falling with a pending transaction when HOST is killed'
    $killedAt=[DateTime]::UtcNow
    Stop-Process -Id $h.pid -Force
    [void]$processes['host-crash'].process.WaitForExit(5000)
    $ended=Wait-Ended 'client'
    $gate.abrupt_loss_detection_msec=([DateTime]::UtcNow-$killedAt).TotalMilliseconds
    Assert ($ended.reason -in @('server_disconnected','server_timeout')) 'Forced HOST process kill ends JOIN'
    [void](Record 'client' 'force-kill-ended');[void](Wait-Ended 'third');[void](Record 'third' 'force-kill-ended')
    # Failed reconnect is one bounded attempt and retains the ended view.
    [void](Command 'client' @{op='w57_reconnect'})
    $failed=Wait-Condition 'client' {param($r) $r.state -eq 'CONNECTION_FAILED' -and $r.ended_visible -and -not $r.terrain_exists} 'Offline host reconnect fails visibly' 12
    Assert $failed.no_world_save 'Failed reconnect has no authoritative save'
    Start-Probe 'host-recovered' 'HOST' 'host' '' -1 25658
    $h=Wait-Resources 'host-recovered'
    Assert ($h.loaded_graph_hash -eq $crashSaved.saved_graph_hash) 'Crash restart restores exact last successful authoritative graph'
    Assert (@($h.overrides | Where-Object { $_.block -eq 'leyforge:oak_planks' -and $_.position[0] -eq 5 }).Count -eq 0) 'Crash restores last successful save, unsaved edit absent'
    [void](Command 'client' @{op='w57_reconnect'});[void](Wait-Resources 'client')
    # A real Client process restart continues to use its existing identity file.
    [IO.File]::WriteAllText((Join-Path $evidenceRoot 'client.command.json'),(@{op='w57_f10'}|ConvertTo-Json -Compress))
    Finish-Run 'client' 0 20000
    [void](Wait-Condition 'host-recovered' {param($r) @($r.bindings.PSObject.Properties).Count -eq 1} 'Client F10 removes body')
    Start-Probe 'client-restart' 'JOIN' 'client' '' -1 25658
    $r=Wait-Resources 'client-restart'
    Assert ($r.player_id -eq $id -and $r.pid -ne $clientPid) 'Process restart reuses same durable identity'

    # Each functional context is exercised over ENet before a real HOST kill.
    $uiMatrix=@()
    $currentHost='host-recovered'
    foreach($context in @(
        @{kind='Manual'},
        @{kind='Workbench';id=$bench.commands[-1].id;position=@(0.5,($y+0.05),3.5)},
        @{kind='Storage';id=$storage.commands[-1].id;position=@(-1.5,($y+0.05),2.5)},
        @{kind='Kiln';id=$kiln.commands[-1].id;position=@(2.5,($y+0.05),0.5)}
    )){
        if($context.kind -eq 'Manual'){
            $opened=Command 'client-restart' @{op='w57_ui';manual=$true}
            Assert ($opened.commands[-1].ui_open -and $opened.commands[-1].manual_visible) 'Actual Crafting Manual open before forced HOST loss'
        }else{
            [void](Command $currentHost @{op='actor_position';player_id=$id;position=$context.position})
            Start-Sleep -Milliseconds 500
            $opened=Command 'client-restart' @{op='w57_context';id=$context.id}
            Assert ($opened.commands[-1].accepted -and $opened.commands[-1].opened) ($context.kind+' actual authorized UI open')
        }
        $h=Read-Report $currentHost
        Stop-Process -Id $h.pid -Force
        [void]$processes[$currentHost].process.WaitForExit(5000)
        $ended=Wait-Ended 'client-restart'
        $uiMatrix+=@{context=$context.kind;ended=$ended.teardown;reason=$ended.reason}
        [void](Record 'client-restart' ('ui-'+$context.kind+'-ended'))
        $currentHost='host-after-'+$context.kind
        Start-Probe $currentHost 'HOST' 'host' '' -1 25658
        [void](Wait-Resources $currentHost)
        [void](Command 'client-restart' @{op='w57_reconnect'});[void](Wait-Resources 'client-restart')
    }
    [void](Command $currentHost @{op='save'})
    $gate.ui_open_loss_matrix=$uiMatrix
    $gate.final_host=Record $currentHost 'final'
    # A reconnect to a different world is rejected before world/character bootstrap.
    $finalClient=Read-Report 'client-restart'
    Assert ((Get-Process -Id $finalClient.pid).CloseMainWindow()) 'Client window X delivered'
    Finish-Run 'client-restart' 0 20000
    [void](Wait-Condition $currentHost {param($r) @($r.bindings.PSObject.Properties).Count -eq 1 -and @($r.bodies.PSObject.Properties).Count -eq 0} 'Client window X removes body/viewer and keeps HOST alive')
    Stop-Probe $currentHost
    # Use the existing third client's real previous-world ended flow.

    Start-Probe 'host-otherworld' 'HOST' 'host' '' -1 25658
    [void](Wait-Resources 'host-otherworld')
    [void](Command 'third' @{op='w57_reconnect'})
    $mismatch=Wait-Condition 'third' {param($r) $r.state -eq 'REJECTED' -and $r.reason -eq 'world_mismatch' -and -not $r.terrain_exists} 'Different world reconnect rejects before bootstrap'
    Assert ($mismatch.no_world_save -and $mismatch.no_authority) 'Changed world never merges authority or writes save'
    $wrong=Read-Report 'host-otherworld';Assert (@($wrong.roster).Count -eq 1) 'Different world retains separate character roster'
    Assert ((Get-FileHash -LiteralPath $identityFile.FullName).Hash -eq $identityHash) 'Every teardown/reconnect preserves exact durable identity bytes'
    $gate.identity_hash=$identityHash
    Stop-Probe 'host-otherworld'
    $gate.real_process_checks=$checks;$gate.reconnect_cycles=10;$gate.reconnect_success_rate=1.0
    foreach($name in @('third')){Stop-Probe $name}
    $testProject=$originalProofProject
    if(-not $SkipRegression -and -not [string]::IsNullOrEmpty($CertifiedRegressionEvidence)){
        $priorRoot=(Resolve-Path -LiteralPath $CertifiedRegressionEvidence).Path
        $prior=Get-Content (Join-Path $priorRoot 'gate.json') -Raw | ConvertFrom-Json
        Assert ($prior.passed -and $prior.certified -and $prior.runner_sha256 -eq $gate.runner_sha256) 'Reused complete regression is certified with the exact runner'
        $priorManifest=Get-Content (Join-Path $priorRoot 'source_manifest.json') -Raw | ConvertFrom-Json
        Assert (@($priorManifest.PSObject.Properties).Count -eq $manifest.Count) 'Reused regression pins the entire same candidate inventory'
        foreach($relative in $manifest.Keys){Check ($priorManifest.PSObject.Properties[$relative] -and $priorManifest.PSObject.Properties[$relative].Value -eq $manifest[$relative]) "Reused regression source mismatch: $relative"}
        & robocopy.exe $priorRoot (Join-Path $evidenceRoot 'regression_w56_repair') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
        Check ($LASTEXITCODE -lt 8) 'Preserve complete source-identical certified regression evidence'
        $gate.regressions=$prior.regressions+'; W5.6 Repair 1 PASS'
        $gate.regression_reused_with_full_source_identity=$true
    }elseif(-not $SkipRegression){
        Start-Run 'regression' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $testProject 'tools/development/verify_wave_5_part_6_repair_1.ps1')) 'regression' 'powershell.exe'
        Finish-Run 'regression' 0 2400000
        & robocopy.exe (Join-Path $testProject '.verification/wave5/w5_6_repair_1') (Join-Path $evidenceRoot 'regression_w56_repair') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
        Check ($LASTEXITCODE -lt 8) 'Preserve complete regression evidence'
        $last=Get-ChildItem (Join-Path $evidenceRoot 'regression_w56_repair') -Directory | Sort-Object Name | Select-Object -Last 1
        $prior=Get-Content (Join-Path $last.FullName 'gate.json') -Raw | ConvertFrom-Json
        Assert ($prior.passed -and $prior.certified) 'Complete Wave 0-4 and W5.1-W5.6 Repair 1 regressions certified'
        $gate.regressions=$prior.regressions+'; W5.6 Repair 1 PASS'
    }
    foreach($relative in $workingManifest.Keys){Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $workingManifest[$relative]) "Source changed: $relative"}
    $gate.passed=$true;$gate.certified=-not $SkipRegression
    Write-Output 'WAVE_5_PART_7_VALIDATION_PASS'
} catch {$gate.failure=$_.Exception.Message;throw}
finally {
    # A failed GUI assertion must also stop the actual owner-launched children.
    foreach($name in $processes.Keys){[IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.stop"),'stop')}
    foreach($name in $processes.Keys){[void]$processes[$name].process.WaitForExit(3000)}
    $resolvedTemp=[IO.Path]::GetFullPath($tempRoot)
    if($resolvedTemp.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){
        foreach($child in Get-CimInstance Win32_Process -Filter "Name like 'godot%exe'"){
            if($child.CommandLine -and $child.CommandLine.Contains($resolvedTemp)){
                $owned=Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
                if($owned){[void]$owned.CloseMainWindow();if(-not $owned.WaitForExit(2000)){Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue}}
            }
        }
    }
    foreach($name in $processes.Keys){
        $entry=$processes[$name]
        if(-not $entry.process.HasExited){$entry.process.Kill();$entry.process.WaitForExit()}
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.log"),($entry.stdout.Result+$entry.stderr.Result))
    }
    $gate | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $evidenceRoot gate.json) -Encoding UTF8
    Write-Output "WAVE_5_PART_7_EVIDENCE=$evidenceRoot"
}
