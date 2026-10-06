[CmdletBinding()]
param([string]$ProjectPath,[string]$ProofDir,[string]$ProofName,[ValidateSet('HOST','JOIN')][string]$Mode,[int]$Port)
$ErrorActionPreference='Stop'
if(-not [IO.Path]::IsPathRooted($ProofDir) -or -not $ProjectPath.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Owner input proof requires an isolated temp project'}
$env:LEYFORGE_REPAIR_PROOF_DIR=$ProofDir
$env:LEYFORGE_REPAIR_PROOF_NAME=$ProofName
$launcher=if($Mode -eq 'HOST'){'run_wave_5_part_6_host.ps1'}else{'run_wave_5_part_6_join.ps1'}
$log=Join-Path $ProofDir "$ProofName-runtime.log"
& (Join-Path $ProjectPath "tools/development/$launcher") -Port $Port -RuntimeLogPath $log | Tee-Object -Variable output
if(($output -join [Environment]::NewLine) -notmatch 'W5_2_OWNER_LAUNCH_STARTED pid=(\d+)'){throw 'Owner launcher did not start a process'}
$game=Get-Process -Id ([int]$Matches[1]);[void]$game.Handle
if(-not $game.WaitForExit(650000)){$game.Kill();throw 'Owner input proof timeout'}
Get-Content -LiteralPath $log
if($game.ExitCode -ne 0){throw "Owner input proof exit $($game.ExitCode)"}
