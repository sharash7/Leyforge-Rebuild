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
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.5 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_5\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf55-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
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
    Start-Run $Name @('--path',$testProject,'--script','res://tests/networking/w5_5_process.gd','--',"--session=$Mode","--port=$Port","--world-id=proof-world",'--seed=184552221',"--proof-dir=$evidenceRoot","--proof-name=$Name","--proof-fault=$Fault","--proof-hold=$Hold","--w55-proof") $ProfileName
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
function Wait-Condition([string] $Name, [scriptblock] $Predicate, [string] $Label) {
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
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
            $text = [regex]::Replace($text,'config/version="[^"]+"','config/version="0.5.6-wave5-w5.5"')
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
    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_5_focused.gd','--',("--fixture=" + (Join-Path $tempRoot 'focused-fixture')),"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    $focused = Read-Report 'focused'
    Check $focused.passed 'Focused tests failed'
    $gate.focused_checks = $focused.checks
    $gate.largest_part = $focused.largest_part
    Start-Probe 'host' 'HOST' 'host'
    [void](Wait-Ready 'host')
    $arena = Command 'host' @{op='arena'}
    $y = [int]$arena.commands[-1].y
    foreach ($z in @(1,2)) {
        [void](Command 'host' @{op='edit';cell=@(2,$y,$z);block='leyforge:oak_heartwood'})
        [void](Command 'host' @{op='edit';cell=@(3,$y,$z);block='leyforge:stone'})
    }
    [void](Command 'host' @{op='save'})
    Start-Probe 'client' 'JOIN' 'client'
    $client = Wait-Resources 'client'
    $id = $client.player_id
    Assert ($client.no_authority -and $client.no_world_save -and $client.pid -ne (Read-Report 'host').pid) 'Real separate ENet client / authority negative'
    Start-Run 'old_protocol' @('--path',$testProject,'--script','res://tests/networking/w5_2_process.gd','--','--session=JOIN','--port=25652',"--proof-dir=$evidenceRoot",'--proof-name=old_protocol','--proof-fault=w54_protocol_mismatch') 'old-protocol'
    Finish-Run 'old_protocol'
    Assert ((Read-Report 'old_protocol').reason -eq 'protocol_mismatch') 'Protocol-3 W5.4 peer rejected cleanly'
    Assert (@($client.personal.inventory).Count -eq 27 -and @($client.personal.equipment).Count -eq 2) 'Personal inventory shape'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void](Wait-Converged 'client')
    Harvest 'client' @(0,$y,0)
    $drop = Wait-Condition 'client' {param($r) @($r.drop_nodes).Count -gt 0} 'Physical drop rendered on JOIN'
    [void](Command 'client' @{op='resource_capture'})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),1.7)})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='move';direction='move_forward'})
    Start-Sleep -Milliseconds 200
    [void](Command 'client' @{op='move';direction='stop'})
    $picked = Wait-Condition 'client' {param($r) (Quantity $r.personal 'leyforge:dirt') -eq 1} 'Client walking pickup / inventory'
    Assert ((Quantity (Read-Report 'host').personal 'leyforge:dirt') -eq 0) 'Independent personal state'
    $dropped = Command 'client' @{op='resource_drop';content='leyforge:dirt'}
    Assert $dropped.commands[-1].result.success 'Client drop request'
    [void](Command 'client' @{op='retry'})
    Start-Sleep -Milliseconds 500
    $hostDrops = @((Read-Report 'host').drops | Where-Object { $_.stack.content -eq 'leyforge:dirt' })
    Assert ($hostDrops.Count -eq 1 -and $hostDrops[0].stack.quantity -eq 1) 'Duplicate drop exactly once'
    $p = $hostDrops[0].position
    [void](Command 'host' @{op='actor_position';player_id=(Read-Report 'host').player_id;position=@($p[0],($y+0.05),($p[2]+0.5))})
    [void](Wait-Condition 'host' {param($r) (Quantity $r.personal 'leyforge:dirt') -eq 1} 'Host acquires client drop')
    [void](Command 'host' @{op='actor_position';player_id=(Read-Report 'host').player_id;position=@(-2.5,($y+0.05),4.5)})
    Assert ([int](Read-Report 'host').totals.'leyforge:dirt' -eq 1) 'Dirt conserved through break, walking pickup, drop retry and host pickup'
    # Gather each real wood voxel, then craft through canonical transactions.
    foreach ($z in @(2,1,0)) {
        [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),($z+2.0))})
        [void](Wait-Converged 'client')
        Harvest 'client' @(2,$y,$z)
        [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),($z+1.0))})
        [void](Wait-Converged 'client')
        Start-Sleep -Milliseconds 600
    }
    $wood = Wait-Condition 'client' {param($r) (Quantity $r.personal 'leyforge:oak_heartwood') -eq 3} 'Legitimate timber progression input'
    $crafted = Command 'client' @{op='progression'}
    Assert ((Quantity $crafted.personal 'leyforge:workbench') -eq 1 -and (Quantity $crafted.personal 'leyforge:oak_planks') -eq 7 -and (Quantity $crafted.personal 'leyforge:oak_stick') -eq 4) '2x2 recipes reconcile'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),2.5)})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='look';cell=@(0,($y-1),0)})
    Start-Sleep -Milliseconds 300
    $placed = Command 'client' @{op='source_place';content='leyforge:workbench';cell=@(0,$y,0)}
    Assert $placed.commands[-1].result.success 'Remote inventory-backed placement'
    $bench = @((Read-Report 'host').objects | Where-Object { $_.content -eq 'leyforge:workbench' })[0].instance
    Assert ((Quantity $placed.personal 'leyforge:workbench') -eq 0 -and $bench) 'Atomic functional placement consumes exactly one'
    [void](Command 'client' @{op='tool_progression';id=$bench})
    $toolReport = Command 'client' @{op='equip';content='leyforge:wooden_pickaxe'}
    Assert $toolReport.commands[-1].result.success 'Remote equipment transfer'
    $toolBefore = $toolReport.personal.equipment[0]
    Assert ($toolBefore.instance -and $toolBefore.durability -gt 0) 'Stateful tool instance'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),4.5)})
    [void](Wait-Converged 'client')
    foreach ($z in @(2,1,0)) {
        [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),($z+2.0))})
        [void](Wait-Converged 'client')
        Harvest 'client' @(3,$y,$z)
        [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),($z+1.0))})
        [void](Wait-Converged 'client')
        Start-Sleep -Milliseconds 600
    }
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),1.0)})
    [void](Wait-Converged 'client')
    $worn = Wait-Condition 'client' {param($r) (Quantity $r.personal 'leyforge:stone') -eq 3} 'Authoritative wooden tool mines ordinary Stone'
    Assert ($worn.personal.equipment[0].instance -eq $toolBefore.instance -and $worn.personal.equipment[0].durability -lt $toolBefore.durability) 'Exact instance wear replicated'
    $denseNegative = @((Read-Report 'host').sources | Where-Object source -eq 'dense_stone')[0]
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@($denseNegative.position[0],([Math]::Floor($denseNegative.position[1])+0.05),($denseNegative.position[2]+2.0))})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='source_look';id=$denseNegative.instance})
    [void](Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 900
    [void](Command 'client' @{op='harvest_input';active=$false})
    Assert (@((Read-Report 'host').sources | Where-Object instance -eq $denseNegative.instance)[0].remaining -eq 6 -and (Quantity (Read-Report 'client').personal 'leyforge:stone') -eq 3) 'Wooden capability-1 tool cannot harvest Dense Stone'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),2.5)})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='tool_progression';id=$bench;heads='leyforge:stone';recipe='leyforge:craft_stone_pickaxe'})
    [void](Command 'client' @{op='resource_move';content='leyforge:wooden_pickaxe';quantity=1;source='equipment';destination='inventory'})
    [void](Command 'client' @{op='equip';content='leyforge:stone_pickaxe'})
    $dense = @((Read-Report 'host').sources | Where-Object source -eq 'dense_stone')[0]
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@($dense.position[0],([Math]::Floor($dense.position[1])+0.05),($dense.position[2]+2.0))})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='source_look';id=$dense.instance})
    Start-Sleep -Milliseconds 300
    [void](Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 3000
    [void](Command 'client' @{op='harvest_input';active=$false})
    $denseDone = Wait-Condition 'client' {param($r) (Quantity $r.personal 'leyforge:stone') -eq 6} 'Legitimate capability-2 Dense Stone yields six Stone'
    Assert (-not ($denseDone.source_nodes -contains $dense.instance)) 'Dense Stone presentation/collision removed'
    Start-Probe 'third' 'JOIN' 'third'
    $third = Wait-Resources 'third'
    $thirdId = $third.player_id
    Assert ($thirdId -ne $id -and $thirdId -ne (Read-Report 'host').player_id -and (Quantity $third.personal 'leyforge:stone') -eq 0) 'Third stable identity has independent empty inventory'
    [void](Command 'client' @{op='resource_pause_pickup';active=$true})
    [void](Command 'third' @{op='resource_pause_pickup';active=$true})
    # Origin shared crate, with real player-owned planks.
    $crate = @((Read-Report 'host').resource_streams.PSObject.Properties | Where-Object { $_.Name -like 'storage/*' })[0].Value
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(($crate.position[0]+0.8),($y+0.05),($crate.position[2]+1.0))})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='resource';operation='open_context';args=@{target=$crate.instance}})
    $stored = Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;destination=('storage/'+$crate.instance)}
    Assert $stored.commands[-1].result.success 'Shared storage deposit'
    $shared = @((Read-Report 'host').resource_streams.PSObject.Properties | Where-Object { $_.Name -eq ('storage/'+$crate.instance) })[0].Value
    Assert (($shared.slots | Where-Object { $_ -and $_.content -eq 'leyforge:oak_planks' }).quantity -eq 1) 'Host sees exact shared storage state'
    $withdrawn = Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;source=('storage/'+$crate.instance);destination='inventory'}
    Assert $withdrawn.commands[-1].result.success 'Shared storage withdrawal'
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(($crate.position[0]-0.8),($y+0.05),($crate.position[2]+1.0))})
    [void](Wait-Converged 'third')
    $toolStored = Command 'client' @{op='resource_move';content='leyforge:wooden_pickaxe';quantity=1;destination=('storage/'+$crate.instance)}
    Assert $toolStored.commands[-1].result.success 'Store legitimately crafted worn wooden tool'
    Queue-Withdraw 'client' ('storage/'+$crate.instance) 'leyforge:wooden_pickaxe' 1
    Queue-Withdraw 'third' ('storage/'+$crate.instance) 'leyforge:wooden_pickaxe' 1
    $toolRace = Race 'client' 'third' 'same stateful storage withdrawal'
    Assert (((Quantity $toolRace[0].personal 'leyforge:wooden_pickaxe')+(Quantity $toolRace[1].personal 'leyforge:wooden_pickaxe')) -eq 1) 'Unique wooden tool owner after race'
    [void](Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;destination=('storage/'+$crate.instance)})
    [void](Command 'third' @{op='resource_move';content='leyforge:oak_planks';quantity=1;source=('storage/'+$crate.instance);destination='inventory'})
    foreach ($pair in @(@('client',$id,-1.5),@('third',$thirdId,2.5))) {
        [void](Command 'host' @{op='actor_position';player_id=$pair[1];position=@($pair[2],($y+0.05),3.5)})
        [void](Wait-Converged $pair[0])
        [void](Command $pair[0] @{op='look';cell=@(0,($y-1),2)})
    }
    Start-Sleep -Milliseconds 300
    foreach ($name in @('client','third')) {
        [void](Command $name @{op='resource_queue';operation='place';content='leyforge:oak_planks';args=@{cell=@(0,$y,2);expected_block='leyforge:air'}})
    }
    $planksBefore = [int](Read-Report 'host').totals.'leyforge:oak_planks'
    $placementRace = Race 'client' 'third' 'same placement cell'
    Assert (((Quantity $placementRace[0].personal 'leyforge:oak_planks')+(Quantity $placementRace[1].personal 'leyforge:oak_planks')) -eq ($planksBefore-1) -and [int](Read-Report 'host').totals.'leyforge:oak_planks' -eq $planksBefore) 'Placement consumes one inventory plank and conserves whole world including placed material'
    $beforeFailed = (Read-Report 'client').personal | ConvertTo-Json -Depth 20 -Compress
    foreach ($cell in @(@(0,$y,2),@(0,$y,0),@(-2,$y,3),@(300,$y,300))) {
        $bad = Command 'client' @{op='resource';operation='place';args=@{cell=$cell;expected_block='leyforge:air';slot=(Read-Report 'client').personal.hotbar_selected;expected=((Read-Report 'client').personal.inventory[(Read-Report 'client').personal.hotbar_selected])}}
        Assert (-not $bad.commands[-1].result.success) 'Occupied/stale/out-of-range placement rejected'
    }
    $current = Read-Report 'client'
    $absent = Command 'client' @{op='resource';operation='place';args=@{cell=@(1,$y,2);expected_block='leyforge:air';slot=$current.personal.hotbar_selected;expected=@{content='leyforge:dirt';quantity=1}}}
    Assert (-not $absent.commands[-1].result.success) 'Forged no-longer-present selected stack rejected'
    Assert (((Read-Report 'client').personal | ConvertTo-Json -Depth 20 -Compress) -eq $beforeFailed) 'Failed placements consume no items'
    # Kiln uses an explicitly separate adversarial station fixture.
    $kilnReport = Command 'host' @{op='resource_fixture';kind='kiln';cell=@(1,$y,0)}
    $kiln = $kilnReport.commands[-1].id
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(1.5,($y+0.05),2.5)})
    [void](Wait-Converged 'client')
    Start-Sleep -Milliseconds 400
    $started = Command 'client' @{op='resource';operation='start_process';args=@{target=$kiln;recipe='leyforge:charcoal_burn'}}
    Assert $started.commands[-1].result.success 'Remote kiln process starts'
    [void](Wait-Condition 'client' {param($r) $s=$r.resource_streams.PSObject.Properties['object/'+$kiln].Value; $s -and $s.station.output[0] -and $s.station.output[0].quantity -eq 2} 'Shared kiln completion')
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(2.5,($y+0.05),2.5)})
    [void](Wait-Converged 'third')
    Queue-Withdraw 'client' ('station/'+$kiln+'/output') 'leyforge:charcoal' 2
    Queue-Withdraw 'third' ('station/'+$kiln+'/output') 'leyforge:charcoal' 2
    [void](Race 'client' 'third' 'same kiln output withdrawal')
    Assert ([int](Read-Report 'host').totals.'leyforge:charcoal' -eq 2) 'Kiln canonical input/fuel/output accounting'
    # Finite provisions source: actual held targeting/collision and host output.
    $source = @((Read-Report 'host').sources | Where-Object { $_.source -eq 'trail_food' })[0]
    if (-not $source) { $source = @((Read-Report 'host').sources | Where-Object { $_.source -like '*provision*' })[0] }
    Check ($null -ne $source) 'Canonical provisions source missing'
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@($source.position[0],([Math]::Floor($source.position[1])+0.05),($source.position[2]+2.0))})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='source_look';id=$source.instance})
    Start-Sleep -Milliseconds 300
    [void](Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 3500
    [void](Command 'client' @{op='harvest_input';active=$false})
    [void](Wait-Condition 'host' {param($r) @($r.sources | Where-Object { $_.instance -eq $source.instance })[0].remaining -eq 0} 'Remote finite source depleted')
    Assert ((Quantity (Read-Report 'client').personal 'leyforge:provisions') -eq 4) 'Canonical food cache quantity without consumption'
    $water = @((Read-Report 'host').sources | Where-Object source -eq 'trail_water')[0]
    foreach ($pair in @(@('client',$id,2.0),@('third',$thirdId,-2.0))) {
        [void](Command 'host' @{op='actor_position';player_id=$pair[1];position=@($water.position[0],([Math]::Floor($water.position[1])+0.05),($water.position[2]+$pair[2]))})
        [void](Wait-Converged $pair[0])
        [void](Command $pair[0] @{op='source_look';id=$water.instance})
    }
    Start-Sleep -Milliseconds 300
    foreach ($name in @('client','third')) { [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.command.json"),'{"op":"harvest_input","active":true}') }
    Start-Sleep -Milliseconds 1500
    foreach ($name in @('client','third')) { [void](Command $name @{op='harvest_input';active=$false}) }
    $waterHost = Read-Report 'host'
    Assert (@($waterHost.sources | Where-Object instance -eq $water.instance)[0].remaining -eq 0) 'Same water source depletes once'
    $waterA = Quantity (Read-Report 'client').personal 'leyforge:drinking_water'
    $waterB = Quantity (Read-Report 'third').personal 'leyforge:drinking_water'
    Assert (($waterA+$waterB) -eq 4 -and ($waterA -eq 0 -or $waterB -eq 0)) 'Same-source contention one canonical output owner'
    $races += @{label='same finite source';left_quantity=$waterA;right_quantity=$waterB}
    Assert $waterHost.instances_unique 'Source race global instance uniqueness'
    # Drop one legitimately harvested Stone, then race two actors at pickup distance.
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(-1.5,($y+0.05),3.5)})
    [void](Wait-Converged 'client')
    [void](Command 'client' @{op='look';cell=@(-2,($y-1),0)})
    $dropRace = Command 'client' @{op='resource_drop';content='leyforge:stone'}
    Assert $dropRace.commands[-1].result.success 'Drop race moves a legitimately harvested Stone'
    $dropId = $dropRace.commands[-1].result.data.drop_id
    $dp = @((Read-Report 'host').drops | Where-Object instance -eq $dropId)[0].position
    foreach ($pair in @(@('client',$id,0.5),@('third',$thirdId,-0.5))) {
        [void](Command 'host' @{op='actor_position';player_id=$pair[1];position=@(($dp[0]+$pair[2]),($y+0.05),$dp[2])})
        [void](Wait-Converged $pair[0])
        [void](Command $pair[0] @{op='resource_queue';operation='pickup';args=@{target=$dropId}})
    }
    Start-Sleep -Milliseconds 1300
    $stoneBefore = (Quantity (Read-Report 'client').personal 'leyforge:stone')+(Quantity (Read-Report 'third').personal 'leyforge:stone')+1
    [void](Race 'client' 'third' 'same physical drop pickup')
    [void](Command 'client' @{op='retry'})
    [void](Command 'third' @{op='retry'})
    Start-Sleep -Milliseconds 500
    Assert (((Quantity (Read-Report 'client').personal 'leyforge:stone')+(Quantity (Read-Report 'third').personal 'leyforge:stone')) -eq $stoneBefore) 'Pickup retries preserve whole quantity'
    $lostBefore = Read-Report 'host'
    $plank = (Read-Report 'client').personal.inventory[1]
    $lost = Command 'client' @{op='lost_result';operation='transfer';args=@{source='inventory';destination='inventory';source_slot=1;destination_slot=20;quantity=1;expected=$plank}}
    Assert ($lost.commands[-1].result.success -and (Read-Report 'host').resource_commits -eq ($lostBefore.resource_commits+1) -and [int](Read-Report 'host').totals.'leyforge:oak_planks' -eq [int]$lostBefore.totals.'leyforge:oak_planks') 'Dropped successful transfer result recovered with one mutation and conserved quantity'
    [void](Command 'client' @{op='resource';operation='open_context';args=@{target=''}})
    [void](Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;destination='grid';destination_slot=0})
    $stagedTotal = [int](Read-Report 'host').totals.'leyforge:oak_planks'
    Stop-Probe 'third'
    $gate.races = $races
    $gate.instance_uniqueness = $waterHost.instances_unique
    $gate.transaction_retry = @{duplicate_craft_focused=$true;duplicate_drop_process=$true;duplicate_pickup_process=$true;lost_result_process=$true;reconnect_cache_focused=$true}
    $gate.source_contention = @{provisions=4;water_total=($waterA+$waterB);dense_stone_output=6;capability_1_rejected=$true}
    $gate.real_process_paths = @('drop spawn','walking pickup','client drop to host','personal separation','2x2 crafting','functional placement','Workbench 3x3','equipment/tool wear','shared storage','shared kiln','finite source')
    [void](Command 'client' @{op='resource';operation='close_grid';args=@{}})
    $before = (Read-Report 'client').personal | ConvertTo-Json -Depth 20 -Compress
    [void](Command 'client' @{op='resource_resync'})
    Start-Sleep -Milliseconds 700
    Assert (((Read-Report 'client').personal | ConvertTo-Json -Depth 20 -Compress) -eq $before) 'Resource resync preserves exact owner facts'
    [void](Command 'client' @{op='resource';operation='open_context';args=@{target=''}})
    [void](Command 'client' @{op='resource_move';content='leyforge:oak_planks';quantity=1;destination='grid';destination_slot=0})
    Stop-Probe 'client'
    Start-Probe 'reconnect' 'JOIN' 'client'
    $again = Wait-Resources 'reconnect'
    Assert ($again.player_id -eq $id -and (($again.personal | ConvertTo-Json -Depth 20 -Compress) -eq $before)) 'Reconnect same inventory/tool/hotbar'
    Assert ([int](Read-Report 'host').totals.'leyforge:oak_planks' -eq $stagedTotal) 'Disconnect staging conserved globally'
    Stop-Probe 'reconnect'
    [void](Command 'host' @{op='save'})
    Stop-Probe 'host'
    Start-Probe 'reload_host' 'HOST' 'host'
    [void](Wait-Ready 'reload_host')
    Start-Probe 'reload_client' 'JOIN' 'client'
    $reload = Wait-Resources 'reload_client'
    Assert (($reload.personal | ConvertTo-Json -Depth 20 -Compress) -eq $before -and $reload.no_world_save -and $reload.no_authority) 'Fresh process save-v4 recovery / client-save negative'
    $gate.persistence = $true
    $gate.resource_metrics = @{host=(Read-Report 'host').resource_metrics;client=(Read-Report 'client').resource_metrics}
    $gate.conservation_totals = (Read-Report 'reload_host').totals
    Assert (Read-Report 'reload_host').instances_unique 'Persisted global instance uniqueness'
    $gate.process_checks = $checks
    Stop-Probe 'reload_client'
    Stop-Probe 'reload_host'
    $ownerProject = Join-Path $tempRoot 'owner-project'
    New-Item -ItemType Directory -Force $ownerProject | Out-Null
    foreach ($relative in $manifest.Keys) {
        $target = Join-Path $ownerProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item (Join-Path $testProject $relative) $target
    }
    $ownerInfo = New-Object Diagnostics.ProcessStartInfo
    $ownerInfo.FileName = 'powershell.exe'
    $ownerInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tests\networking\w5_5_owner_launch.ps1') + '" -ProjectPath "' + $ownerProject + '" -FixtureRoot "' + (Join-Path $tempRoot 'owner-fixture') + '" -EvidenceRoot "' + $evidenceRoot + '"'
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
    Check ($ownerProcess.ExitCode -eq 0 -and $ownerText -match 'W5_5_OWNER_LAUNCH_PASS') "Owner-launch verification failed: $ownerText"
    $ownerReceipt = Read-Report 'owner_launch'
    Check ($ownerReceipt.passed -and $ownerReceipt.clean_cache) 'Owner launch lacks clean-cache proof'
    $gate.owner_launch = $true
    $gate.owner_launch_checks = $ownerReceipt.checks
    Write-Output 'OWNER_LAUNCH PASS'
    if (-not $SkipRegression) {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = 'powershell.exe'
        $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tools\development\verify_wave_5_part_4.ps1') + '" -GodotExecutable "' + $godotPath + '"'
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
        if (-not $prior.WaitForExit(1200000)) { $prior.Kill(); throw 'W5.4 and earlier regressions timed out.' }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w54.log'),$text)
        $priorRoot = Join-Path $testProject '.verification\wave5\w5_4'
        if (Test-Path $priorRoot) {
            # Nested retained receipts exceed Copy-Item's legacy Windows path limit.
            & robocopy.exe $priorRoot (Join-Path $evidenceRoot 'regression_w54') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
            Check ($LASTEXITCODE -lt 8) 'Complete regression evidence copy failed'
        }
        Check ($prior.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_4_VALIDATION_PASS') 'W5.4 complete regression failed'
        $priorRun = Get-ChildItem (Join-Path $evidenceRoot 'regression_w54') -Directory | Sort-Object Name | Select-Object -Last 1
        $priorReceipt = Get-Item -LiteralPath (Join-Path $priorRun.FullName 'gate.json')
        $priorGate = Get-Content $priorReceipt.FullName -Raw | ConvertFrom-Json
        Check ($priorGate.certified -and $priorGate.passed) 'W5.4 receipt uncertified'
        $gate.regressions = 'Wave 0, 1, 2, 3, 4, W5.1, W5.2 W5.3 and W5.4 PASS'
    }

    foreach ($relative in $workingManifest.Keys) { Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $workingManifest[$relative]) "Source changed: $relative" }
    $gate.snapshot_matches_source = $true
    $gate.passed = $true
    $gate.certified = -not $SkipRegression
    Write-Output 'WAVE_5_PART_5_VALIDATION_PASS'
} catch {
    $gate.failure = $_.Exception.Message
    throw
} finally {
    foreach ($name in $processes.Keys) {
        $entry = $processes[$name]
        if (-not $entry.process.HasExited) { $entry.process.Kill(); $entry.process.WaitForExit() }
        [IO.File]::WriteAllText((Join-Path $evidenceRoot "$name.log"),($entry.stdout.Result + $entry.stderr.Result))
    }
    $gate | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidenceRoot 'gate.json') -Encoding UTF8
    Write-Output "WAVE_5_PART_5_EVIDENCE=$evidenceRoot"
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    # Retain disposable projects on failure for diagnosis; never touch live userdata.
}
