[CmdletBinding()]
param([string]$SnapshotPath,[string]$TempRoot,[string]$EvidencePath)
$ErrorActionPreference='Stop'
if(-not $TempRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Isolated temporary root required'}
$testProject=$SnapshotPath
$tempRoot=$TempRoot
$evidenceRoot=$EvidencePath
$pins=Get-Content (Join-Path $EvidencePath source_manifest.json) -Raw | ConvertFrom-Json
$manifest=@{}
foreach($pin in $pins.PSObject.Properties){$manifest[$pin.Name]=$pin.Value}
$gate=@{}
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
# Reuse the established physical input/observation autoload generator. Its
# generated tests attach to the normal scene; production scripts stay exact.
. (Join-Path $SnapshotPath 'tools/development/w5_7_owner_fixture.ps1')
$config=Join-Path $testProject project.godot
[IO.File]::AppendAllText($config,("`nW58FixtureInvite="+'"*res://tests/networking/w5_8_regression_bridge.gd"'+"`n"),(New-Object Text.UTF8Encoding($false)))
@{project=$testProject;project_sha256=(Get-FileHash $config).Hash;clean_cache=(-not(Test-Path (Join-Path $testProject '.godot')));normal_main_scene=$true;test_only_private_invite_bridge=$true} | ConvertTo-Json | Set-Content (Join-Path $EvidencePath owner-preparation.json) -Encoding UTF8
