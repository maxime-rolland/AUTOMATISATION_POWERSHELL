#Requires -Version 5.1
<#
.SYNOPSIS
    Joindre SRV01 ou ADMIN au domaine learn-it.local (prérequis du TP).
.DESCRIPTION
    Exécuté par lab.sh via l'agent QEMU, en SYSTEM. Le redémarrage est demandé par lab.sh.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainPassword,
    [string]$DomainName = 'learn-it.local',
    [string]$UserName = 'Administrator'
)
$ErrorActionPreference = 'Stop'

$system = Get-CimInstance Win32_ComputerSystem
if ($system.PartOfDomain -and $system.Domain -eq $DomainName) {
    "Déjà membre de $DomainName : rien à faire."
    return
}

$secret = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$UserName@$DomainName", $secret)

# Juste après la promotion ou un redémarrage de DC01, le DNS répond avant les services AD :
# réessayer pendant quelques minutes plutôt qu'échouer à la première tentative.
for ($attempt = 1; ; $attempt++) {
    try {
        Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV | Out-Null
        Add-Computer -DomainName $DomainName -Credential $credential -Force -WarningAction SilentlyContinue
        break
    } catch {
        if ($attempt -ge 20) {throw}
        "Tentative $attempt : $($_.Exception.Message) ; nouvel essai dans 30 s."
        Start-Sleep -Seconds 30
    }
}
"Jonction de $env:COMPUTERNAME à $DomainName effectuée ; redémarrage nécessaire."
