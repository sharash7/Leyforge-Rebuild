[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port=25652,[string]$GatewayExternalAddress='')
$ErrorActionPreference='Stop'
Get-NetConnectionProfile | Select-Object InterfaceAlias,NetworkCategory,IPv4Connectivity,IPv6Connectivity
Get-NetIPAddress | Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(127\.|169\.254\.|::1$|fe80:)' } | Select-Object InterfaceAlias,IPAddress
Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess
Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction
Write-Output "Leyforge uses UDP $Port. Permit inbound HOST executable/game UDP on the active firewall profile. No TCP gameplay forwarding required."
Write-Output 'Manual IPv4 routing: external UDP game port -> HOST LAN address / UDP game port. UPnP is optional; see HOST F8 session panel for result.'
if ($GatewayExternalAddress -match '^(10\.|127\.|0\.|192\.168\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)') { Write-Warning 'Direct inbound hosting may be blocked by CGNAT/double NAT.' }
Write-Output 'Listening/mapping does not prove internet reachability. Test from a separate internet connection; no firewall/router changes were made.'
