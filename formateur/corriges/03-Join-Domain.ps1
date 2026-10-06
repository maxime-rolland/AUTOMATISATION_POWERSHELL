#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][pscredential]$Credential)
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -notin @('ADM01','SRV01')) {throw 'Serveur membre attendu.'}
$cs=Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain) {
    if ($cs.Domain -ne 'campus.test') {throw 'Autre domaine: intervention manuelle requise.'}
    Write-Output 'Deja membre de campus.test.';return
}
Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV -ErrorAction Stop | Out-Null
Add-Computer -DomainName campus.test -Credential $Credential -PassThru
Write-Warning 'Redemarrage requis. Restart-Computer en console, puis ouvrir une session CAMPUS.'
