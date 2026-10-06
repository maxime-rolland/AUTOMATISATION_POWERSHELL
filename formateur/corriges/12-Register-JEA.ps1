#Requires -Version 5.1
#Requires -RunAsAdministrator
<# Extension optionnelle: serveur membre SRV01 uniquement, jamais DC01. #>
[CmdletBinding()]
param([string]$OperatorGroup='CAMPUS\GG_IT')
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -ne 'SRV01' -or (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {throw 'JEA uniquement sur SRV01 membre.'}
$module='C:\Program Files\WindowsPowerShell\Modules\CampusJEA'
New-Item "$module\RoleCapabilities" -ItemType Directory -Force | Out-Null
New-ModuleManifest -Path "$module\CampusJEA.psd1" -ModuleVersion '1.0.0' -Author 'Campus' -Description 'Role JEA du TP'
New-PSRoleCapabilityFile -Path "$module\RoleCapabilities\CampusRead.psrc" `
    -VisibleCmdlets @{Name='Get-Service';Parameters=@{Name='Name';ValidateSet='W3SVC','WinRM'}}
$roles=@{};$roles[$OperatorGroup]=@{RoleCapabilities='CampusRead'}
New-PSSessionConfigurationFile -Path C:\LabOps\CampusRead.pssc -SessionType RestrictedRemoteServer `
    -RunAsVirtualAccount -TranscriptDirectory C:\LabLogs -RoleDefinitions $roles
Test-PSSessionConfigurationFile C:\LabOps\CampusRead.pssc | Out-Null
Register-PSSessionConfiguration -Name CampusRead -Path C:\LabOps\CampusRead.pssc -Force
Write-Warning 'WinRM peut redemarrer: tester depuis une nouvelle session ADM01.'
