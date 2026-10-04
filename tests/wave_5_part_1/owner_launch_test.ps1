[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $ProjectPath,
    [Parameter(Mandatory=$true)][string] $FixtureRoot,
    [Parameter(Mandatory=$true)][string] $EvidenceRoot
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$fixture = [IO.Path]::GetFullPath($FixtureRoot)
$evidence = (Resolve-Path -LiteralPath $EvidenceRoot).Path
if (-not $fixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Owner fixtures must be external disposable temporary data.' }
$console = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
$launcher = Join-Path $project 'tools\development\run_wave_5_part_1_owner_test.ps1'
$utf8 = New-Object Text.UTF8Encoding($false)
$script:checks = 0
$script:running = @()
$cases = @()
function Check([bool] $Condition,[string] $Message) {
    $script:checks++
    if (-not $Condition) { throw $Message }
}
function Read-Payload([string] $Path) {
    $envelope = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Check ($envelope.save_version -eq 4) 'Owner launcher must retain save v4.'
    Check ((Get-Item -LiteralPath $Path).Length -gt 0) 'Saved world is readable.'
    return ($envelope.payload_json | ConvertFrom-Json)
}
# Godot keeps the live log open for writing; permit concurrent writer access.
function Read-LiveLog([string] $Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
# Capture expected import failures as text/exit status, not PowerShell
# NativeCommandError records, so their safety assertions still execute.
function Invoke-Launcher([string] $Path,[string[]] $Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $tokens = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Path) + $Arguments
    $info.Arguments = (($tokens | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    [void] $proc.Start()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(180000)) { $proc.Kill();$proc.WaitForExit();throw 'Owner launcher timed out.' }
    return @{text=$stdout.Result + $stderr.Result;exit_code=$proc.ExitCode}
}
function Launch-Normal([string] $Name,[string] $WorldId,[int] $Seed,[bool] $UseDefaults) {
    $log = Join-Path $evidence ('owner_' + $Name + '_runtime.log')
    $launchArguments = @('-RuntimeLogPath',$log)
    if (-not $UseDefaults) { $launchArguments += @('-WorldId',$WorldId,'-Seed',"$Seed") }
    $result = Invoke-Launcher $launcher $launchArguments
    $code = $result.exit_code
    $text = $result.text
    [IO.File]::WriteAllText((Join-Path $evidence ('owner_' + $Name + '_launcher.log')),$text,$utf8)
    Check ($code -eq 0 -and $text -match 'W5_1_OWNER_IMPORT_PASS') 'Import-first owner launcher must succeed.'
    Check ($text -match "W5_1_OWNER_LAUNCH_STARTED pid=(\d+) world=$WorldId seed=$Seed") 'Launcher forwards normal world/seed arguments.'
    $gameId = [int] $Matches[1]
    $game = Get-Process -Id $gameId
    # Pin the Windows process handle before exit so ExitCode remains queryable.
    [void] $game.Handle
    $script:running += $game
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    $runtime = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $log) { $runtime = Read-LiveLog $log }
        if ($runtime -match 'LEYFORGE_WAVE_1_RUNTIME_READY') { break }
        if ($game.HasExited) { throw "Owner runtime exited before readiness: $runtime" }
        Start-Sleep -Milliseconds 200
    }
    Check ($runtime -match 'LEYFORGE_WAVE_1_RUNTIME_READY' -and $runtime -match 'OpenGL') 'Normal graphical owner runtime reaches readiness.'
    Check ($runtime -notmatch '(?m)^\s*(SCRIPT ERROR|ERROR:)') 'Normal runtime has no script/native errors.'
    Check ($runtime -notmatch 'TEST_SURVIVAL_RATE|RENDERED_[A-Z0-9]+_PASS') 'Owner launch uses production runtime without verification flags.'
    Check ($game.CloseMainWindow()) 'Disposable graphical game accepts normal close.'
    Check ($game.WaitForExit(30000)) 'Normal close saves and exits without a timeout.'
    Check ($game.ExitCode -eq 0) "Normal owner runtime exits successfully (exit $($game.ExitCode))."
    $runtime = Read-LiveLog $log
    Check ($runtime -match 'WAVE_2_SAVE_PASS' -and $runtime -notmatch '(?m)^\s*(SCRIPT ERROR|ERROR:)') 'Normal close saved the authoritative character.'
    Write-Output "OWNER_RUNTIME_PASS case=$Name"
}
function Fail-Canonical([string] $Name,[string] $Canonical) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $console
    $info.WorkingDirectory = $project
    $info.Arguments = '--headless --path "' + $project + '" -- --world-id=canonical-corruption --seed=184552221'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    [void] $proc.Start()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(30000)) { $proc.Kill();$proc.WaitForExit();throw 'Corruption startup timed out.' }
    $text = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $evidence ('owner_canonical_' + $Name + '.log')),$text,$utf8)
    Check ($proc.ExitCode -ne 0 -and $text -match 'Canonical local identity is unreadable, oversized or malformed') 'Canonical corruption fails visibly instead of falling back.'
    Check (-not (Test-Path -LiteralPath ($Canonical + '.pending'))) 'Corrupt canonical does not create replacement pending identity.'
}
try {
    $cache = Join-Path $project '.godot\global_script_class_cache.cfg'
    Check (-not (Test-Path -LiteralPath (Join-Path $project '.godot'))) 'Owner proof begins with fresh project snapshot and no .godot directory.'
    foreach ($kind in @('historical','legacy')) {
        $caseDirectory = if ($kind -eq 'historical') { 'h' } else { 'l' }
        $caseRoot = Join-Path $fixture $caseDirectory
        $env:APPDATA = Join-Path $caseRoot 'ad'
        $env:LOCALAPPDATA = Join-Path $caseRoot 'ld'
        $userdata = Join-Path $env:APPDATA 'Godot\app_userdata\Leyforge'
        New-Item -ItemType Directory -Force -Path $userdata,$env:LOCALAPPDATA | Out-Null
        $generic = Join-Path $userdata 'profile.json'
        $canonical = Join-Path $userdata 'identity\local_profile.json'
        $oldId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        if ($kind -eq 'historical') {
            $raw = @{settings_version=1;bindings=@{forward='W';jump='Space'};accessibility=@{ui_scale=1.25};quality='high';sprint_mode='hold';tutorial_mode='normal'} | ConvertTo-Json -Depth 4
            $raw += ' ' * (1941 - $utf8.GetByteCount($raw))
        } else { $raw = @{profile_version=1;player_id=$oldId} | ConvertTo-Json }
        [IO.File]::WriteAllText($generic,$raw,$utf8)
        $genericHash = (Get-FileHash -LiteralPath $generic -Algorithm SHA256).Hash
        Check ($kind -ne 'historical' -or (Get-Item -LiteralPath $generic).Length -eq 1941) 'Historical owner settings fixture is exactly 1941 bytes.'
        Check (-not (Test-Path -LiteralPath $canonical)) 'Canonical identity starts absent.'
        $worldId = if ($kind -eq 'historical') { 'wave5-w51-owner-test' } else { 'wave5-legacy-owner-test' }
        $seed = if ($kind -eq 'historical') { 184552221 } else { 442211 }
        Launch-Normal ($kind + '_first') $worldId $seed ($kind -eq 'historical')
        Check (Test-Path -LiteralPath $cache) 'Owner import generated class cache from clean source.'
        $cacheText = [IO.File]::ReadAllText($cache)
        foreach ($class in @('LfeLocalProfile','LfePlayerCharacter','LfePlayerResourceState','LfeGameplayAuthority')) { Check ($cacheText.Contains($class)) "Global class registered: $class" }
        Check (Test-Path -LiteralPath $canonical) 'Canonical identity created separately.'
        $identity = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
        $canonicalHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
        Check ($identity.profile_version -eq 1 -and $identity.player_id -cmatch '^[0-9a-f]{32}$') 'Canonical identity is minimal valid 128-bit record.'
        Check ($kind -ne 'legacy' -or $identity.player_id -eq $oldId) 'Early W5.1 identity reused without generating a new ID.'
        Check ((Get-FileHash -LiteralPath $generic -Algorithm SHA256).Hash -eq $genericHash) 'Generic profile byte hash unchanged after launch.'
        $savePath = Join-Path $userdata "worlds\$worldId\world.json"
        $saved = Read-Payload $savePath
        Check ($saved.metadata.seed -eq $seed -and $saved.metadata.world_id -eq $worldId) 'Requested world ID/seed used by normal save.'
        Check ($saved.metadata.owner_player_id -eq $identity.player_id -and $saved.players.Count -eq 1 -and $saved.players[0].player_id -eq $identity.player_id) 'Normal world owner/character uses canonical identity.'
        Launch-Normal ($kind + '_restart') $worldId $seed ($kind -eq 'historical')
        $restarted = Read-Payload $savePath
        Check ($restarted.metadata.owner_player_id -eq $identity.player_id -and $restarted.players[0].player_id -eq $identity.player_id) 'Restart retains world character association.'
        Check ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -eq $canonicalHash) 'Canonical identity bytes stable through genuine restart.'
        Check ((Get-FileHash -LiteralPath $generic -Algorithm SHA256).Hash -eq $genericHash) 'Historical profile remains byte-identical through restart.'
        $cases += @{case=$kind;profile_bytes=(Get-Item -LiteralPath $generic).Length;generic_sha256_before=$genericHash;generic_sha256_after=(Get-FileHash -LiteralPath $generic).Hash;player_id=$identity.player_id;world_id=$worldId;seed=$seed}
    }
    $original = [IO.File]::ReadAllBytes($canonical)
    foreach ($bad in @(@{name='malformed';text='bad JSON'},@{name='oversized';text=('x'*1025)})) {
        [IO.File]::WriteAllText($canonical,$bad.text,$utf8)
        $hash = (Get-FileHash -LiteralPath $canonical).Hash
        Fail-Canonical $bad.name $canonical
        Check ((Get-FileHash -LiteralPath $canonical).Hash -eq $hash) 'Corrupt canonical bytes remain intact.'
    }
    [IO.File]::WriteAllBytes($canonical,$original)
    $locked = [IO.File]::Open($canonical,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try { Fail-Canonical 'unreadable' $canonical } finally { $locked.Dispose() }
    Check ((Get-FileHash -LiteralPath $canonical).Hash -eq $canonicalHash) 'Unreadable canonical retains original identity bytes.'
    Check ((Get-FileHash -LiteralPath $generic).Hash -eq $genericHash) 'Canonical failure never modifies valid legacy generic identity.'

    # Import errors must stop before any graphical process starts.
    $broken = Join-Path $fixture 'broken_project'
    New-Item -ItemType Directory -Force -Path (Join-Path $broken 'tools\development') | Out-Null
    Copy-Item -LiteralPath $launcher -Destination (Join-Path $broken 'tools\development\run_wave_5_part_1_owner_test.ps1')
    [IO.File]::WriteAllText((Join-Path $broken 'project.godot'),"[application]`nconfig/name=`"Broken owner fixture`"`n[autoload]`nBroken=`"*res://broken.gd`"`n",$utf8)
    [IO.File]::WriteAllText((Join-Path $broken 'broken.gd'),"extends Node`nfunc broken(`n",$utf8)
    $badResult = Invoke-Launcher (Join-Path $broken 'tools\development\run_wave_5_part_1_owner_test.ps1') @()
    $badCode = $badResult.exit_code
    $badText = $badResult.text
    [IO.File]::WriteAllText((Join-Path $evidence 'owner_import_failure.log'),$badText,$utf8)
    Check ($badCode -ne 0 -and $badText -match 'SCRIPT ERROR' -and $badText -notmatch 'W5_1_OWNER_LAUNCH_STARTED') 'Import script error prevents graphical launch.'
    @{passed=$true;checks=$script:checks;clean_cache_start=$true;normal_runtime=$true;cases=$cases;canonical_corruption=@('malformed','oversized','unreadable');import_failure_blocks_launch=$true} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'owner_launch.json') -Encoding UTF8
    Write-Output "W5_1_OWNER_LAUNCH_TEST_PASS checks=$script:checks"
} finally {
    foreach ($game in $script:running) {
        if (-not $game.HasExited) {
            [void] $game.CloseMainWindow()
            if (-not $game.WaitForExit(5000)) { $game.Kill();$game.WaitForExit() }
        }
    }
}
