#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -ne 'SRV01') {throw 'SRV01 attendu.'}
Install-WindowsFeature Web-Server,Web-Static-Content,Web-Default-Doc,Web-Mgmt-Tools,Web-Scripting-Tools | Out-Null
Import-Module WebAdministration
New-Item C:\LabWeb\releases -ItemType Directory -Force | Out-Null
# ACL d'un arbre neuf uniquement; n'appliquer cette reinitialisation qu'au repertoire du TP.
$acl=New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach ($r in @(@{Sid='S-1-5-18';Rights='FullControl'},@{Sid='S-1-5-32-544';Rights='FullControl'},@{Sid='S-1-5-32-568';Rights='ReadAndExecute'})) {
    $id=New-Object System.Security.Principal.SecurityIdentifier($r.Sid)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id,$r.Rights,'ContainerInherit,ObjectInherit','None','Allow')))
}
Set-Acl C:\LabWeb $acl
if (-not (Test-Path IIS:\AppPools\Campus)) {New-WebAppPool -Name Campus | Out-Null}
Set-ItemProperty IIS:\AppPools\Campus -Name managedRuntimeVersion -Value ''
if (-not (Test-Path C:\LabWeb\bootstrap\index.html)) {
    New-Item C:\LabWeb\bootstrap -ItemType Directory -Force | Out-Null
    Set-Content C:\LabWeb\bootstrap\index.html '<h1>Campus - bootstrap</h1>' -Encoding UTF8
}
if (-not (Get-Website -Name Campus)) {
    New-Website -Name Campus -Port 8080 -PhysicalPath C:\LabWeb\bootstrap -ApplicationPool Campus | Out-Null
}
Start-Service W3SVC
Start-WebAppPool Campus
Start-Website Campus
if (-not (Get-NetFirewallRule -Name 'PSLAB-WEB' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'PSLAB-WEB' -DisplayName 'PSLAB HTTP ADM01' -Direction Inbound -Protocol TCP `
        -LocalPort 8080 -RemoteAddress '10.77.10.30' -Action Allow | Out-Null
}
