[CmdletBinding()]
param([string]$KitPath,[string]$EvidencePath,[int]$Port=25660)
$ErrorActionPreference='Stop'
$log=Join-Path $EvidencePath 'kit-join-runtime.log'
& (Join-Path $KitPath 'tools/development/run_wave_5_part_8_remote_join.ps1') -Address 127.0.0.1 -Port $Port -GodotRoot (Join-Path $KitPath runtime) -RuntimeLogPath $log | Tee-Object -Variable output
if(($output -join "`n") -notmatch 'W5_2_OWNER_LAUNCH_STARTED pid=(\d+)'){throw 'Portable launcher failed'}
$game=Get-Process -Id ([int]$Matches[1])
try{
 $deadline=[DateTime]::UtcNow.AddSeconds(50)
 do{
  $text=''
  try{
   $stream=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
   $reader=New-Object IO.StreamReader($stream)
   try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
  }catch{}
  if($text -match 'state=CONNECTED' -and $text -match 'LEYFORGE_WAVE_1_RUNTIME_READY'){break}
  if($game.HasExited){throw 'Portable JOIN exited before world ready'}
  Start-Sleep -Milliseconds 100
 }while([DateTime]::UtcNow -lt $deadline)
 if($text -notmatch 'state=CONNECTED' -or $text -notmatch 'LEYFORGE_WAVE_1_RUNTIME_READY'){throw 'Portable JOIN readiness timeout'}
 if($text -match 'SCRIPT ERROR|(?m)^ERROR:'){throw 'Portable JOIN engine errors'}
 $identity=Join-Path $env:APPDATA 'Godot/app_userdata/Leyforge/identity/local_profile.json'
 $profile=Get-Content -LiteralPath $identity -Raw | ConvertFrom-Json
 if($profile.player_id -notmatch '^[a-f0-9]{32}$'){throw 'Portable tester identity missing'}
 if(Test-Path (Join-Path $env:APPDATA 'Godot/app_userdata/Leyforge/worlds')){throw 'JOIN created an authoritative world save'}
 @{passed=$true;ready=$true;unique_local_identity=$profile.player_id;no_world_save=$true;bundled_runtime=$true;prompt_environment_only=$true} | ConvertTo-Json | Set-Content (Join-Path $EvidencePath 'kit-launch.json') -Encoding UTF8
 [void]$game.CloseMainWindow()
 if(-not $game.WaitForExit(10000)){$game.Kill();throw 'Portable JOIN close timed out'}
}finally{if(-not $game.HasExited){$game.Kill()}}
