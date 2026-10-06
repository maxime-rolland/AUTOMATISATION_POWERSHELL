#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutPath='C:\LabReports\health.json')
$ErrorActionPreference='Stop'
try {
    $disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $web=Get-Service W3SVC -ErrorAction Stop
    $http=Invoke-WebRequest 'http://localhost:8080/index.html' -UseBasicParsing -TimeoutSec 5
    $healthy=($web.Status -eq 'Running' -and $http.StatusCode -eq 200 -and $disk.FreeSpace -gt 2GB)
    $report=[pscustomobject]@{Machine=$env:COMPUTERNAME;Utc=(Get-Date).ToUniversalTime().ToString('o');
        Service=$web.Status.ToString();Http=$http.StatusCode;FreeGB=[math]::Round($disk.FreeSpace/1GB,2);Healthy=$healthy;Error=''}
} catch {
    $healthy=$false
    $report=[pscustomobject]@{Machine=$env:COMPUTERNAME;Utc=(Get-Date).ToUniversalTime().ToString('o');Service='';Http=$null;FreeGB=$null;Healthy=$false;Error=$_.Exception.Message}
}
New-Item (Split-Path $OutPath) -ItemType Directory -Force | Out-Null
$report | ConvertTo-Json | Set-Content $OutPath -Encoding UTF8
if (-not $healthy) {exit 1}
exit 0
