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
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.6 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_6\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf56-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
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
    Start-Run $Name @('--path',$testProject,'--script','res://tests/networking/w5_6_process.gd','--',"--session=$Mode","--port=$Port","--world-id=proof-world",'--seed=184552221',"--proof-dir=$evidenceRoot","--proof-name=$Name","--proof-fault=$Fault","--proof-hold=$Hold","--w56-proof") $ProfileName
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
function Drop-Quantity($Report) { $total = 0; foreach ($drop in $Report.drops) { $total += [int] $drop.stack.quantity }; return $total }
function Body($HostReport,[string] $Id) { return $HostReport.bodies.PSObject.Properties[$Id].Value }
function Distance($A,$B) {
    return [Math]::Sqrt([Math]::Pow(($A[0]-$B[0]),2)+[Math]::Pow(($A[1]-$B[1]),2)+[Math]::Pow(($A[2]-$B[2]),2))
}
function HorizontalSpeed($State) { return [Math]::Sqrt([Math]::Pow($State.velocity[0],2)+[Math]::Pow($State.velocity[2],2)) }
function Wait-Converged([string] $Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $report = Read-Report $Name
        $hostNow = Read-Report "host"
        $bodyNow = if ($report -and $hostNow) { Body $hostNow $report.player_id } else { $null }
        if ($report -and $bodyNow -and $report.error -lt 0.12 -and (Distance $report.position $bodyNow.state.position) -lt 0.12 -and $report.grounded -and (HorizontalSpeed $report) -lt 0.1) { return $report }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name convergence failed"
}

function Wait-Resources([string] $Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    do {
        $report = Read-Report $Name
        if ($report -and $report.ready -and $report.resource_ready) { Assert $report.passed "$Name resource assertions"; return $report }
        if ($processes[$Name].process.HasExited) { Finish-Run $Name; throw "$Name exited before resources" }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name resource sync timeout"
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
function Quantity($Personal,[string] $Content) {
    $count = 0
    foreach ($s in @($Personal.inventory)+@($Personal.equipment)) { if ($s -and $s.content -eq $Content) { $count += [int]$s.quantity } }
    return $count
}
function Race([string] $Left, [string] $Right, [string] $Label) {
    $counts = @{}
    foreach ($name in @($Left,$Right)) {
        $counts[$name] = @((Read-Report $name).commands).Count
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.command.json"),'{"op":"resource_release"}')
    }
    $a = Wait-Condition $Left {param($r) @($r.commands).Count -gt $counts[$Left]} "$Label left response"
    $b = Wait-Condition $Right {param($r) @($r.commands).Count -gt $counts[$Right]} "$Label right response"
    Assert (([int][bool]$a.commands[-1].result.success + [int][bool]$b.commands[-1].result.success) -eq 1) "$Label exactly one winner"
    $h = Read-Report 'host'
    Assert $h.instances_unique "$Label global instance uniqueness"
    $script:races += @{label=$Label;left=$a.commands[-1].result;right=$b.commands[-1].result;totals=$h.totals}
    return @($a,$b)
}
function Queue-Withdraw([string] $Name,[string] $Endpoint,[string] $Content,[int] $Quantity) {
    [void](Command $Name @{op='resource_queue';operation='transfer';content=$Content;args=@{source=$Endpoint;destination='inventory';destination_slot=-1;quantity=$Quantity}})
}
$races = @()
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

function Harvest([string] $Name, $Cell) {
    $r = Command $Name @{op='gather_one';cell=$Cell}
    Assert $r.commands[-1].removed 'Held input removes exactly its target'
    Start-Sleep -Milliseconds 400
}

try {
    $paths = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- project.godot src content scenes tests tools addons docs AGENTS.md | Where-Object { $_ -notlike '*.gd.uid' -or @(& git -C $repositoryRoot ls-files -- $_).Count -gt 0 })
    $manifest = @{}
    $workingManifest = @{}
    $edits = @(& git -C $repositoryRoot diff HEAD --name-only) + @(& git -C $repositoryRoot ls-files --others --exclude-standard)
    foreach ($relative in $paths) {
        $source = Join-Path $repositoryRoot $relative
        $target = Join-Path $testProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        $workingManifest[$relative] = (Get-FileHash -LiteralPath $source).Hash
        if ($relative -eq 'project.godot') {
            $text = [Text.Encoding]::UTF8.GetString((Read-GitBytes $relative))
            $text = [regex]::Replace($text,'config/version="[^"]+"','config/version="0.5.7-wave5-w5.6"')
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

    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_6_focused.gd','--',"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    $focused = Read-Report 'focused'
    Check $focused.passed 'W5.6 focused tests failed'
    $gate.focused_checks = $focused.checks
    Start-Probe 'host' 'HOST' 'host'
    [void](Wait-Ready 'host')
    Start-Run 'old_protocol' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_2_process.gd','--','--session=JOIN','--port=25652',"--proof-dir=$evidenceRoot",'--proof-name=old_protocol','--proof-fault=w55_protocol_mismatch') 'old-protocol'
    Finish-Run 'old_protocol'
    Assert ((Read-Report 'old_protocol').reason -eq 'protocol_mismatch') 'Protocol-4 W5.5 Client rejects cleanly over ENet'
    $arena = Command 'host' @{op='arena'}
    $y = [int]$arena.commands[-1].y
    [void](Command 'host' @{op='survival_runway';y=$y})
    Start-Probe 'client' 'JOIN' 'client'
    $client = Wait-Resources 'client'
    $client = Wait-Condition 'client' {param($r) $r.survival_ready} 'Owner survival bootstrap'
    $id = $client.player_id
    Start-Probe 'third' 'JOIN' 'third'
    $third = Wait-Resources 'third'
    $third = Wait-Condition 'third' {param($r) $r.survival_ready} 'Third owner bootstrap'
    $thirdId = $third.player_id
    Assert ($id -ne $thirdId) 'Distinct third identity'
    Assert ($client.survival.health -eq 100 -and -not $client.survival.thirst_enabled -and $client.survival_hud -match 'Health') 'Client HUD uses HOST Standard state'
    Assert ($client.survival_hud -notmatch 'Water') 'Standard hydration hidden'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(1.5,($y+0.05),4.5)})
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(-1.5,($y+0.05),4.5)})
    Start-Sleep -Milliseconds 700
    $before = Read-Report 'host'
    [void](Command 'client' @{op='move';sprint=$true})
    [void](Wait-Condition 'client' {param($r) $r.survival.stamina -lt 85} 'Authoritative sprint expenditure')
    $spent = Read-Report 'host'
    Assert ($spent.characters.$id.survival.stamina -lt 90 -and $spent.characters.$thirdId.survival.stamina -eq 100 -and $spent.survival.stamina -eq 100) 'Client authoritative stamina independent from host and third'
    [void](Wait-Condition 'client' {param($r) $r.survival.stamina -lt 1} 'Real continuous sprint reaches insufficient stamina' 30)
    [void](Wait-Condition 'host' {param($r) $r.characters.$id.survival.stamina -lt 1 -and (HorizontalSpeed (Body $r $id).state) -le 5.05} 'HOST denies sprint at depleted reserve' 15)
    [void](Command 'client' @{op='survival_inventory';open=$true})
    $recovered = Wait-Condition 'client' {param($r) $r.survival.stamina -gt 99} 'UI-open stamina recovery' 30
    Assert ($recovered.inventory_open -and -not $recovered.paused -and $recovered.time_scale -eq 1) 'Inventory controls only; biology/physics continue'
    [void](Command 'client' @{op='move';direction='stop'})
    [void](Command 'client' @{op='survival_inventory';open=$false})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(1.5,($y+0.05),4.5)})
    Start-Sleep -Milliseconds 500
    [void](Command 'host' @{op='survival_inventory';open=$true})
    [void](Command 'client' @{op='move';sprint=$true})
    [void](Wait-Condition 'client' {param($r) $r.survival.stamina -lt 95} 'Remote sprint while HOST Inventory open')
    Assert ((Read-Report 'client').survival.stamina -lt 99 -and (Read-Report 'host').inventory_open) 'Host Inventory does not pause remote sprint biology'
    [void](Command 'client' @{op='move';direction='stop'})
    [void](Command 'host' @{op='survival_inventory';open=$false})
    # Guarded fixtures only live in this separately invoked test driver.
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{stamina=0;fatigue=100}})
    [void](Command 'client' @{op='survival_sprint_spam'})
    Start-Sleep -Milliseconds 250
    $empty = Read-Report 'host'
    Assert ((HorizontalSpeed (Body $empty $id).state) -le 5.1 -and $empty.characters.$id.survival.stamina -ge 0) 'Sprint spoof cannot force speed or negative stamina'
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{stamina=85;fatigue=8;hunger=45;health=86}})
    # Legitimate remote food/water gathering is covered by the complete W5.5
    # regression; these fixtures isolate consume atomicity from harvest timing.
    [void](Command 'host' @{op='survival_items';player_id=$id})
    Start-Sleep -Milliseconds 500
    $foodBefore = Quantity (Read-Report 'client').personal 'leyforge:provisions'
    $consume = Command 'client' @{op='survival_consume';content='leyforge:provisions'}
    Assert ($consume.commands[-1].result.success -and $consume.survival.hunger -gt 74 -and (Quantity $consume.personal 'leyforge:provisions') -eq ($foodBefore-1)) 'Remote consume commits item and +30 hunger'
    $retry = Command 'client' @{op='retry'}
    Assert ((Quantity $retry.personal 'leyforge:provisions') -eq ($foodBefore-1) -and $retry.survival.hunger -gt 74 -and $retry.survival.hunger -lt 76) 'Exact consume retry one item and one effect'
    [void](Command 'host' @{op='survival_hold_tick';hold=$true})
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{hunger=100;thirst=40}})
    Start-Sleep -Milliseconds 200
    $full = Command 'client' @{op='survival_consume';content='leyforge:provisions'}
    Assert (-not $full.commands[-1].result.success -and (Quantity $full.personal 'leyforge:provisions') -eq ($foodBefore-1)) 'Full hunger consume no-op conserves item'
    $waterBefore = Quantity $full.personal 'leyforge:drinking_water'
    $water = Command 'client' @{op='survival_consume';content='leyforge:drinking_water'}
    Assert (-not $water.commands[-1].result.success -and (Quantity $water.personal 'leyforge:drinking_water') -eq $waterBefore -and $water.survival.thirst -eq 40 -and -not $water.survival.thirst_enabled) 'Standard water no-op'
    [void](Command 'host' @{op='survival_set';player_id=$id;profile='Harsh'})
    Start-Sleep -Milliseconds 200
    $water = Command 'client' @{op='survival_consume';content='leyforge:drinking_water'}
    Assert ($water.commands[-1].result.success -and $water.survival.thirst -eq 75 -and $water.survival.thirst_enabled -and $water.survival_hud -match 'Water') 'Focused Harsh hydration owner view'
    [void](Command 'host' @{op='survival_set';player_id=$id;profile='Standard'})
    [void](Command 'host' @{op='survival_hold_tick';hold=$false})
    $hostOrigin = (Read-Report 'host').position
    $hostId = (Read-Report 'host').player_id
    [void](Command 'host' @{op='host_distance';player_id=$id;distance=180})
    [void](Wait-Condition 'host' {param($r) (Distance $r.position (Body $r $id).state.position) -gt 128 -and -not (Body $r $id).visible -and (Body $r $id).loaded} 'Remote terrain remains authoritative beyond HOST view')
    $farStamina = (Read-Report 'client').survival.stamina
    [void](Command 'client' @{op='move';sprint=$true})
    [void](Wait-Condition 'client' {param($r) $r.survival.stamina -lt ($farStamina-3)} 'Remote biology sprint beyond HOST camera')
    [void](Command 'client' @{op='move';direction='stop'})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),4.5)})
    Start-Sleep -Milliseconds 500
    $shelter = Command 'host' @{op='survival_shelter';player_id=$id}
    $mat = $shelter.commands[-1].target
    $matCell = $shelter.commands[-1].cell
    Start-Sleep -Milliseconds 700
    $noShelter = Command 'third' @{op='survival_rest';target=$mat}
    Assert (-not $noShelter.commands[-1].result.success -and -not $noShelter.survival.resting) 'Another actor without cover cannot claim shelter/rest'
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(-1.5,($y+0.05),-12.5)})
    Start-Sleep -Milliseconds 500
    $tooFar = Command 'third' @{op='survival_rest';target=$mat}
    Assert (-not $tooFar.commands[-1].result.success -and -not $tooFar.survival.resting) 'Remote rest out of range rejected'
    $noMat = Command 'client' @{op='survival_rest';target=('f'*32)}
    Assert (-not $noMat.commands[-1].result.success -and -not $noMat.survival.resting) 'Absent Rest Mat rejected'
    $rest = Command 'client' @{op='survival_rest';target=$mat}
    Assert ($rest.commands[-1].result.success -and $rest.survival.resting -and -not (Read-Report 'third').survival.resting -and -not (Read-Report 'host').survival.resting) 'Rest is actor-specific and HOST validates shelter'
    [void](Command 'client' @{op='move';direction='move_back'})
    $restEnd = Wait-Condition 'client' {param($r) -not $r.survival.resting} 'Movement cancels rest'
    [void](Command 'client' @{op='move';direction='stop'})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),4.5)})
    Start-Sleep -Milliseconds 500
    [void](Command 'client' @{op='survival_rest';target=$mat})
    [void](Command 'host' @{op='survival_rest_invalidate';cell=$matCell})
    [void](Wait-Condition 'client' {param($r) -not $r.survival.resting} 'Object invalidation cancels rest')
    # No valid wire command carries health/damage/death/shelter claims.
    $healthBefore = (Read-Report 'host').characters.$id.survival.health
    foreach ($p in @(@{kind='survival_damage';damage=-100},@{kind='survival_state';health=100;alive=$true},@{kind='survival_resync';player_id=$thirdId})) {
        [void](Command 'client' @{op='survival_spoof';packet=$p})
    }
    Assert ((Read-Report 'host').characters.$id.survival.health -le ($healthBefore+0.2)) 'Damage/health/owner-query spoof leaves authoritative biology unchanged'
    [void](Command 'client' @{op='survival_loss';active=$true})
    $lostRevision = (Read-Report 'client').survival.revision
    Start-Sleep -Milliseconds 500
    Assert ((Read-Report 'client').survival.revision -eq $lostRevision) 'Periodic state loss injected'
    [void](Command 'client' @{op='survival_loss';active=$false})
    [void](Wait-Condition 'client' {param($r) $r.survival.revision -gt $lostRevision} 'Complete snapshot convergence after loss')
    [void](Command 'client' @{op='survival_resync'})
    [void](Wait-Condition 'client' {param($r) $r.survival_ready} 'Bounded missing owner resync')
    $rejectedSurvival = (Read-Report 'client').survival_metrics.rejected
    [void](Command 'host' @{op='survival_corrupt';player_id=$id})
    Start-Sleep -Milliseconds 300
    Assert ((Read-Report 'client').survival_metrics.rejected -ge ($rejectedSurvival+6) -and (Read-Report 'client').survival_ready) 'Real transport rejects corrupt owner state without losing healthy replica'
    # Real remote HOST body falls under gravity; Client sends no damage result.
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),4.5)})
    Start-Sleep -Milliseconds 400
    $fallHealth = (Read-Report 'client').survival.health
    [void](Command 'client' @{op='survival_inventory';open=$true})
    [void](Command 'host' @{op='survival_fall';player_id=$id})
    $fall = Wait-Condition 'client' {param($r) $r.survival.health -lt ($fallHealth-1)} 'Remote real physics fall damage'
    Assert ($fall.inventory_open -and -not $fall.paused -and $fall.time_scale -eq 1) 'Client Inventory cannot stop falling or grant damage immunity'
    [void](Command 'client' @{op='survival_inventory';open=$false})
    $hostFall = Wait-Condition 'host' {param($r) @($r.survival_events | Where-Object { $_.event -eq 'fall' -and $_.actor -eq $id }).Count -gt 0} 'HOST landing receipt'
    $event = @($hostFall.survival_events | Where-Object { $_.event -eq 'fall' -and $_.actor -eq $id })[-1]
    Assert ($event.speed -gt 12 -and [Math]::Abs($event.damage-[Math]::Min(100.0,($event.speed-12)*3)) -lt 0.0001 -and $hostFall.survival.health -eq 100) 'HOST landing formula matches Wave 4; host health independent'
    $equipped = Command 'client' @{op='equip';content='leyforge:wooden_pickaxe'}
    Assert ($equipped.commands[-1].result.success -and $equipped.personal.equipment[0].instance) 'Death proof has a real stateful equipped instance'
    [void](Command 'client' @{op='resource';operation='open_context';args=@{target=''}})
    $staged = Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;destination='grid';destination_slot=0}
    Assert $staged.commands[-1].result.success 'Death proof has non-empty crafting staging'
    [void](Command 'client' @{op='survival_input_capture'})
    $oldSnapshot = Command 'host' @{op='survival_snapshot_capture';player_id=$id}
    $staleSnapshot = $oldSnapshot.commands[-1].packet
    $beforeDeath = Read-Report 'host'
    $death = Command 'host' @{op='survival_damage';player_id=$id;amount=100}
    $respawn = Wait-Condition 'client' {param($r) $r.input_epoch -gt 1 -and $r.survival.health -eq 50} 'Authoritative recovery reset'
    Assert ($respawn.survival.stamina -ge 50 -and $respawn.player_id -eq $id -and ((Read-Report 'host').characters.$id.resources | ConvertTo-Json -Depth 20 -Compress) -eq ($beforeDeath.characters.$id.resources | ConvertTo-Json -Depth 20 -Compress)) 'Recovery retains identity/resources and 50/50 biology'
    Assert (((Read-Report 'host').resource_streams.PSObject.Properties['grid/'+$id].Value | ConvertTo-Json -Depth 20 -Compress) -eq ($beforeDeath.resource_streams.PSObject.Properties['grid/'+$id].Value | ConvertTo-Json -Depth 20 -Compress)) 'Death retains non-empty crafting staging exactly'
    $released = Command 'client' @{op='resource';operation='close_grid';args=@{}}
    Assert ($released.commands[-1].result.success -and (Quantity $released.personal 'leyforge:oak_planks') -eq 2 -and $released.personal.equipment[0].instance -eq $equipped.personal.equipment[0].instance) 'Recovered actor releases staging without loss or tool replacement'
    $rejectedBefore = (Read-Report 'host').rejected_packets
    [void](Command 'client' @{op='survival_stale_input'})
    [void](Command 'host' @{op='survival_old_snapshot';player_id=$id;packet=$staleSnapshot})
    Start-Sleep -Milliseconds 200
    Assert ((Read-Report 'host').rejected_packets -gt $rejectedBefore -and (Read-Report 'client').input_epoch -eq $respawn.input_epoch -and (Read-Report 'client').survival.health -ge 50) 'Stale pre-death input and snapshots cannot cross recovery epochs'
    [void](Command 'host' @{op='resource_fixture';kind='kiln';cell=@(3,$y,3)})
    [void](Command 'host' @{op='actor_position';player_id=$hostId;position=$hostOrigin})
    $kiln = @((Read-Report 'host').objects | Where-Object content -eq 'leyforge:kiln')[-1].instance
    [void](Command 'host' @{op='resource';operation='start_process';args=@{target=$kiln;recipe='leyforge:charcoal_burn'}})
    $invariant = Command 'host' @{op='survival_tick_invariant'}
    $measure = $invariant.commands[-1].measurements
    Assert ([Math]::Abs($measure[0].elapsed-2) -lt 0.000001 -and [Math]::Abs($measure[1].elapsed-2) -lt 0.000001 -and [Math]::Abs($measure[2].elapsed-2) -lt 0.000001) 'Production world elapsed independent of 1/2/3 active players'
    Assert (($measure[0].objects | ConvertTo-Json -Depth 20 -Compress) -eq ($measure[1].objects | ConvertTo-Json -Depth 20 -Compress) -and ($measure[1].objects | ConvertTo-Json -Depth 20 -Compress) -eq ($measure[2].objects | ConvertTo-Json -Depth 20 -Compress)) 'Identical kiln progress with 1/2/3 players'
    $gate.world_tick_invariant = $measure
    # Capture latest timing on disconnect, then prove inactive character freeze.
    Stop-Probe 'client'
    [void](Wait-Bindings 2)
    $frozen = (Read-Report 'host').characters.$id
    Start-Sleep -Milliseconds 1200
    Assert (((Read-Report 'host').characters.$id.survival | ConvertTo-Json -Depth 10 -Compress) -eq ($frozen.survival | ConvertTo-Json -Depth 10 -Compress)) 'Disconnected survival timing/values frozen exactly'
    Start-Probe 'reconnect' 'JOIN' 'client'
    $again = Wait-Resources 'reconnect'
    $again = Wait-Condition 'reconnect' {param($r) $r.survival_ready} 'Reliable retained non-default survival bootstrap'
    Assert ($again.player_id -eq $id -and $again.survival.health -lt 60 -and ($again.personal | ConvertTo-Json -Depth 20 -Compress) -eq ($frozen.resources | ConvertTo-Json -Depth 20 -Compress)) 'Reconnect same character/biology/resources'
    Stop-Probe 'reconnect'; Stop-Probe 'third'
    [void](Wait-Bindings 1)
    [void](Command 'host' @{op='save'})
    $saved = (Read-Report 'host').characters.$id
    Stop-Probe 'host'
    Start-Probe 'reload_host' 'HOST' 'host'
    [void](Wait-Ready 'reload_host')
    Assert (((Read-Report 'reload_host').characters.$id | ConvertTo-Json -Depth 20 -Compress) -eq ($saved | ConvertTo-Json -Depth 20 -Compress)) 'Fresh HOST save-v4 exact survival/timing/resource restore'
    Start-Probe 'reload_client' 'JOIN' 'client'
    [void](Wait-Resources 'reload_client')
    $reload = Wait-Condition 'reload_client' {param($r) $r.survival_ready} 'Fresh reload owner survival bootstrap'
    Assert ($reload.no_authority -and -not (Test-Path (Join-Path $tempRoot 'client-appdata/Godot/app_userdata/Leyforge/worlds'))) 'JOIN writes no authoritative save'
    $gate.survival_metrics = (Read-Report 'reload_host').survival_metrics
    $gate.real_process_checks = $checks
    Stop-Probe 'reload_client'; Stop-Probe 'reload_host'
    Write-Output 'W5_6_REAL_PROCESS_PASS'
    # Subsequent exact owner-launch and complete regression receipt are mandatory.
    . (Join-Path $PSScriptRoot 'w5_6_completion.ps1')
} catch { $gate.failure = $_.Exception.Message; throw }
finally {
    foreach ($name in $processes.Keys) {
        $entry = $processes[$name]
        if (-not $entry.process.HasExited) { $entry.process.Kill(); $entry.process.WaitForExit() }
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.log"),($entry.stdout.Result + $entry.stderr.Result))
    }
    $gate | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot 'gate.json') -Encoding UTF8
    Write-Output "WAVE_5_PART_6_EVIDENCE=$evidenceRoot"
}
