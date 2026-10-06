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
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_6_repair_1\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf56r-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
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
 Start-Run $Name @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $testProject 'tests/networking/w5_6_repair_launch.ps1'),'-ProjectPath',$testProject,'-ProofDir',$evidenceRoot,'-ProofName',$Name,'-Mode',$Mode,'-Port',"$Port") $ProfileName 'powershell.exe'
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
            $text = [regex]::Replace($text,'config/version="[^"]+"','config/version="0.5.8-wave5-w5.6"')
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


    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_6_repair_focused.gd','--',"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    Assert (Read-Report 'focused').passed 'Focused canonical/manual/lookup tests'
    $gate.focused_checks=(Read-Report 'focused').checks
    . (Join-Path $PSScriptRoot 'w5_6_repair_owner_fixture.ps1')
    Start-Probe 'host' 'HOST' 'host' '' -1 25657
    [void](Wait-Ready 'host')
    $arena=Command 'host' @{op='arena'}; $y=[int]$arena.commands[-1].y
    $bench=Command 'host' @{op='repair_fixture';cell=@(0,$y,0)}
    $benchId=$bench.commands[-1].id
    $storage=Command 'host' @{op='repair_fixture';cell=@(-2,$y,0);content='leyforge:storage_box'}
    $storageId=$storage.commands[-1].id
    [void](Command 'host' @{op='edit';cell=@(2,$y,0);block='leyforge:air'})
    Start-Probe 'client' 'JOIN' 'client' '' -1 25657
    $client=Wait-Resources 'client';$id=$client.player_id
    Start-Probe 'third' 'JOIN' 'third' '' -1 25657
    $third=Wait-Resources 'third';$thirdId=$third.player_id
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void](Command 'host' @{op='actor_position';player_id=$thirdId;position=@(-1.5,($y+0.05),5.5)})
    Start-Sleep -Seconds 1
    $r=Command 'client' @{op='repair_interact';cell=@(0,$y,0)}
    Assert ($r.commands[-1].ui_open -and $r.commands[-1].grid_size -eq 3 -and $r.commands[-1].object_id -eq $benchId) 'Normal crosshair/RMB opens actual Workbench 3x3'
    [void](Command 'client' @{op='repair_key';code=4194305})
    $r=Command 'client' @{op='repair_interact';cell=@(0,$y,0);key=$true}
    Assert ($r.commands[-1].ui_open -and $r.commands[-1].grid_size -eq 3) 'Normal E opens Workbench through same validated path'
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'client' @{op='repair_key';code=73})
    $manualBefore=Read-Report 'client'
    $r=Command 'client' @{op='repair_button';name='OpenCraftingManual'}
    Assert ($r.commands[-1].manual_visible -and @($r.commands[-1].listed_ids).Count -eq (Read-Report 'focused').recipes) 'Client inventory manual visible; runtime count'
    $r=Command 'client' @{op='repair_button';name='build_kiln'}
    Assert ($r.commands[-1].selected_recipe -eq 'leyforge:build_kiln') 'Client reads canonical Stone Kiln pattern'
    Assert (($r.personal | ConvertTo-Json -Depth 8 -Compress) -eq ($manualBefore.personal | ConvertTo-Json -Depth 8 -Compress) -and $r.resource_metrics.results -eq $manualBefore.resource_metrics.results) 'Client Manual browsing sends no mutation and changes no resources'
    [void](Command 'client' @{op='repair_button';name='CloseManual'})
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'host' @{op='repair_items';player_id=$id})
    Start-Sleep -Milliseconds 400
    [void](Command 'client' @{op='repair_interact';cell=@(0,$y,0)})
    $r=Command 'client' @{op='repair_button';name='OpenCraftingManual'}
    Assert $r.commands[-1].manual_visible 'Manual accessible inside physical Workbench 3x3 context'
    [void](Command 'client' @{op='repair_button';name='CloseManual'})
    $slots=@(0,1,2,3,5,7,6,8)
    foreach($n in 0..7) {
        [void](Command 'client' @{op='repair_slot';endpoint='inventory';slot=(9+$n)})
        $r=Command 'client' @{op='repair_slot';endpoint='grid';slot=$slots[$n]}
    }
    Assert ($r.commands[-1].preview -eq 'leyforge:build_kiln') 'Manual pattern arranged by normal inventory clicks matches canonical recipe'
    $r=Command 'client' @{op='repair_button';name='CraftOutput'}
    Assert ((Quantity $r.personal 'leyforge:kiln') -eq 1) 'Normal craft output click commits one Kiln'
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),1.5)})
    Start-Sleep -Milliseconds 700
    [void](Command 'client' @{op='repair_select';content='leyforge:kiln'})
    $r=Command 'client' @{op='repair_place';cell=@(2,($y-1),-2)}
    $h=Wait-Condition 'host' {param($r) @($r.objects | Where-Object content -eq 'leyforge:kiln').Count -eq 1} 'Normal RMB places the crafted Kiln'
    $kiln=@($h.objects | Where-Object content -eq 'leyforge:kiln')[0];$kilnId=$kiln.instance
    $r=Command 'client' @{op='repair_interact';cell=$kiln.cell;key=$true}
    Assert ($r.commands[-1].ui_open -and $r.commands[-1].context -eq $kilnId) 'Normal crosshair/E opens placed Kiln UI'
    [void](Command 'client' @{op='repair_button';name='OpenCraftingManual'})
    $r=Command 'client' @{op='repair_button';name='charcoal_burn'}
    Assert ($r.commands[-1].selected_recipe -eq 'leyforge:charcoal_burn') 'Client reads canonical input/fuel/output/time in Kiln manual'
    [void](Command 'client' @{op='repair_button';name='CloseManual'})
    # Normal split click moves half of three timber (one); then remaining two.
    [void](Command 'client' @{op='repair_slot';endpoint='inventory';slot=0})
    [void](Command 'client' @{op='repair_slot';endpoint="station/$kilnId/fuel";slot=0;right=$true})
    [void](Command 'client' @{op='repair_slot';endpoint='inventory';slot=0})
    [void](Command 'client' @{op='repair_slot';endpoint="station/$kilnId/input";slot=0})
    $start=Command 'client' @{op='repair_button';name='StartProcess'}
    Assert ((Read-Report 'host').resource_streams."object/$kilnId".station.active -eq 'leyforge:charcoal_burn') 'Normal Fire kiln button starts canonical process'
    $r=Wait-Condition 'client' {param($r) @($r.resource_streams."object/$kilnId".station.output | Where-Object content -eq 'leyforge:charcoal').Count -eq 1} 'Shared Kiln completes canonical eight simulation seconds' 40
    [void](Command 'client' @{op='repair_slot';endpoint="station/$kilnId/output";slot=0;shift=$true})
    $r=Read-Report 'client';Assert ((Quantity $r.personal 'leyforge:charcoal') -eq 2) 'Normal UI withdraws two Charcoal'
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(-1.5,($y+0.05),2.5)})
    Start-Sleep -Milliseconds 700
    $r=Command 'client' @{op='repair_interact';cell=@(-2,$y,0)}
    Assert ($r.commands[-1].ui_open -and $r.commands[-1].context -eq $storageId) 'Physical placed Storage Box opens'
    $charcoalSlot=0
    for($slot=0;$slot -lt 27;$slot++){if($r.personal.inventory[$slot].content -eq 'leyforge:charcoal'){$charcoalSlot=$slot;break}}
    [void](Command 'client' @{op='repair_slot';endpoint='inventory';slot=$charcoalSlot;shift=$true})
    $r=Wait-Condition 'host' {param($r) $r.resource_streams."object/$storageId".slots[0].quantity -eq 2} 'Normal storage deposit visible on Host'
    [void](Command 'client' @{op='repair_slot';endpoint="storage/$storageId";slot=0;shift=$true})
    Assert ((Quantity (Read-Report 'client').personal 'leyforge:charcoal') -eq 2) 'Normal storage withdrawal'
    [void](Command 'client' @{op='repair_key';code=4194305})
    $crate=(Read-Report 'host').resource_streams.PSObject.Properties | Where-Object Name -like 'storage/*' | Select-Object -First 1
    $p=$crate.Value.position
    [void](Command 'host' @{op='repair_crate_access';position=$p;arena_y=$y})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(($p[0]+1.5),($p[1]-0.4),$p[2])})
    Start-Sleep -Milliseconds 900
    $r=Command 'client' @{op='repair_interact';position=$p;key=$true}
    Assert ($r.commands[-1].ui_open -and $r.commands[-1].crate_id -eq $crate.Value.instance -and $r.commands[-1].context -eq $crate.Value.instance) 'Physical origin crate opens its actual targeted ID'
    $crateId=$crate.Value.instance
    [void](Command 'client' @{op='repair_slot';endpoint='inventory';slot=$charcoalSlot;shift=$true})
    [void](Wait-Condition 'host' {param($r) $r.resource_streams."storage/$crateId".slots[0].quantity -eq 2} 'Origin crate normal deposit visible on Host')
    [void](Command 'client' @{op='repair_slot';endpoint="storage/$crateId";slot=0;shift=$true})
    Assert ((Quantity (Read-Report 'client').personal 'leyforge:charcoal') -eq 2) 'Origin crate normal withdrawal conserves output'
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    Start-Sleep -Milliseconds 700
    $missing=Command 'client' @{op='repair_missing';id=$benchId;cell=@(0,$y,0)}
    Assert (-not $missing.commands[-1].ui_open -and $missing.commands[-1].status -match 'Synchronizing object' -and $missing.commands[-1].recovered_ui) 'Missing descriptor waits truthfully, no placement fallthrough, then Host-authorized UI'
    [void](Command 'client' @{op='repair_key';code=4194305})
    # Normal production time and actual unobstructed HOST-granted sprint.
    [void](Command 'host' @{op='repair_runway';y=$y})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),5.5)})
    Start-Sleep -Milliseconds 700
    [void](Command 'client' @{op='look';cell=@(2,$y,25)})
    [void](Command 'host' @{op='repair_key';code=73})
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{fatigue=10;exposure=10;thirst=40;stamina=100}})
    $a=Read-Report 'host'
    [void](Command 'client' @{op='move';sprint=$true})
    $hostManualBefore=Read-Report 'host'
    $hm=Command 'host' @{op='repair_button';name='OpenCraftingManual'}
    Assert $hm.commands[-1].manual_visible 'HOST normal graphical Manual opens'
    $hm=Command 'host' @{op='repair_button';name='build_kiln'}
    Assert ($hm.commands[-1].selected_recipe -eq 'leyforge:build_kiln' -and ($hm.personal | ConvertTo-Json -Depth 8 -Compress) -eq ($hostManualBefore.personal | ConvertTo-Json -Depth 8 -Compress)) 'HOST reads same canonical Kiln without resource mutation'
    Start-Sleep -Seconds 2
    [void](Command 'client' @{op='move';direction='stop'})
    $b=Read-Report 'host'
    $dt=$b.elapsed-$a.elapsed
    $av=$a.characters.$id.survival;$bv=$b.characters.$id.survival
    Assert ($bv.stamina -lt $av.stamina -and $bv.fatigue -gt $av.fatigue) 'Actual remote sprint drains own stamina and increases fatigue'
    Assert ([Math]::Abs(($bv.fatigue-$av.fatigue)-($dt/60)) -lt 0.01) 'Real-process sprint fatigue 1/min while Host inventory open'
    [void](Command 'host' @{op='repair_button';name='CloseManual'})
    [void](Command 'host' @{op='repair_key';code=4194305})
    Assert ([Math]::Abs(($bv.exposure-$av.exposure)-($dt*0.5/60)) -lt 0.01) 'Real-process outdoor production exposure rate'
    Assert ([Math]::Abs(($bv.thirst-$av.thirst)+($dt*5/3600)) -lt 0.005) 'Real-process Standard thirst rate'
    $gate.outdoor_trace=@{before=$a.characters;after=$b.characters;elapsed=$dt}
    [void](Command 'client' @{op='repair_key';code=73})
    [void](Command 'client' @{op='repair_button';name='OpenCraftingManual'})
    $a=Read-Report 'host';Start-Sleep -Seconds 3;$b=Read-Report 'host'
    Assert ($b.characters.$id.survival.thirst -lt $a.characters.$id.survival.thirst -and $b.elapsed -gt $a.elapsed -and -not $b.paused -and $b.time_scale -eq 1) 'Manual/inventory does not pause either biology or world'
    [void](Command 'client' @{op='repair_button';name='CloseManual'})
    [void](Command 'client' @{op='repair_key';code=4194305})
    [void](Command 'client' @{op='repair_select';content='leyforge:drinking_water'})
    $a=Read-Report 'client';[void](Command 'client' @{op='repair_key';code=70})
    $b=Wait-Condition 'client' {param($r) $r.survival.mutation_revision -gt $a.survival.mutation_revision -and (Quantity $r.personal 'leyforge:drinking_water') -lt (Quantity $a.personal 'leyforge:drinking_water')} 'Water authoritative resource and biology results arrive'
    Assert ($b.survival.thirst -gt ($a.survival.thirst+34) -and (Quantity $b.personal 'leyforge:drinking_water') -eq ((Quantity $a.personal 'leyforge:drinking_water')-1) -and $b.survival_hud -match 'Water') 'Normal F consumes exactly one Standard water for +35'
    [void](Command 'client' @{op='retry'})
    Assert ((Quantity (Read-Report 'client').personal 'leyforge:drinking_water') -eq (Quantity $b.personal 'leyforge:drinking_water')) 'Water retry one item/effect through existing ledger'
    Assert ((Read-Report 'client').survival.thirst -le ($b.survival.thirst+0.01)) 'Retried water does not apply second hydration effect'
    [void](Command 'host' @{op='survival_hold_tick';hold=$true})
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{thirst=100}})
    [void](Wait-Condition 'client' {param($r) $r.survival.thirst -eq 100} 'Full hydration authoritative snapshot before no-op')
    $a=Read-Report 'client';[void](Command 'client' @{op='repair_key';code=70});$b=Read-Report 'client'
    Assert ((Quantity $a.personal 'leyforge:drinking_water') -eq (Quantity $b.personal 'leyforge:drinking_water') -and $b.survival.thirst -eq 100) 'Full Standard water no-op retains item'
    [void](Command 'host' @{op='survival_hold_tick';hold=$false})
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    Start-Sleep -Milliseconds 800
    $rest=Command 'host' @{op='survival_shelter';player_id=$id}
    [void](Command 'host' @{op='survival_set';player_id=$id;values=@{fatigue=10;exposure=10}})
    Start-Sleep -Milliseconds 600
    $r=Command 'client' @{op='repair_interact';cell=$rest.commands[-1].cell;key=$true}
    $r=Wait-Condition 'client' {param($r) $r.survival.resting} 'Physical sheltered Rest Mat starts authoritative owner rest'
    $a=Read-Report 'host';Start-Sleep -Seconds 3;$b=Read-Report 'host';$dt=$b.elapsed-$a.elapsed
    Assert ([Math]::Abs(($a.characters.$id.survival.fatigue-$b.characters.$id.survival.fatigue)-($dt*2/60)) -lt 0.01) 'Real-process sheltered rest 2 fatigue/min'
    Assert ([Math]::Abs(($a.characters.$id.survival.exposure-$b.characters.$id.survival.exposure)-($dt*2/60)) -lt 0.01) 'Real-process cover 2 exposure/min without double rest recovery'
    Assert (-not $b.rests.PSObject.Properties[$thirdId]) 'Rest remains player-specific'
    $gate.rest_trace=@{before=$a.characters;after=$b.characters;elapsed=$dt}
    [void](Command 'client' @{op='move'})
    [void](Wait-Condition 'client' {param($r) -not $r.survival.resting} 'Actual movement cancels remote rest')
    [void](Command 'client' @{op='move';direction='stop'})
    # Clustering runs unchanged in production; only JOIN root presentation smooths.
    [void](Command 'host' @{op='actor_position';player_id=$id;position=@(2.5,($y+0.05),5.5)})
    $d=Command 'host' @{op='repair_drops';position=@(-2.5,($y+0.3),-2.5)}
    $ids=$d.commands[-1].ids
    [void](Wait-Condition 'client' {param($r) @($r.drop_nodes).Count -eq 2} 'Reliable drop spawn exact')
    Start-Sleep -Seconds 3
    [void](Command 'host' @{op='repair_drop_stop';hold=$true})
    Start-Sleep -Seconds 1
    $gate.drop_convergence_checkpoint=Read-Report 'client'
    [void](Command 'host' @{op='repair_drop_jump';id=$ids[1];position=@(0.5,($y+0.3),-2.5)})
    Start-Sleep -Milliseconds 350
    [void](Command 'host' @{op='repair_drop_jump';id=$ids[1];position=@(-2.1,($y+0.3),-2.5)})
    [void](Command 'host' @{op='repair_drop_stop';hold=$false})
    [void](Wait-Condition 'client' {param($r) @($r.drop_nodes).Count -eq 1} 'Reliable merge removes losing node immediately; no ghost')
    $gate.survival_metrics=(Read-Report 'host').survival_metrics
    $gate.real_process_checks=$checks
    $gate.actual_input_paths='RMB/E Workbench, origin crate, Storage Box, crafted/placed Kiln; inventory/Workbench/Kiln Manual; slot transfers; shaped Kiln craft; start/progress/output; Rest Mat; F Standard water'
    foreach($name in @('third','client','host')) { Stop-Probe $name }
    . (Join-Path $PSScriptRoot 'w5_6_repair_drop_metrics.ps1')
    $testProject=$originalProofProject
    if(-not $SkipRegression) {
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName='powershell.exe';$info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $testProject 'tools/development/verify_wave_5_part_6.ps1')+'"'
        $info.WorkingDirectory=$testProject;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.EnvironmentVariables['APPDATA']=Join-Path $tempRoot 'regression-app';$info.EnvironmentVariables['LOCALAPPDATA']=Join-Path $tempRoot 'regression-local'
        $proc=New-Object Diagnostics.Process;$proc.StartInfo=$info;[void]$proc.Start();$out=$proc.StandardOutput.ReadToEndAsync();$err=$proc.StandardError.ReadToEndAsync()
        if(-not $proc.WaitForExit(2400000)){$proc.Kill();throw 'Full repair regression timeout'}
        $text=$out.Result+$err.Result;[IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w56.log'),$text)
        & robocopy.exe (Join-Path $testProject '.verification/wave5/w5_6') (Join-Path $evidenceRoot 'regression_w56') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
        Check ($LASTEXITCODE -lt 8) 'Retain complete prior evidence'
        Assert ($proc.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_6_VALIDATION_PASS') 'Wave 0-4 and W5.1-W5.6 all pass'
        $last=Get-ChildItem (Join-Path $evidenceRoot 'regression_w56') -Directory | Sort-Object Name | Select-Object -Last 1
        $prior=Get-Content (Join-Path $last.FullName gate.json) -Raw | ConvertFrom-Json
        Assert ($prior.passed -and $prior.certified) 'Prior gate certified'
        $gate.regressions=$prior.regressions+'; W5.6 PASS';$gate.owner_launch=$prior.owner_launch
    }
    foreach($relative in $workingManifest.Keys){Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $workingManifest[$relative]) "Source changed: $relative"}
    $gate.passed=$true;$gate.certified=-not $SkipRegression
    Write-Output 'WAVE_5_PART_6_REPAIR_1_VALIDATION_PASS'
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
    Write-Output "WAVE_5_PART_6_REPAIR_1_EVIDENCE=$evidenceRoot"
}
