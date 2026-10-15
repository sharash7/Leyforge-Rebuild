[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')][string]$WorldId='wave5-w59-owner-test',
    [ValidateRange(0,2147483647)][int]$Seed=184552221,
    [ValidateRange(1,65535)][int]$Port=25652,
    [string]$ProfilePath='user://identity/local_profile.json',
    [string]$GodotRoot='', [string]$BindAddress='*', [switch]$EnableUpnp,
    [string]$RuntimeLogPath=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'w5_2_launcher.ps1')
Start-W52Game -SessionArguments @('--session=HOST',"--world-id=$WorldId","--seed=$Seed","--port=$Port","--profile-path=$ProfilePath","--bind-address=$BindAddress",("--enable-upnp="+$EnableUpnp.IsPresent.ToString().ToLowerInvariant())) -RuntimeLogPath $RuntimeLogPath -GodotRoot $GodotRoot
