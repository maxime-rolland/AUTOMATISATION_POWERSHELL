# Mémo PowerShell — TP deux jours

[Accueil](../README.md)

| Besoin | Commandes |
|---|---|
| Contexte | hostname ; whoami ; $PSVersionTable |
| Découverte | Get-Command ; Get-Help -Examples ; Get-Member |
| Données | Where-Object ; Select-Object ; Group-Object ; Export-Csv |
| Configuration | Get-Content -Raw puis ConvertFrom-Json |
| Import | Import-Csv -Delimiter ';' -Encoding UTF8 |
| Nom/port | Resolve-DnsName ; Test-NetConnection -Port 5985 ou 445 |
| Connexion | New-PSSession -ComputerName FQDN -Authentication Kerberos -Credential $admin |
| Action distante | Invoke-Command -Session $s -ArgumentList ... {param(...) ...} |
| Copie directe | Copy-Item source destination -ToSession $s |
| Fermeture | Remove-PSSession $s dans finally |
| Domaine | Get-ADDomain |
| Comptes/groupes | Get-ADUser ; Get-ADGroup ; Get-ADGroupMember |
| Partage/droits | Get-SmbShare ; Get-SmbShareAccess ; Get-Acl |

Avant de modifier : identifier la cible et l'identité, lire le code et tester WhatIf si prévu. Après : vérifier l'état réel et rejouer.

Dépannage : IP → DNS → port TCP → authentification → service → groupes → ACL. Si le partage autorisé échoue aussi, ne pas interpréter le refus de l'autre comme une réussite de sécurité.

Le JSON contient le nom DNS, le LabId et l'IP du poste de test. Le vrai NetBIOS est lu sur le DC. Les scripts utilisent des objets ; réserver Format-Table/Format-List à l'affichage final.
