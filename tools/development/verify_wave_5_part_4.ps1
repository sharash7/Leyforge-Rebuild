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
if ((Get-FileHash $godotPath).Hash -ne (Get-FileHash $approved).Hash) { throw 'W5.4 requires the approved shutdown-fixed runner.' }
$evidenceRoot = Join-Path $repositoryRoot ('.verification\wave5\w5_4\run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lf54-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
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
    Start-Run $Name @('--path',$testProject,'--script','res://tests/networking/w5_4_process.gd','--',"--session=$Mode","--port=$Port","--world-id=proof-world",'--seed=184552221',"--proof-dir=$evidenceRoot","--proof-name=$Name","--proof-fault=$Fault","--proof-hold=$Hold") $ProfileName
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
        if ($report -and $report.error -lt 0.12 -and $report.grounded -and (HorizontalSpeed $report) -lt 0.1) { return $report }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name convergence failed"
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
function Snapshot-Paths {
    if ($usingSnapshot) { $values = Get-Content $inventoryPath -Raw | ConvertFrom-Json; return $values }
    $tracked = @(& git -C $repositoryRoot ls-files -- project.godot src content scenes tests tools addons docs AGENTS.md)
    Check ($LASTEXITCODE -eq 0) 'Tracked snapshot inventory failed'
    $others = @(& git -C $repositoryRoot ls-files --others --exclude-standard -- project.godot src content scenes tests tools addons docs AGENTS.md)
    Check ($LASTEXITCODE -eq 0) 'Untracked snapshot inventory failed'
    return @($tracked) + @($others | Where-Object { -not $_.StartsWith('addons/') -and $_ -notin $preserved.Keys })
}
try {
    $inventoryPath = Join-Path $repositoryRoot '.verification_snapshot_inventory.json'
    $usingSnapshot = Test-Path -LiteralPath $inventoryPath
    $preserved = @{}
    $preservationFile = Join-Path $repositoryRoot '.verification\wave5\w5_4\preparation-20261005\unrelated_hashes.json'
    if (-not $usingSnapshot -and (Test-Path $preservationFile)) {
        $prior = Get-Content $preservationFile -Raw | ConvertFrom-Json
        foreach ($property in $prior.PSObject.Properties) { $preserved[$property.Name] = $property.Value }
    }
    $publicationEdits = @()
    if (-not $usingSnapshot) {
        $publicationEdits = @(& git -C $repositoryRoot diff HEAD --name-only)
        Check ($LASTEXITCODE -eq 0) 'Publication edit inventory failed'
        $publicationEdits += @(& git -C $repositoryRoot ls-files --others --exclude-standard)
        Check ($LASTEXITCODE -eq 0) 'Publication new-file inventory failed'
    }
    $paths = @(Snapshot-Paths)
    $manifest = @{}
    $workingManifest = @{}
    foreach ($relative in $paths) {
        $source = Join-Path $repositoryRoot $relative
        $target = Join-Path $testProject $relative
        New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
        $workingManifest[$relative] = (Get-FileHash -LiteralPath $source).Hash
        if (-not $usingSnapshot -and $relative -eq 'project.godot') {
            $text = [Text.Encoding]::UTF8.GetString((Read-GitBytes $relative))
            $text = [regex]::Replace($text,'config/version="[^"]+"','config/version="0.5.7-wave5-w5.6"')
            [IO.File]::WriteAllText($target,$text,(New-Object Text.UTF8Encoding($false)))
        } elseif (-not $usingSnapshot -and $relative -eq 'scenes/main/wave_1_playground.tscn') {
            [IO.File]::WriteAllBytes($target,(Read-GitBytes $relative))
        } elseif (-not $usingSnapshot -and $relative -notin $publicationEdits) {
            # Qualify canonical Git bytes, including LF normalization, while
            # separately pinning and preserving the raw working-copy bytes.
            [IO.File]::WriteAllBytes($target,(Read-GitBytes $relative))
        } else {
            Copy-Item -LiteralPath $source -Destination $target
        }
        $manifest[$relative] = (Get-FileHash -LiteralPath $target).Hash
    }
    @($manifest.Keys) | ConvertTo-Json | Set-Content (Join-Path $testProject '.verification_snapshot_inventory.json') -Encoding UTF8
    $manifest | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'source_manifest.json') -Encoding UTF8
    $workingManifest | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'working_source_manifest.json') -Encoding UTF8
    $gate.publication_projection = $true
    Start-Run 'import' @('--headless','--editor','--path',$testProject,'--quit')
    Finish-Run 'import' 0 180000
    Start-Run 'focused' @('--headless','--path',$testProject,'--script','res://tests/networking/w5_4_focused.gd','--',("--fixture=" + (Join-Path $tempRoot 'focused-fixture')),"--output=$evidenceRoot\focused.json")
    Finish-Run 'focused'
    $focused = Read-Report 'focused'
    Check $focused.passed 'Focused tests failed'
    $gate.focused_checks = $focused.checks
    $gate.largest_focused_snapshot_part = $focused.largest_snapshot_part



    Start-Probe 'host' 'HOST' 'host'
    $hostStart = Wait-Ready 'host'
    $arena = Command 'host' @{op='arena'}
    $y = [int] $arena.commands[-1].y
    $cell = @(0,$y,0)
    $tree = @(2,$y,0)
    $stone = @(3,$y,0)
    $grass = @(-2,$y,0)
    $watch = @($cell,$tree,$stone,$grass)
    [void] (Command 'host' @{op='watch';cells=$watch})
    [void] (Command 'host' @{op='save'})
    Start-Probe 'client' 'JOIN' 'client'
    $client = Wait-Ready 'client'
    $id = $client.player_id
    [void] (Command 'client' @{op='watch';cells=$watch})
    Start-Sleep -Milliseconds 400
    $client = Read-Report 'client'
    $two = Wait-Bindings 2
    Assert ($client.voxel_ready -and $client.no_authority -and $client.no_world_save) 'Initial sparse synchronization gates movement without JOIN save'
    Assert ($client.cells[0].canonical -eq 'leyforge:dirt') 'Saved pre-join override in actual JOIN voxel tool'
    Assert ($client.pid -ne $two.pid) 'Separate real rendered ENet processes'
    foreach ($p in $client.bucket_hashes.PSObject.Properties) { Assert ($two.bucket_hashes.PSObject.Properties[$p.Name].Value -eq $p.Value) 'Initial relevant HOST/JOIN bucket hash equality before input' }
    Start-Run 'old_client' @('--path',$testProject,'--script','res://tests/networking/w5_2_process.gd','--','--session=JOIN','--port=25652',"--proof-dir=$evidenceRoot",'--proof-name=old_client','--proof-fault=w53_protocol_mismatch') 'old-client'
    Finish-Run 'old_client'
    Assert ((Read-Report 'old_client').reason -eq 'protocol_mismatch') 'Actual protocol-2 W5.3 hello rejects cleanly over ENet'
    [void] (Wait-Bindings 2)
    $gate.w53_protocol_rejection = $true
    $gate.initial_sync = $true
    $gate.initial_override_count = @($client.overrides).Count
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=$cell})
    Start-Sleep -Milliseconds 300
    [void] (Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 120
    [void] (Command 'client' @{op='harvest_input';active=$false})
    Start-Sleep -Milliseconds 300
    Assert ((Read-Report 'host').cells[0].canonical -eq 'leyforge:dirt') 'Quick tap and release cannot complete harvest'
    $gate.quick_tap_release = $true
    [void] (Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 150
    [void] (Command 'client' @{op='look';cell=$grass})
    Start-Sleep -Milliseconds 150
    [void] (Command 'client' @{op='harvest_input';active=$false})
    Start-Sleep -Milliseconds 200
    Assert ((Read-Report 'host').cells[0].canonical -eq 'leyforge:dirt' -and (Read-Report 'host').cells[3].canonical -eq 'leyforge:grass') 'Retargeting cancels partial held work instead of carrying it'
    $gate.remote_target_change = $true
    [void] (Command 'client' @{op='look';cell=$cell})
    Start-Sleep -Milliseconds 300
    [void] (Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 1400
    [void] (Command 'client' @{op='harvest_input';active=$false})
    Start-Sleep -Milliseconds 300
    $afterHarvest = Read-Report 'host'
    $clientHarvest = Read-Report 'client'
    Assert ($afterHarvest.cells[0].canonical -eq 'leyforge:air' -and $clientHarvest.cells[0].canonical -eq 'leyforge:air') 'Real held CLIENT input commits once on HOST and both real voxel grids converge'
    Assert (@($afterHarvest.drops).Count -ge 1) 'Remote break retains HOST physical output'
    Assert (-not $clientHarvest.cells[0].collision) 'Loaded JOIN collision rebuilt after removal'
    $gate.remote_harvest = $true
    $gate.client_collision_removal = $true
    [void] (Command 'client' @{op='look';cell=@(0,$y,(-3))})
    [void] (Command 'client' @{op='move';direction='move_forward'})
    Start-Sleep -Milliseconds 1000
    [void] (Command 'client' @{op='move';direction='stop'})
    $walk = Wait-Converged 'client'
    Assert ($walk.position[2] -lt 0 -and $walk.error -lt 0.12) 'Client actually walks through removed cell without stale-block oscillation'
    $gate.jitter_regression = $true
    $gate.jitter_final_error = $walk.error
    $gate.jitter_corrections = $walk.corrections
    [void] (Command 'host' @{op='edit';cell=$cell;block='leyforge:dirt'})
    Start-Sleep -Milliseconds 600
    Assert ((Read-Report 'client').cells[0].canonical -eq 'leyforge:dirt' -and (Read-Report 'client').cells[0].collision) 'HOST placement state rebuilds JOIN loaded collider'
    $gate.host_place_collision = $true
    [void] (Command 'host' @{op='edit';cell=$tree;block='leyforge:air'})
    Start-Sleep -Milliseconds 500
    Assert ((Read-Report 'client').cells[1].canonical -eq 'leyforge:air') 'HOST actual voxel tree edit converges'
    $gate.tree_edit = $true

    # Default remote character has no fabricated tool. Real held input rejects Stone.
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(3.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=$stone})
    Start-Sleep -Milliseconds 300
    [void] (Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 900
    Assert ((Read-Report 'client').feedback.reason -eq 'tool_required' -and (Read-Report 'host').cells[2].canonical -eq 'leyforge:stone') 'Default Client 2 Stone capability rejection'
    [void] (Command 'client' @{op='harvest_input';active=$false})
    $gate.tool_required = $true
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=$cell})
    Start-Sleep -Milliseconds 300
    $hidden = @(0,$y,-1)
    [void] (Command 'host' @{op='edit';cell=$hidden;block='leyforge:stone'})
    $negativeBefore = (Read-Report 'host').voxel_metrics.commits
    foreach ($bad in @(
        @{op='harvest_packet';cell=@(900000,$y,0)},
        @{op='harvest_packet';cell=$hidden;block='leyforge:stone'},
        @{op='harvest_packet';cell=@(1,$y,1);block='leyforge:air'},
        @{op='harvest_packet';cell=$cell;block='leyforge:stone'},
        @{op='harvest_packet';cell=$cell;spoof=$true;player_id=(Read-Report 'host').player_id},
        @{op='harvest_packet';cell=$cell;unsupported=$true},
        @{op='harvest_packet';cell=$cell;oversized=$true},
        @{op='harvest_packet';cell=$cell;block='leyforge:unknown'},
        @{op='harvest_packet';cell=$cell;repeat=$true}
    )) { [void] (Command 'client' $bad) }
    Start-Sleep -Milliseconds 900
    Assert ((Read-Report 'host').voxel_metrics.commits -eq $negativeBefore -and (Read-Report 'host').cells[0].canonical -eq 'leyforge:dirt') 'Malformed, forged actor, unsupported, stale, remote and replay/expired lease requests cause no mutation'
    $gate.negative_authority = $true
    $gate.hold_lease = $true
    [void] (Command 'host' @{op='edit';cell=$hidden;block='leyforge:air'})
    # Both legitimate actors hold the same cell. Shared completion revalidates it.
    [void] (Command 'host' @{op='actor_position';player_id=(Read-Report 'host').player_id;position=@(-0.5,($y+0.05),3.5)})
    $raceBefore = Read-Report 'host'
    [void] (Command 'host' @{op='host_harvest';cell=$cell})
    [void] (Command 'client' @{op='harvest_input';active=$true})
    Start-Sleep -Milliseconds 1100
    [void] (Command 'client' @{op='harvest_input';active=$false})
    [void] (Command 'host' @{op='harvest_input';active=$false})
    $race = Read-Report 'host'
    Assert ($race.voxel_metrics.commits -eq $raceBefore.voxel_metrics.commits+1 -and (Drop-Quantity $race) -eq (Drop-Quantity $raceBefore)+1) 'Same-cell contention commits exactly one edit and one defined output'
    Assert ((Read-Report 'client').cells[0].canonical -eq 'leyforge:air') 'Race peers converge'
    $gate.same_cell_race = $true
    # HOST obtains a real authoritative harvest output and consumes it for placement.
    [void] (Command 'host' @{op='host_pick_place';cell=$cell})
    Start-Sleep -Milliseconds 600
    Assert ((Read-Report 'client').cells[0].canonical -eq 'leyforge:dirt') 'Legitimate HOST inventory-backed placement replicates'
    $gate.host_inventory_placement = $true


    # Reproduce the owner's case on a verified untouched generated solid step.
    $generated = (Command 'host' @{op='generated_jitter_target';player_id=$id}).commands[-1]
    $generatedCell = @($generated.cell)
    Assert ($generated.base_block -eq $generated.current_block -and $generated.base_block -ne 'leyforge:air') 'Jitter target is untouched generated solid terrain'
    $gate.generated_jitter_cell = $generatedCell
    $gate.generated_jitter_block = $generated.base_block
    [void] (Command 'host' @{op='watch';cells=@(,$generatedCell)})
    [void] (Command 'client' @{op='watch';cells=@(,$generatedCell)})
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=$generated.client_foot})
    [void] (Command 'host' @{op='actor_position';player_id=(Read-Report 'host').player_id;position=$generated.host_foot})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=$generatedCell})
    [void] (Command 'client' @{op='voxel_pause';enable=$true})
    [void] (Command 'host' @{op='host_harvest';cell=$generatedCell})
    Start-Sleep -Milliseconds 900
    [void] (Command 'host' @{op='harvest_input';active=$false})
    Assert ((Read-Report 'host').cells[0].canonical -eq 'leyforge:air' -and (Read-Report 'client').cells[0].canonical -eq $generated.base_block) 'Exact generated stale-block reproduction: HOST air, JOIN generated solid'
    $staleStart = (Read-Report 'client').smooth_corrections
    [void] (Command 'client' @{op='move';direction='move_forward'})
    Start-Sleep -Milliseconds 800
    [void] (Command 'client' @{op='move';direction='stop'})
    $stale = Read-Report 'client'
    Assert ($stale.smooth_corrections -gt $staleStart) 'Stale collider causes measured reconciliation corrections'
    $gate.stale_collider_corrections = $stale.smooth_corrections-$staleStart
    $gate.stale_collider_error = $stale.error
    [void] (Command 'client' @{op='voxel_pause';enable=$false;cell=$generatedCell})
    Start-Sleep -Milliseconds 800
    Assert ((Read-Report 'client').cells[0].canonical -eq 'leyforge:air' -and -not (Read-Report 'client').cells[0].collision) 'Resynchronized live voxel and collider are air'
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=$generated.client_foot})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=$generatedCell})
    $cleanWalkStart = (Read-Report 'client').commands[-1].msec
    [void] (Command 'client' @{op='move';direction='move_forward'})
    Start-Sleep -Milliseconds 1000
    [void] (Command 'client' @{op='move';direction='stop'})
    $postSync = Wait-Converged 'client'
    $postTrace = Get-Content (Join-Path $evidenceRoot 'client-voxel-trace.json') -Raw | ConvertFrom-Json
    $postErrors = @($postTrace | Where-Object msec -ge $cleanWalkStart | ForEach-Object { $_.error })
    Assert ($postErrors.Count -ge 5) 'Nonempty quantitative post-sync movement trace'
    $gate.post_sync_walk_max_error = ($postErrors | Measure-Object -Maximum).Maximum
    $gate.post_sync_walk_final_error = $postSync.error
    $enteredGeneratedCell = @($postTrace | Where-Object { $_.msec -ge $cleanWalkStart -and $_.position[0] -ge $generatedCell[0] -and $_.position[0] -lt ($generatedCell[0]+1) -and $_.position[1] -ge ($generatedCell[1]-0.05) -and $_.position[1] -lt ($generatedCell[1]+1) -and $_.position[2] -ge $generatedCell[2] -and $_.position[2] -lt ($generatedCell[2]+1) })
    Assert ($enteredGeneratedCell.Count -gt 0) 'Real predicted feet enter the formerly solid generated cell'
    Assert ($postSync.error -lt 0.12 -and $gate.post_sync_walk_max_error -lt 0.6) 'After synchronization, generated-cell movement has bounded correction and final convergence'
    $gate.explicit_w53_jitter_reproduction = $true
    [void] (Command 'host' @{op='watch';cells=$watch})
    [void] (Command 'client' @{op='watch';cells=$watch})
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'host' @{op='edit';cell=$cell;block='leyforge:dirt'})
    Start-Sleep -Milliseconds 400

    [void] (Command 'client' @{op='gap';cell=$cell})
    [void] (Command 'host' @{op='edit';cell=$cell;block='leyforge:grass'})
    Start-Sleep -Milliseconds 1500
    $resync = Read-Report 'client'
    Assert ($resync.voxel_metrics.resyncs -ge 1 -and $resync.cells[0].canonical -eq 'leyforge:grass') 'Injected logical delta gap requests real-wire clean replacement'
    $gate.revision_gap_resync = $true
    [void] (Command 'host' @{op='corrupt';cell=$cell;player_id=$id;sync_id=$resync.sync_id})
    Start-Sleep -Milliseconds 1500
    $clean = Read-Report 'client'
    Assert ($clean.voxel_metrics.resyncs -gt $resync.voxel_metrics.resyncs) 'Corrupt wire hash requests resync'
    $hostHashes = (Read-Report 'host').bucket_hashes
    foreach ($p in $clean.bucket_hashes.PSObject.Properties) {
        Assert ($hostHashes.PSObject.Properties[$p.Name].Value -eq $p.Value) 'Final HOST/JOIN bucket SHA256 equality'
    }
    $gate.hash_corruption_resync = $true

    # A third identity retains separate knowledge while outside voxel interest.
    Start-Probe 'third' 'JOIN' 'third'
    $third = Wait-Ready 'third'
    [void] (Command 'third' @{op='watch';cells=$watch})
    [void] (Command 'host' @{op='relocate_remote';player_id=$third.player_id;x=140;z=3})
    Start-Sleep -Milliseconds 1400
    $thirdBefore = Read-Report 'third'
    $nearBefore = $thirdBefore.cells[0].override
    [void] (Command 'host' @{op='edit';cell=$cell;block='leyforge:air'})
    Start-Sleep -Milliseconds 500
    Assert ((Read-Report 'client').cells[0].canonical -eq 'leyforge:air' -and (Read-Report 'third').cells[0].override -eq $nearBefore) 'Relevant peer receives near edit; irrelevant third peer retains its cached state'
    Assert (@((Read-Report 'host').known.PSObject.Properties).Count -eq 2) 'Bounded bucket knowledge is per authenticated destination'
    [void] (Command 'host' @{op='relocate_remote';player_id=$third.player_id;x=2;z=4})
    Start-Sleep -Milliseconds 1400
    Assert ((Read-Report 'third').cells[0].canonical -eq 'leyforge:air') 'Previously seen stale bucket receives replacement on re-entry'
    $gate.third_identity = $true
    Stop-Probe 'third'
    [void] (Wait-Bindings 2)
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=@(0,($y+2),(-10))})
    [void] (Command 'host' @{op='host_distance';player_id=$id;distance=140})
    Start-Sleep -Milliseconds 1200
    $far = Command 'host' @{op='far_edit';x=116;z=3}
    $farCell = @($far.commands[-1].cell)
    $farBucket = @([Math]::Floor($farCell[0]/16),[Math]::Floor($farCell[1]/16),[Math]::Floor($farCell[2]/16))
    [void] (Command 'client' @{op='watch';cells=@($cell,$tree,$stone,$grass,$farCell)})
    Start-Sleep -Milliseconds 500
    Assert ((Read-Report 'client').cells[4].override -eq '') 'Out-of-range edit is not broadcast'
    [void] (Command 'host' @{op='inventory';open=$true})
    [void] (Command 'client' @{op='look';cell=@(0,($y+2),(-10))})
    $travelStart = (Read-Report 'client').commands[-1].msec
    [void] (Command 'client' @{op='move';direction='move_right';sprint=$true;jump=$true})
    Start-Sleep -Milliseconds 5500
    [void] (Command 'client' @{op='move';direction='stop'})
    $approach = Wait-Converged 'client'
    $farApplied = @($approach.voxel_events | Where-Object { $_.kind -eq 'applied' -and ($_.data.bucket -join ',') -eq ($farBucket -join ',') })
    Assert ($farApplied.Count -gt 0 -and $approach.cells[4].override -eq 'leyforge:air') 'Real input-driven approach receives current distant sparse bucket'
    Assert ($farApplied[0].data.position[0] -lt ($farCell[0]-80)) 'Authoritative snapshot arrives in prefetch margin before edited cell enters 80 m viewer'
    Assert ((Read-Report 'host').inventory_open -and (Body (Read-Report 'host') $id).viewer_exists) 'HOST UI leaves movement, voxel sync and remote terrain interest active'
    $gate.relevance_prefetch = $true
    $gate.prefetch_delivery_position = $farApplied[0].data.position
    $gate.prefetch_target_cell = $farCell
    $gate.relevance_final_error = $approach.error
    [void] (Command 'host' @{op='inventory';open=$false})
    # Representative edit traffic uses a separate channel while actual input keeps flowing.
    [void] (Command 'host' @{op='actor_position';player_id=$id;position=@(0.5,($y+0.05),3.5)})
    [void] (Wait-Converged 'client')
    [void] (Command 'client' @{op='look';cell=@(0,($y+2),(-10))})
    $trafficStart = (Read-Report 'client').commands[-1].msec
    $ackBefore = (Body (Read-Report 'host') $id).accepted
    [void] (Command 'client' @{op='move';direction='move_forward'})
    [void] (Command 'host' @{op='traffic';cell=$grass})
    [void] (Command 'client' @{op='move';direction='stop'})
    $trafficEnd = Wait-Converged 'client'
    $trafficTrace = Get-Content (Join-Path $evidenceRoot 'client-voxel-trace.json') -Raw | ConvertFrom-Json
    $trafficErrors = @($trafficTrace | Where-Object msec -ge $trafficStart | ForEach-Object { $_.error })
    Assert ($trafficErrors.Count -ge 10) 'Nonempty quantitative voxel-traffic movement trace'
    $gate.voxel_traffic_max_movement_error = ($trafficErrors | Measure-Object -Maximum).Maximum
    $gate.voxel_traffic_final_error = $trafficEnd.error
    Assert ((Body (Read-Report 'host') $id).accepted -gt $ackBefore+30 -and $trafficEnd.error -lt 0.12 -and $gate.voxel_traffic_max_movement_error -lt 1.0) 'Reliable voxel traffic does not starve movement inputs or convergence'
    $gate.movement_during_voxel_traffic = $true
    [void] (Command 'client' @{op='screenshot_voxel'})
    [void] (Command 'host' @{op='screenshot_voxel'})
    $sent = @((Read-Report 'host').voxel_events | Where-Object kind -eq 'commit')
    $applied = @((Read-Report 'client').voxel_events | Where-Object { $_.kind -eq 'applied' -and $_.data.kind -eq 'voxel_delta_batch' })
    $latencies = @()
    foreach ($event in $applied) {
        $match = @($sent | Where-Object { $_.data.revision -eq $event.data.revision -and ($_.data.bucket -join ',') -eq ($event.data.bucket -join ',') } | Select-Object -Last 1)
        if ($match.Count -gt 0) { $latencies += $event.utc_msec-$match[0].utc_msec }
    }
    Assert ($latencies.Count -ge 10) 'Measured real edit propagation samples'
    $gate.loopback_average_edit_ms = ($latencies | Measure-Object -Average).Average
    $gate.loopback_propagation_samples = $latencies.Count
    $gate.host_voxel_metrics = (Read-Report 'host').voxel_metrics

    [void] (Command 'host' @{op='save'})
    Stop-Probe 'client'
    [void] (Wait-Bindings 1)
    [void] (Command 'host' @{op='edit';cell=$cell;block='leyforge:air'})
    Start-Probe 'reconnect' 'JOIN' 'client'
    $reconnect = Wait-Ready 'reconnect'
    [void] (Command 'reconnect' @{op='watch';cells=$watch})
    Start-Sleep -Milliseconds 500
    Assert ($reconnect.player_id -eq $id -and (Read-Report 'reconnect').cells[0].canonical -eq 'leyforge:air') 'Reconnect same identity receives disconnected-period edits'
    $gate.reconnect = $true
    Stop-Probe 'reconnect'
    [void] (Command 'host' @{op='save'})
    Stop-Probe 'host'
    Start-Probe 'reload_host' 'HOST' 'host'
    [void] (Wait-Ready 'reload_host')
    Start-Probe 'reload_client' 'JOIN' 'client'
    [void] (Wait-Ready 'reload_client')
    [void] (Command 'reload_client' @{op='watch';cells=$watch})
    Start-Sleep -Milliseconds 500
    Assert ((Read-Report 'reload_client').cells[0].canonical -eq 'leyforge:air' -and (Read-Report 'reload_client').no_world_save) 'Fresh HOST reload supplies saved overrides without client save'
    $gate.host_save_reload = $true
    $gate.client_save_negative = $true
    Stop-Probe 'reload_client'
    Stop-Probe 'reload_host'
    $gate.process_checks = $checks
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
    $ownerInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tests\networking\w5_4_owner_launch.ps1') + '" -ProjectPath "' + $ownerProject + '" -FixtureRoot "' + (Join-Path $tempRoot 'owner-fixture') + '" -EvidenceRoot "' + $evidenceRoot + '"'
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
    Check ($ownerProcess.ExitCode -eq 0 -and $ownerText -match 'W5_4_OWNER_LAUNCH_PASS') "Owner-launch verification failed: $ownerText"
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
        $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $testProject 'tools\development\verify_wave_5_part_3.ps1') + '" -GodotExecutable "' + $godotPath + '"'
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
        if (-not $prior.WaitForExit(1200000)) { $prior.Kill(); throw 'W5.3 and earlier regressions timed out.' }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $evidenceRoot 'regression_w53.log'),$text)
        $priorRoot = Join-Path $testProject '.verification\wave5\w5_3'
        if (Test-Path $priorRoot) {
            # Nested retained receipts exceed Copy-Item's legacy Windows path limit.
            & robocopy.exe $priorRoot (Join-Path $evidenceRoot 'regression_w53') /E /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
            Check ($LASTEXITCODE -lt 8) 'Complete regression evidence copy failed'
        }
        Check ($prior.ExitCode -eq 0 -and $text -match 'WAVE_5_PART_3_VALIDATION_PASS') 'W5.3 complete regression failed'
        $priorRun = Get-ChildItem (Join-Path $evidenceRoot 'regression_w53') -Directory | Sort-Object Name | Select-Object -Last 1
        $priorReceipt = Get-Item -LiteralPath (Join-Path $priorRun.FullName 'gate.json')
        $priorGate = Get-Content $priorReceipt.FullName -Raw | ConvertFrom-Json
        Check ($priorGate.certified -and $priorGate.passed) 'W5.3 receipt uncertified'
        $gate.regressions = 'Wave 0, 1, 2, 3, 4, W5.1, W5.2 and W5.3 PASS'
    }

    foreach ($relative in $workingManifest.Keys) { Check ((Get-FileHash (Join-Path $repositoryRoot $relative)).Hash -eq $workingManifest[$relative]) "Source changed during run: $relative" }
    $finalPaths = @(Snapshot-Paths)
    Check (@(Compare-Object $paths $finalPaths).Count -eq 0) 'Source inventory changed during run'
    $gate.snapshot_matches_source = $true
    $gate.client_authority_separation = $true
    $gate.passed = $true
    $gate.certified = -not $SkipRegression
    Write-Output 'WAVE_5_PART_4_VALIDATION_PASS'
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
    Write-Output "WAVE_5_PART_4_EVIDENCE=$evidenceRoot"
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved)) { try { Remove-Item -LiteralPath $resolved -Recurse -Force } catch { Write-Warning ("Temporary cleanup incomplete at " + $resolved + ": " + $_.Exception.Message) } }
}