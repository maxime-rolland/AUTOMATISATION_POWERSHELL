#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('DC01','SRV01','ADM01')][string]$VMName,
      [Parameter(Mandatory)][ValidateScript({Test-Path $_ -PathType Container})][string]$SourcePath,
      [Parameter(Mandatory)][pscredential]$Credential)
$ErrorActionPreference='Stop'
$s=New-PSSession -VMName $VMName -Credential $Credential
try {
    Invoke-Command -Session $s {New-Item C:\Lab -ItemType Directory -Force | Out-Null}
    Copy-Item -Path (Join-Path $SourcePath '*') -Destination C:\Lab -Recurse -Force -ToSession $s
} finally {Remove-PSSession $s}
