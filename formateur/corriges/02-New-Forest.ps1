#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][securestring]$DsrmPassword)
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -ne 'DC01') {throw 'Executez sur DC01 uniquement.'}
$cs=Get-CimInstance Win32_ComputerSystem
if ($cs.DomainRole -ge 4) {throw 'Deja controleur de domaine: ne pas repromouvoir.'}
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
Test-ADDSForestInstallation -DomainName campus.test -DomainNetbiosName CAMPUS `
    -InstallDns -SafeModeAdministratorPassword $DsrmPassword
Install-ADDSForest -DomainName campus.test -DomainNetbiosName CAMPUS -InstallDns `
    -SafeModeAdministratorPassword $DsrmPassword
# Confirmation et redemarrage geres par Install-ADDSForest. Relire ses avertissements.
