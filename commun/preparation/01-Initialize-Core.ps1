#Requires -Version 5.1
#Requires -RunAsAdministrator
<# Console locale, une seule carte reseau, avant installation des roles. Pas de redemarrage automatique. #>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateSet('DC01','SRV01','ADM01')][string]$Name,
      [string]$ConfigPath=(Join-Path $PSScriptRoot '..\config\lab.json'))
$ErrorActionPreference='Stop'
$cfg=Get-Content $ConfigPath -Raw | ConvertFrom-Json
$v=$cfg.VMs | Where-Object Name -eq $Name
$adapters=@(Get-NetAdapter | Where-Object Status -eq Up)
if ($adapters.Count -ne 1) {throw 'Le TP attend exactement une carte active. Choisir/corriger la VM en console.'}
$nic=$adapters[0]
$ipv4=@(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 | Where-Object IPAddress -notlike '169.254.*')
$other=@($ipv4 | Where-Object IPAddress -ne $v.IPAddress)
if ($other.Count) {throw 'Une autre IPv4 existe. Revenir au modele vierge ou la retirer explicitement en console.'}
if ($PSCmdlet.ShouldProcess($Name,'Configurer IPv4, DNS, WinRM')) {
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -Dhcp Disabled
    if (-not ($ipv4 | Where-Object IPAddress -eq $v.IPAddress)) {
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $v.IPAddress -PrefixLength $cfg.PrefixLength | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $cfg.Dns
    $profile=Get-NetConnectionProfile -InterfaceIndex $nic.ifIndex
    if ($profile.NetworkCategory -ne 'DomainAuthenticated') {
        Set-NetConnectionProfile -InterfaceIndex $nic.ifIndex -NetworkCategory Private
    }
    Enable-PSRemoting -Force
    Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue | Set-NetFirewallRule -RemoteAddress '10.77.10.30'
    if (-not (Get-NetFirewallRule -Name 'PSLAB-ICMP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'PSLAB-ICMP' -DisplayName 'PSLAB ICMP diagnostic' -Direction Inbound `
            -Protocol ICMPv4 -IcmpType 8 -Action Allow -RemoteAddress '10.77.10.0/24' | Out-Null
    }
    New-Item C:\Lab\preuves -ItemType Directory -Force | Out-Null
    if ($env:COMPUTERNAME -ne $Name) {Rename-Computer -NewName $Name -Force;Write-Warning 'Redemarrage requis: Restart-Computer en console.'}
}
