#Requires -Version 5.1
<#
.SYNOPSIS
    Créer la forêt learn-it.local sur DC01 (prérequis du TP, pas un exercice).
.DESCRIPTION
    Exécuté par lab.sh via l'agent QEMU, en SYSTEM. Le redémarrage est demandé par lab.sh.
    Le compte Administrator local devient l'administrateur du domaine, avec le même secret.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SafeModePassword,
    [string]$DomainName = 'learn-it.local',
    [string]$NetBIOSName = 'LEARN-IT'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Un DC démarre avant ses propres services AD : NLA classe alors le LAN en profil Public.
# AlwaysExpectDomainController fait patienter NLA jusqu'à ce que le domaine réponde.
# New-ItemProperty : ne jamais recréer la clé Parameters, elle contient ServiceDll et ses ACL.
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters' `
    -Name AlwaysExpectDomainController -PropertyType DWord -Value 1 -Force | Out-Null

if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
    "Déjà contrôleur de domaine : rien à faire."
    return
}

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools |
    Select-Object Success, RestartNeeded, ExitCode

Import-Module ADDSDeployment
$secret = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
$result = Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetBIOSName -InstallDns `
    -SafeModeAdministratorPassword $secret -NoRebootOnCompletion -Force -WarningAction SilentlyContinue
"Promotion de $env:COMPUTERNAME : $($result.Status). $($result.Message)"
