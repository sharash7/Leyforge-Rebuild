[CmdletBinding()]
param(
 [string]$GodotExecutable='D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
 [switch]$SkipRegression,
 [ValidateRange(1,3600)][int]$SoakSeconds=660
)
$ErrorActionPreference='Stop'
$runner=(Resolve-Path -LiteralPath $GodotExecutable).Path
if((Get-FileHash -LiteralPath $runner).Hash -ne '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A'){throw 'Approved shutdown-fixed runner required'}
$arguments59=@((Join-Path $PSScriptRoot 'w5_9_verify.py'),'--runner',$runner,'--soak-seconds',$SoakSeconds)
if($SkipRegression){$arguments59+='--skip-regression'}
& python @arguments59
if($LASTEXITCODE -ne 0){throw 'W5.9 verification failed; retained gate.json identifies the blocker'}
