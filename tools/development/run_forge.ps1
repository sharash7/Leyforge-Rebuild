[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
& python (Join-Path $PSScriptRoot 'w6_2_verify.py') --launch --runner 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
if($LASTEXITCODE -ne 0){throw 'Forge launch failed; inspect the printed evidence folder'}
