#Requires -Version 5.1
<#
.SYNOPSIS
    Attendre que DC01 assure réellement le domaine : AD DS, SYSVOL et localisation du DC.
.DESCRIPTION
    Exécuté par lab.sh via l'agent QEMU, en SYSTEM, sur DC01.
    Au premier démarrage qui suit la promotion, DFSR interroge AD avant qu'il soit prêt
    (événement 1202) et ne réessaie qu'une heure plus tard : SYSVOL reste non partagé et le DC
    ne s'annonce pas (nltest /dsgetdc : ERROR_NO_SUCH_DOMAIN). Le script relance alors DFSR.
#>
[CmdletBinding()]
param([int]$TimeoutSeconds = 900)
$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$netlogon = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'

function Wait-Until {
    param([scriptblock]$Condition, [string]$What)
    while (-not (& $Condition)) {
        if ((Get-Date) -gt $deadline) {throw "Délai dépassé : $What"}
        Start-Sleep -Seconds 5
    }
}

Wait-Until {(Get-Service NTDS).Status -eq 'Running'} 'service NTDS'

# Laisser une minute à DFSR, puis le relancer une fois si SYSVOL n'est toujours pas prêt.
$grace = (Get-Date).AddSeconds(60)
Wait-Until {(Get-ItemProperty $netlogon).SysvolReady -eq 1 -or (Get-Date) -gt $grace} 'SYSVOL'
if ((Get-ItemProperty $netlogon).SysvolReady -ne 1) {
    'SYSVOL non initialisé : relance du service DFSR.'
    Restart-Service DFSR
    Wait-Until {(Get-ItemProperty $netlogon).SysvolReady -eq 1} 'SYSVOL après relance de DFSR'
}

Import-Module ActiveDirectory -WarningAction SilentlyContinue
Wait-Until {
    try {[bool](Get-ADDomain -Server $env:COMPUTERNAME)} catch {$false}
} 'services Web AD'
$domain = Get-ADDomain -Server $env:COMPUTERNAME
"Domaine $($domain.DNSRoot) ($($domain.NetBIOSName)) prêt, SYSVOL partagé."
