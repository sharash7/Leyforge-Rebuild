[CmdletBinding()]
param(
    [string]$Address='127.0.0.1',
    [ValidateRange(1,65535)][int]$Port=25652,
    [string]$ProfilePath='user://identity/development/wave5-client-2.json', [string]$GodotRoot='', [string]$RuntimeLogPath=''
)
$ErrorActionPreference='Stop'
if (-not $Address) { $Address=Read-Host 'HOST address' }
if ($Address -notmatch '^[A-Za-z0-9:][A-Za-z0-9.:-]{0,252}$') { throw 'Invalid HOST address' }
. (Join-Path $PSScriptRoot 'w5_2_launcher.ps1')
Start-W52Game -SessionArguments @('--session=JOIN',"--address=$Address","--port=$Port","--profile-path=$ProfilePath") -RuntimeLogPath $RuntimeLogPath -GodotRoot $GodotRoot
