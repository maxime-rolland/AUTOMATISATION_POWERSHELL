# Sources et choix techniques

Références officielles vérifiées pour les points structurants le 6 octobre 2026. Les liens de cmdlets complémentaires servent à la répétition locale.

## Dépôt examiné

https://github.com/maxime-rolland/AUTOMATISATION_POWERSHELL/tree/main

Arbre main : README de 2 octets et LICENSE MIT ; aucun cours existant à reprendre.

## Core et Desktop Experience

https://learn.microsoft.com/en-us/windows-server/get-started/install-options-server-core-desktop-experience

Choix installation, administration à distance, absence de conversion ultérieure.

## SConfig

https://learn.microsoft.com/fr-fr/windows-server/administration/server-core/server-core-sconfig

Configuration initiale de Server Core.

## ISO évaluation Windows Server 2025

https://www.microsoft.com/fr-fr/evalcenter/evaluate-windows-server-2025

Téléchargement officiel, édition et conditions de l’évaluation.

## Installation AD DS

https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-

Rôle, Test-ADDSForestInstallation, DSRM et promotion.

## Sécurité WinRM

https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/winrm-security

Kerberos, chiffrement de messages, TrustedHosts et ports.

## Second saut

https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ps-remoting-second-hop

Délimitation des accès distants ; pas de CredSSP dans le TP.

## 5.1 et 7

https://learn.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7

Moteurs coexistants et endpoints de remoting.

## New-VM

https://learn.microsoft.com/en-us/powershell/module/hyper-v/new-vm?view=windowsserver2025-ps

Création VM Hyper-V ; consulter la syntaxe locale.

## New-SmbShare

https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare?view=windowsserver2025-ps

Partage, permissions, chiffrement et énumération.

## JEA

https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/jea/overview

Extension moindre privilège et restrictions de commandes.

## ExecutionPolicy

https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1

Portées, signatures et limites de la politique.

## New-ScheduledTaskTrigger

https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=windowsserver2025-ps

Déclencheur et répétition de tâche.

## WebAdministration

https://learn.microsoft.com/en-us/powershell/module/webadministration/?view=windowsserver2025-ps

Gestion du site IIS et de son physicalPath.

## PowerShell Direct

https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct

Sessions hôte→VM sans réseau Windows.
