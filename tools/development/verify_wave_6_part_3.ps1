[CmdletBinding()]
param(
 [string]$GodotExecutable='D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe',
 [switch]$FocusedOnly
)
$ErrorActionPreference='Stop'
$runner=(Resolve-Path -LiteralPath $GodotExecutable).Path
if((Get-FileHash -LiteralPath $runner).Hash -ne '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A'){throw 'Approved shutdown-fixed runner required'}
$voxelArgs=@((Join-Path $PSScriptRoot 'w6_3_verify.py'),'--runner',$runner)
if($FocusedOnly){$voxelArgs+='--focused-only'}
& python @voxelArgs
if($LASTEXITCODE -ne 0){throw 'W6.3 incomplete; retained gate.json identifies failures'}
