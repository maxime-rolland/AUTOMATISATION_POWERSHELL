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

Le JSON contient les noms DNS et l'IP du poste de test. Le vrai NetBIOS est lu sur le DC. Les scripts utilisent des objets ; réserver Format-Table/Format-List à l'affichage final.

Ordre du parcours : vérifier la maquette → inventorier → créer les six comptes/groupes → configurer les deux partages et tester Alice/Chloé → piloter, tester les erreurs et ajouter Gabriel. L'état final comporte sept comptes, quatre groupes et deux partages. La relance finale utilise le CSV à sept ; elle annonce Created=0 et Existing=7.

Gardez une console administrative sur ADMIN pour le déploiement et les variables du TP. Ouvrez une console réseau distincte par identité métier pour les tests ; revenez ensuite à la console administrative.
