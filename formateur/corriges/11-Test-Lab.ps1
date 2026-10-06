#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][pscredential]$Credential,[string]$OutPath='C:\Lab\preuves\recette.json')
$ErrorActionPreference='Stop'
$results=New-Object 'System.Collections.Generic.List[object]'
function Add-Result([string]$Name,[bool]$Passed,[string]$Detail) {
    $results.Add([pscustomobject]@{Test=$Name;Passed=$Passed;Detail=$Detail})
}
try {$r=Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV;Add-Result 'DNS-SRV' ([bool]$r) 'Decouverte AD'} catch {Add-Result 'DNS-SRV' $false $_.Exception.Message}
foreach ($name in @('dc01.campus.test','srv01.campus.test','adm01.campus.test')) {
    $s=$null
    try {
        $s=New-PSSession -ComputerName $name -Authentication Kerberos -ConfigurationName Microsoft.PowerShell -Credential $Credential
        $r=Invoke-Command -Session $s {
            [pscustomobject]@{Domain=(Get-CimInstance Win32_ComputerSystem).Domain;
                Type=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType;
                Firewall=(@(Get-NetFirewallProfile | Where-Object {-not $_.Enabled}).Count -eq 0)}
        }
        Add-Result "$name/Kerberos" $true 'Session etablie'
        Add-Result "$name/Core" ($r.Type -eq 'Server Core') $r.Type
        Add-Result "$name/Domaine" ($r.Domain -eq 'campus.test') $r.Domain
        Add-Result "$name/Pare-feu" $r.Firewall 'Tous profils actifs'
        if ($name -like 'dc01*') {
            $a=Invoke-Command -Session $s {
                Import-Module ActiveDirectory
                [pscustomobject]@{Users=@(Get-ADUser -Filter * -SearchBase 'OU=Utilisateurs,OU=PSLAB,DC=campus,DC=test').Count;
                    Groups=@(Get-ADGroup -Filter * -SearchBase 'OU=Groupes,OU=PSLAB,DC=campus,DC=test').Count}
            }
            Add-Result 'AD-6-utilisateurs' ($a.Users -eq 6) "Nombre=$($a.Users)"
            Add-Result 'AD-6-groupes' ($a.Groups -eq 6) "Nombre=$($a.Groups)"
        }
        if ($name -like 'srv01*') {
            $a=Invoke-Command -Session $s {
                $shares=@(Get-SmbShare | Where-Object Name -in @('IT$','RH$','Direction$'))
                $task=Get-ScheduledTask -TaskName PSLAB-Health -ErrorAction Stop
                $info=Get-ScheduledTaskInfo -TaskName PSLAB-Health
                $report=Get-Content C:\LabReports\health.json -Raw | ConvertFrom-Json
                $age=((Get-Date).ToUniversalTime()-([datetime]$report.Utc).ToUniversalTime()).TotalMinutes
                [pscustomobject]@{Shares=$shares.Count;Encrypted=(@($shares | Where-Object {-not $_.EncryptData}).Count -eq 0);
                    TaskState=$task.State.ToString();TaskResult=$info.LastTaskResult;Healthy=$report.Healthy;
                    Fresh=($age -ge 0 -and $age -lt 10)}
            }
            Add-Result 'SMB-3-partages' ($a.Shares -eq 3) "Nombre=$($a.Shares)"
            Add-Result 'SMB-chiffrement' $a.Encrypted 'EncryptData'
            Add-Result 'Tache-et-sante' ($a.TaskResult -eq 0 -and $a.Healthy -and $a.Fresh) "Resultat=$($a.TaskResult);etat=$($a.TaskState)"
        }
    } catch {Add-Result "$name/Erreur" $false $_.Exception.Message} finally {if ($s) {Remove-PSSession $s}}
}
try {$h=Invoke-WebRequest 'http://srv01.campus.test:8080/index.html' -UseBasicParsing -TimeoutSec 5;Add-Result 'HTTP-depuis-ADM01' ($h.StatusCode -eq 200 -and $h.Content.Contains('Campus - v')) '200 et marqueur version'} catch {Add-Result 'HTTP-depuis-ADM01' $false $_.Exception.Message}
New-Item (Split-Path $OutPath) -ItemType Directory -Force | Out-Null
$results | ConvertTo-Json -Depth 4 | Set-Content $OutPath -Encoding UTF8
$results | Format-Table -AutoSize
if (@($results | Where-Object {-not $_.Passed}).Count -gt 0) {exit 1}
exit 0
