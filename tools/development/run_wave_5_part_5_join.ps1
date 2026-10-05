[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.:-]{0,252}$')] [string] $Address = '127.0.0.1',
    [ValidateRange(1,65535)] [int] $Port = 25652,
    [string] $ProfilePath = 'user://identity/development/wave5-client-2.json',
    [string] $RuntimeLogPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'w5_2_launcher.ps1')
Start-W52Game @("--session=JOIN","--address=$Address","--port=$Port","--profile-path=$ProfilePath") $RuntimeLogPath