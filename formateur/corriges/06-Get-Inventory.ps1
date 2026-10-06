#Requires -Version 5.1
[CmdletBinding()]
param([string[]]$ComputerName=@('dc01.campus.test','srv01.campus.test','adm01.campus.test'),
      [Parameter(Mandatory)][pscredential]$Credential,[string]$OutPath='C:\Lab\preuves\inventaire.csv')
$ErrorActionPreference='Stop'
$result=foreach ($name in $ComputerName) {
    $s=$null
    try {
        $s=New-PSSession -ComputerName $name -Authentication Kerberos -ConfigurationName Microsoft.PowerShell -Credential $Credential
        Invoke-Command -Session $s {
            $os=Get-CimInstance Win32_OperatingSystem
            $cs=Get-CimInstance Win32_ComputerSystem
            $disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            [pscustomobject]@{Machine=$env:COMPUTERNAME;OS=$os.Caption;Domain=$cs.Domain;
                MemoryGB=[math]::Round($cs.TotalPhysicalMemory/1GB,1);FreeGB=[math]::Round($disk.FreeSpace/1GB,1);
                LastBoot=$os.LastBootUpTime;PSVersion=$PSVersionTable.PSVersion.ToString();Etat='OK';Erreur=''}
        }
    } catch {
        [pscustomobject]@{Machine=$name;OS='';Domain='';MemoryGB=$null;FreeGB=$null;LastBoot=$null;PSVersion='';Etat='ECHEC';Erreur=$_.Exception.Message}
    } finally {if ($s) {Remove-PSSession $s}}
}
New-Item (Split-Path $OutPath) -ItemType Directory -Force | Out-Null
$result | Select-Object Machine,OS,Domain,MemoryGB,FreeGB,LastBoot,PSVersion,Etat,Erreur | Export-Csv $OutPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
$result
