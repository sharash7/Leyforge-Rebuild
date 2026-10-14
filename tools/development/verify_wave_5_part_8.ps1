[CmdletBinding()]
param([string]$GodotExecutable='D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',[switch]$SkipRegression)
$ErrorActionPreference='Stop'
$runner=(Resolve-Path -LiteralPath $GodotExecutable).Path
if((Get-FileHash -LiteralPath $runner).Hash -ne '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A'){throw 'Approved shutdown-fixed runner required'}
$args58=@((Join-Path $PSScriptRoot 'w5_8_verify.py'),'--runner',$runner)
if($SkipRegression){$args58+='--skip-regression'}
& python @args58
if($LASTEXITCODE -ne 0){throw 'W5.8 verification failed; retained gate.json identifies the blocker'}
