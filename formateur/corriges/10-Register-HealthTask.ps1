#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$ScriptPath=(Join-Path $PSScriptRoot '10-Write-Health.ps1'))
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -ne 'SRV01') {throw 'SRV01 attendu.'}
New-Item C:\LabOps,C:\LabReports -ItemType Directory -Force | Out-Null
# SYSTEM executera ce code: ni les etudiants ordinaires ni IIS ne doivent pouvoir le modifier.
foreach ($folder in @('C:\LabOps','C:\LabReports')) {
    $acl=New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($s in @('S-1-5-18','S-1-5-32-544')) {
        $id=New-Object System.Security.Principal.SecurityIdentifier($s)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    }
    Set-Acl $folder $acl
}
Copy-Item $ScriptPath C:\LabOps\Write-Health.ps1 -Force
$exe="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$action=New-ScheduledTaskAction -Execute $exe -Argument '-NoProfile -NonInteractive -File "C:\LabOps\Write-Health.ps1"'
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'PSLAB-Health' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'PSLAB-Health'
