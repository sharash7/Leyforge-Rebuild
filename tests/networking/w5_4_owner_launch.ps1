[CmdletBinding()]
param([string] $ProjectPath, [string] $FixtureRoot, [string] $EvidenceRoot)
$ErrorActionPreference = 'Stop'
$games = @()
$checks = 0
$report = @{passed=$false;clean_cache=$false;normal_runtime=$true}
function Check([bool] $Value, [string] $Message) { $script:checks++; if (-not $Value) { throw $Message } }
function Launch([string] $Name, [string] $Script, [string] $Profile) {
    $app = Join-Path $FixtureRoot "$Profile-app"
    $local = Join-Path $FixtureRoot "$Profile-local"
    New-Item -ItemType Directory -Force $app,$local | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $log = Join-Path $EvidenceRoot "$Name-runtime.log"
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $ProjectPath "tools\development\$Script") + '" -Port 25655 -RuntimeLogPath "' + $log + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['APPDATA'] = $app
    $info.EnvironmentVariables['LOCALAPPDATA'] = $local
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    [void] $proc.Start()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(180000)) { $proc.Kill(); throw 'Owner launcher timeout' }
    $text = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $EvidenceRoot "$Name-launch.log"),$text)
    Check ($proc.ExitCode -eq 0 -and $text -match 'W5_2_OWNER_IMPORT_PASS') "$Name import-first launcher"
    Check ($text -match 'W5_2_OWNER_LAUNCH_STARTED pid=(\d+)') "$Name game launch marker"
    $game = Get-Process -Id ([int] $Matches[1])
    # Retain the Windows handle so ExitCode stays available after normal close.
    [void] $game.Handle
    $script:games += $game
    return $game
}
function Wait-Log([string] $Name, [string] $Marker) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        # Read a scalar snapshot of the live log under explicit sharing.
        # Get-Content -Raw can return multiple chunks during concurrent appends.
        [string] $text = ''
        try {
            $stream = [IO.File]::Open((Join-Path $EvidenceRoot "$Name-runtime.log"),[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $reader = New-Object IO.StreamReader($stream)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } catch {}
        if ($text -match [regex]::Escape($Marker)) { Check ($text -notmatch '(?m)^\s*(SCRIPT ERROR|ERROR:)') "$Name runtime errors"; return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name missing $Marker"
}
function Close-Game($Game) {
    Check ($Game.CloseMainWindow()) 'Normal window close request'
    Check ($Game.WaitForExit(20000)) 'Normal window close completes'
    Check ($Game.ExitCode -eq 0) "Normal game exit ($($Game.ExitCode))"
}
try {
    # Fresh snapshot import cache prerequisite is established by the first host launcher.
    $report.clean_cache = -not (Test-Path (Join-Path $ProjectPath '.godot'))
    $hostGame = Launch 'owner_host' 'run_wave_5_part_4_host.ps1' 'host'
    Wait-Log 'owner_host' 'state=HOSTING'
    Wait-Log 'owner_host' 'LEYFORGE_WAVE_1_RUNTIME_READY'
    $clientGame = Launch 'owner_client' 'run_wave_5_part_4_join.ps1' 'client'
    Wait-Log 'owner_client' 'state=CONNECTED'
    Wait-Log 'owner_client' 'W5_4_WORLD_SYNCHRONIZED'
    Wait-Log 'owner_client' 'W5_3_CLIENT_WORLD_READY'
    Wait-Log 'owner_host' 'W5_3_BODY_SPAWN'
    $clientProfile = Join-Path $FixtureRoot 'client-app\Godot\app_userdata\Leyforge\identity\development\wave5-client-2.json'
    $ownerProfile = Join-Path $FixtureRoot 'host-app\Godot\app_userdata\Leyforge\identity\local_profile.json'
    $clientId = (Get-Content $clientProfile -Raw | ConvertFrom-Json).player_id
    $hostId = (Get-Content $ownerProfile -Raw | ConvertFrom-Json).player_id
    $hash = (Get-FileHash $clientProfile).Hash
    Check ($clientId -ne $hostId) 'Owner/client stable profiles differ'
    Check (-not (Test-Path (Join-Path $FixtureRoot 'client-app\Godot\app_userdata\Leyforge\worlds'))) 'Normal JOIN no local world'
    Close-Game $clientGame
    Wait-Log 'owner_host' 'LFE_SESSION left'
    $again = Launch 'owner_reconnect' 'run_wave_5_part_4_join.ps1' 'client'
    Wait-Log 'owner_reconnect' 'state=CONNECTED'
    Wait-Log 'owner_reconnect' 'W5_4_WORLD_SYNCHRONIZED'
    Wait-Log 'owner_reconnect' 'W5_3_CLIENT_WORLD_READY'
    Check ((Get-FileHash $clientProfile).Hash -eq $hash) 'Exact JOIN launcher reuses identical profile bytes'
    Close-Game $again
    Close-Game $hostGame
    $worldPath = Join-Path $FixtureRoot 'host-app\Godot\app_userdata\Leyforge\worlds\wave5-w54-owner-test\world.json'
    $envelope = Get-Content $worldPath -Raw | ConvertFrom-Json
    $world = $envelope.payload_json | ConvertFrom-Json
    Check ($envelope.save_version -eq 4 -and $world.metadata.seed -eq 184552221) 'Normal HOST defaults and save v4'
    Check ($world.metadata.owner_player_id -eq $hostId -and @($world.players).Count -eq 2) 'Normal HOST save two distinct records, same owner'
    Check (@($world.players | Where-Object player_id -eq $clientId).Count -eq 1) 'Remote record durable after manual reconnect'
    $report.passed = $true
    $report.client_identity_stable = $true
    $report.client_no_save = $true
    Write-Output 'W5_4_OWNER_LAUNCH_PASS'
} catch { $report.failure = $_.Exception.Message; throw } finally {
    foreach ($game in $games) { if (-not $game.HasExited) { $game.Kill(); $game.WaitForExit() } }
    $report.checks = $checks
    $report | ConvertTo-Json | Set-Content (Join-Path $EvidenceRoot 'owner_launch.json') -Encoding UTF8
}