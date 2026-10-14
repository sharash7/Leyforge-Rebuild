[CmdletBinding()]
param(
    [string]$Address='',
    [ValidateRange(1,65535)][int]$Port=25652,
    [string]$ProfilePath='user://identity/local_profile.json', [string]$GodotRoot='', [string]$RuntimeLogPath=''
)
$ErrorActionPreference='Stop'
if (-not $Address) { $Address=Read-Host 'HOST address' }
if ($Address -notmatch '^[A-Za-z0-9:][A-Za-z0-9.:-]{0,252}$') { throw 'Invalid HOST address' }
. (Join-Path $PSScriptRoot 'w5_2_launcher.ps1')
Start-W52Game -SessionArguments @('--session=JOIN',"--address=$Address","--port=$Port","--profile-path=$ProfilePath") -RuntimeLogPath $RuntimeLogPath -GodotRoot $GodotRoot
