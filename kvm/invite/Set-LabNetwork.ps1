#Requires -Version 5.1
<#
.SYNOPSIS
    Donner à la VM son adresse fixe sur le LAN isolé 10.77.10.0/24.
.DESCRIPTION
    Exécuté par lab.sh via l'agent QEMU, en SYSTEM. Le LAN n'a ni DHCP ni routeur :
    DC01 fournit le DNS de learn-it.local à toutes les VM.
    La passerelle 10.77.10.254 n'existe pas et rien ne sort du LAN. Elle est déclarée parce que
    Windows classe un réseau sans passerelle en « réseau non identifié », donc en profil
    pare-feu Public : avec elle, les membres reconnaissent le domaine (DomainAuthenticated).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IPAddress,
    [string]$DnsServer = '10.77.10.10',
    [string]$Gateway = '10.77.10.254',
    [int]$PrefixLength = 24
)
$ErrorActionPreference = 'Stop'

# Une seule carte virtio est prévue par VM ; refuser une situation ambiguë.
$adapters = @(Get-NetAdapter -Physical | Where-Object InterfaceDescription -like '*VirtIO*')
if ($adapters.Count -ne 1) {throw "Une carte VirtIO attendue, $($adapters.Count) trouvée(s)."}
$adapter = $adapters[0]
if ($adapter.Name -ne 'LAN-TP') {Rename-NetAdapter -Name $adapter.Name -NewName 'LAN-TP'}

Set-NetIPInterface -InterfaceAlias 'LAN-TP' -AddressFamily IPv4 -Dhcp Disabled
$current = @(Get-NetIPAddress -InterfaceAlias 'LAN-TP' -AddressFamily IPv4 -ErrorAction SilentlyContinue)
if (-not ($current | Where-Object IPAddress -eq $IPAddress)) {
    # Retirer l'adresse automatique (APIPA) avant de poser l'adresse du plan IP.
    $current | Remove-NetIPAddress -Confirm:$false
    New-NetIPAddress -InterfaceAlias 'LAN-TP' -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null
}
if (-not (Get-NetRoute -InterfaceAlias 'LAN-TP' -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
    New-NetRoute -InterfaceAlias 'LAN-TP' -DestinationPrefix '0.0.0.0/0' -NextHop $Gateway | Out-Null
}
Set-DnsClientServerAddress -InterfaceAlias 'LAN-TP' -ServerAddresses $DnsServer

Get-NetIPConfiguration -InterfaceAlias 'LAN-TP' |
    Select-Object InterfaceAlias,
        @{n='IPv4';e={$_.IPv4Address.IPAddress}},
        @{n='Passerelle';e={$_.IPv4DefaultGateway.NextHop}},
        @{n='DNS';e={$_.DNSServer.ServerAddresses -join ','}} |
    Format-List
