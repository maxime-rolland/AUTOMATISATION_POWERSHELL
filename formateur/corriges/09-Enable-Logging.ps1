#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
foreach ($feature in @('ScriptBlockLogging','ModuleLogging','Transcription')) {
    New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\$feature" -Force | Out-Null
}
$root='HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
New-ItemProperty "$root\ScriptBlockLogging" -Name EnableScriptBlockLogging -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty "$root\ModuleLogging" -Name EnableModuleLogging -Value 1 -PropertyType DWord -Force | Out-Null
New-Item "$root\ModuleLogging\ModuleNames" -Force | Out-Null
New-ItemProperty "$root\ModuleLogging\ModuleNames" -Name '*' -Value '*' -PropertyType String -Force | Out-Null
New-Item C:\LabLogs -ItemType Directory -Force | Out-Null
$acl=New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach ($s in @('S-1-5-18','S-1-5-32-544')) {
    $id=New-Object System.Security.Principal.SecurityIdentifier($s)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
}
Set-Acl C:\LabLogs $acl
New-ItemProperty "$root\Transcription" -Name EnableTranscripting -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty "$root\Transcription" -Name EnableInvocationHeader -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty "$root\Transcription" -Name OutputDirectory -Value 'C:\LabLogs' -PropertyType String -Force | Out-Null
Write-Output 'Ouvrir une nouvelle session Windows PowerShell 5.1. Journaux reserves aux administrateurs/SYSTEM.'
