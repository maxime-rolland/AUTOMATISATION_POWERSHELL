# Automatisation Déploiement / PowerShell
## Support de TP étudiant — Bachelor Réseau & Cybersécurité, Bac +3

**Durée : 3 jours / 21 heures de présence, dont 19 heures de travail et 2 heures de pauses.**
Version 1.1 — 6 octobre 2026 — Maxime ROLLAND — Pulse myIT.

Ce support accompagne un laboratoire isolé. Toutes les commandes de rôle Windows et tous les corrigés utilisent **Windows PowerShell 5.1, `powershell.exe`**. L'option **Server Core** désigne l'installation de Windows sans bureau ; elle ne désigne pas PowerShell 7. Le poste physique peut servir d'éditeur et de console d'hyperviseur. Les trois VM restent en Core.

## 1. Mission et compétences attendues

L'entreprise fictive Campus ouvre un site avec trois services : IT, RH et Direction. Elle vous confie le déploiement reproductible de son infrastructure et la livraison de son intranet. Vous devez produire des scripts explicables, des preuves et une procédure d'exploitation. Une commande qui fonctionne une fois ne suffit pas : il faut maîtriser ses préconditions, son identité d'exécution, son effet et son comportement en cas d'erreur.

À l'issue du parcours, vous saurez découvrir une commande, manipuler des objets, filtrer/exporter des données, écrire une fonction paramétrée, distinguer erreurs terminantes et non terminantes, administrer Core, utiliser WinRM avec Kerberos, automatiser AD et AGDLP, construire des ACL SMB/NTFS, déployer un artefact avec vérification et rollback, planifier un contrôle et investiguer une panne.

Prérequis : adressage IPv4, DNS, domaine Windows, groupe/utilisateur, bases NTFS, virtualisation et commandes terminal simples. Aucun niveau de développeur n'est requis. Travail en binôme : un opérateur, un vérificateur ; inverser les rôles après chaque TP. Les binômes rapides traitent les extensions, sans supprimer les vérifications du parcours principal.

### Livrables à remettre

- Scripts `.ps1` et éventuel module `.psm1`, avec paramètres et commentaires utiles.
- Configuration JSON, CSV d'entrée, manifeste SHA256 des versions et inventaire exporté.
- Compte rendu suivant `commun/preuves/MODELE-COMPTE-RENDU.md` ; pas seulement des captures.
- Preuves des accès autorisés et refusés, du deuxième passage, du refus du CSV invalide et du rollback.
- Recette finale et procédure de reprise depuis les checkpoints du TP.

## 2. Maquette : trois VM Windows Server Core

| Machine | IPv4 /24 | Rôle | RAM fixe | vCPU | Disque dynamique |
|---|---|---|---|---|---|
| DC01 | 10.77.10.10 | AD DS + DNS | 4 Go | 2 | 60 Go |
| SRV01 | 10.77.10.20 | Membre, fichiers SMB, intranet IIS | 4 Go | 2 | 60 Go |
| ADM01 | 10.77.10.30 | Membre, administration PowerShell et tests clients | 2 Go | 2 | 60 Go |

Réseau : `10.77.10.0/24` ; DNS des trois VM : `10.77.10.10` ; **aucune passerelle dans le parcours hors ligne**. Domaine : `campus.test`, NetBIOS `CAMPUS`. Aucun DHCP ni routeur nécessaire. Chaque binôme possède son réseau virtuel isolé ; les mêmes IP peuvent y être réutilisées. Sur un hyperviseur collectif, il faut un bridge/VLAN isolé par binôme et des noms de VM préfixés côté hyperviseur ; les noms Windows peuvent rester identiques.

Le [schéma Mermaid de la maquette](../Maquette.md) montre les flux principaux. ADM01 administre DC01 et SRV01 ; les serveurs membres utilisent DC01 pour DNS et les services de domaine. SRV01 fournit SMB et HTTP uniquement à ADM01. Les fonctions fichiers et web sont regroupées pour limiter la RAM et le temps d'installation. En entreprise, leur séparation, la redondance AD/DNS, le stockage de sauvegarde externe, TLS et le cloisonnement réseau seraient à étudier.

### Matériel et logiciel

Hôte recommandé : 16 Go de RAM minimum pour ce profil, 24–32 Go confortables, SSD avec environ 200 Go libres au départ, virtualisation matérielle activée. Les disques dynamiques peuvent atteindre 180 Go, auxquels s'ajoutent ISO et checkpoints ; provisionner davantage si tous grossissent. Ne pas saturer l'hôte en surallouant la RAM. La virtualisation imbriquée n'est pas nécessaire.

Référence : ISO x64 Windows Server 2025 Standard Evaluation, option **sans Desktop Experience**. Windows Server 2022 Standard Core est une alternative cohérente : ne pas mélanger les versions pour la première séance. Les ISO, licences et images Windows ne sont pas incluses. Le formateur fournit l'ISO officielle, vérifie les conditions d'évaluation/activation et prépare les VM avant le cours. Les scripts ne sont pas des disques prêts à démarrer : ils créent les VM et configurent Windows après son installation.

### Hyperviseurs

| Hyperviseur | Réseau du TP | Disques et installation | Acheminement des fichiers |
|---|---|---|---|
| Hyper-V | switch **Private** PSLAB | génération 2, SCSI, Secure Boot Microsoft Windows | PowerShell Direct depuis l'hôte Windows |
| Proxmox | bridge sans port physique, sans passerelle | OVMF + disque EFI ; SATA et E1000 pour éviter les pilotes additionnels | ISO de données montée après installation |
| VMware Workstation | LAN Segment dédié | firmware UEFI, ISO montée | ISO de données |
| VirtualBox | Internal Network dédié | disque SATA ; vérifier le support de l'OS sur la version locale | ISO de données |

Le chemin Hyper-V est fourni par script. Pour les autres hyperviseurs, créer manuellement trois VM avec le tableau ci-dessus. Ne pas connecter le LAN du TP au réseau physique. L'accès Internet temporaire de préparation, si nécessaire pour activation et mises à jour, est géré par le formateur ; retirer cette connectivité avant les TP. Pas de NAT à dépanner pendant les exercices.

## 3. Préparation et règles de travail

### Parcours d'installation initiale

1. Sur l'hôte Hyper-V, ouvrir Windows PowerShell en administrateur, extraire le pack et inspecter `commun/config/lab.json`.
2. Prévisualiser la création, puis créer les VM :

```powershell
Set-Location C:\Cours\AUTOMATISATION_POWERSHELL
.\commun\preparation\New-LabVM.ps1 -IsoPath C:\ISO\WindowsServer.iso -WhatIf
.\commun\preparation\New-LabVM.ps1 -IsoPath C:\ISO\WindowsServer.iso
Start-VM DC01,SRV01,ADM01
```

3. Dans la console de chaque VM, démarrer sur le DVD (appuyer sur une touche), sélectionner **Windows Server Standard Evaluation**, sans Desktop Experience, et installer sur le disque vide. Définir un mot de passe administrateur fort, propre à la séance, communiqué hors dépôt. Dans SConfig, quitter vers PowerShell. Vérifier `$PSVersionTable`.
4. Copier le dossier du pack dans `C:\Lab` sur chacune des VM. Sous Hyper-V, les VM peuvent avoir des comptes locaux différents : saisir la bonne identité par VM.

```powershell
# Sur l'hôte Hyper-V, une VM à la fois ; Windows doit être démarré.
$credLocal = Get-Credential -UserName 'Administrator' -Message 'Compte local de la VM'
.\commun\preparation\Copy-LabToVM.ps1 -VMName DC01 `
  -SourcePath C:\Cours\AUTOMATISATION_POWERSHELL -Credential $credLocal
# Refaire pour SRV01 et ADM01 avec leur compte/mot de passe local.
```

Le nom du compte intégré dépend de la langue : utiliser `Administrateur` si l'ISO est française. PowerShell Direct passe par l'hyperviseur, sans dépendre de l'IP, de WinRM ou du domaine. Sur les autres hyperviseurs, le formateur monte l'ISO de données puis copie son contenu en console, par exemple `Copy-Item E:\* C:\Lab -Recurse -Force`, après avoir vérifié la lettre avec `Get-Volume`. L'ISO de données ne contient que les fichiers du TP, pas Windows.

5. Pour une VM vierge avec une seule NIC active, lancer en console locale :

```powershell
Set-Location C:\Lab
# Remplacer le nom par celui de la VM courante.
.\commun\preparation\01-Initialize-Core.ps1 -Name DC01 -WhatIf
.\commun\preparation\01-Initialize-Core.ps1 -Name DC01
Restart-Computer
```

6. Refaire avec SRV01 et ADM01. Vérifier les IP en console. Le script refuse une adresse déjà configurée différente ; faire analyser cette situation au formateur, sans supprimer arbitrairement les interfaces.
7. Arrêter proprement les trois VM ; prendre le checkpoint **S0-Core** sur chacune ; redémarrer. Les checkpoints sont des points de reprise pédagogiques, pas une sauvegarde AD de production.

### Écriture, encodage et exécution

Écrire sur le poste physique dans un éditeur, puis copier les fichiers sur ADM01 ; ou utiliser un éditeur texte disponible en console. Dans `powershell.exe` 5.1, les scripts français doivent être enregistrés en **UTF-8 avec BOM**. Les scripts fournis le sont. Le CSV utilise `;` et doit être lu avec `-Delimiter ';' -Encoding UTF8`.

```powershell
$PSVersionTable
Get-ExecutionPolicy -List
# Uniquement si les scripts locaux de confiance sont bloqués et selon la règle de la salle :
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
# Après lecture et vérification du pack téléchargé, retirer son marquage Internet si nécessaire :
Get-ChildItem C:\Lab -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

Une politique de groupe peut primer sur Scope Process. L'ExecutionPolicy limite certaines erreurs involontaires ; elle n'est pas une frontière de sécurité. Ne pas remplacer ces contrôles par `Bypass` global. Pour exporter des preuves, choisir un chemin de fichier ; ne pas mettre un secret dans une capture, un transcript, une ligne de commande ou Git.

### Contrat de sécurité du TP

Conserver Windows Firewall et Defender actifs. Ne pas utiliser TrustedHosts `*`, Basic, `AllowUnencrypted`, CredSSP ou une désactivation globale du pare-feu. La phase de bootstrap se fait en console/PowerShell Direct. Après jointure, WinRM utilise les FQDN avec `-Authentication Kerberos`. Aucun nom d'utilisateur/mot de passe en clair dans le code. Les privilèges de domaine servent au montage initial uniquement ; les tests d'accès se font avec des comptes métiers ordinaires.

## 4. Programme des trois jours

Horaires de présence 09:00–12:30 et 13:30–17:00 ; déjeuner exclu. Chaque journée totalise 7 h, dont 40 min de pauses. Les durées sont des enveloppes : une équipe en retard utilise le checkpoint de secours pour atteindre le TP suivant.

| Jour | Heure | Séquence | Durée |
|---|---|---|---|
| J1 | 09:00–09:30 | Mission, diagnostic et règles | 30 min |
| J1 | 09:30–10:30 | TP1 — objets et découverte | 60 min |
| J1 | 10:30–10:50 | Pause | 20 min |
| J1 | 10:50–12:30 | TP2 — réseau et Core | 100 min |
| J1 | 13:30–14:00 | Erreurs, fonctions, scripts | 30 min |
| J1 | 14:00–15:20 | TP3 — AD/DNS et jointure | 80 min |
| J1 | 15:20–15:40 | Pause | 20 min |
| J1 | 15:40–16:40 | TP4 — remoting et inventaire | 60 min |
| J1 | 16:40–17:00 | Preuves et checkpoint S1 | 20 min |
| J2 | 09:00–09:20 | Reprise, données et idempotence | 20 min |
| J2 | 09:20–10:30 | TP5A — validation CSV | 70 min |
| J2 | 10:30–10:50 | Pause | 20 min |
| J2 | 10:50–12:30 | TP5B — provisioning AD | 100 min |
| J2 | 13:30–13:50 | AGDLP et permissions effectives | 20 min |
| J2 | 13:50–15:20 | TP6 — SMB/NTFS | 90 min |
| J2 | 15:20–15:40 | Pause | 20 min |
| J2 | 15:40–16:40 | Tests négatifs et second passage | 60 min |
| J2 | 16:40–17:00 | Preuves et checkpoint S2 | 20 min |
| J3 | 09:00–09:20 | Artefacts, confiance et rollback | 20 min |
| J3 | 09:20–10:30 | TP7A — IIS et publication v1 | 70 min |
| J3 | 10:30–10:50 | Pause | 20 min |
| J3 | 10:50–12:30 | TP7B — v2, échecs et rollback | 100 min |
| J3 | 13:30–14:30 | TP8 — santé et tâche planifiée | 60 min |
| J3 | 14:30–15:20 | TP9 — logs et incident | 50 min |
| J3 | 15:20–15:40 | Pause | 20 min |
| J3 | 15:40–16:40 | TP10 — recette et restitution | 60 min |
| J3 | 16:40–17:00 | Soutenance et bilan individuel | 20 min |

Le parcours suppose Windows déjà installé et copié avant J1. L'installation complète des OS est un travail de préparation de 60–120 min, dépendant du matériel, **en dehors des 21 h**. Si elle doit se faire pendant le cours, le formateur utilise la variante allégée de son guide.

## 5. Repères PowerShell : comprendre avant d'automatiser

### Commande, paramètre et objet

Un cmdlet porte généralement un nom Verbe-Nom. `Get-Process` renvoie des objets possédant des propriétés (`Name`, `Id`, `CPU`) et des méthodes. L'affichage est une représentation, pas le contenu réel. Le pipeline transmet les objets entre commandes ; la sortie de `Format-Table` est destinée à l'écran, pas à un CSV.

```powershell
Get-Command *Service*
Get-Help Get-Service -Examples
Get-Service | Get-Member
Get-Service | Where-Object Status -eq Running |
  Select-Object Name,Status | Sort-Object Name
Get-Service | Select-Object Name,Status |
  Export-Csv C:\Lab\preuves\services.csv -NoTypeInformation -Delimiter ';' -Encoding UTF8
```

Lire l'aide locale ; `Update-Help` peut nécessiter Internet et n'est pas une dépendance du TP. La documentation en ligne officielle peut être consultée depuis le poste physique. Préférer les noms complets aux alias dans un script partagé.

### Variables, collections et portée

Une chaîne entre apostrophes est littérale ; entre guillemets, les variables sont développées. `@(...)` force une collection ; `@{...}` est une table de hachage. `$null` signifie l'absence de valeur, pas une chaîne vide. Dans une chaîne, utiliser `$($objet.Propriete)` pour interpoler une propriété.

```powershell
$machines = @('DC01','SRV01','ADM01')
foreach ($m in $machines) {
  [pscustomobject]@{Machine=$m;ObserveLe=(Get-Date).ToString('o')}
}
$config = Get-Content C:\Lab\commun\config\lab.json -Raw | ConvertFrom-Json
$config.VMs | Select-Object Name,IPAddress
```

### Fonction, paramètres et splatting

Une fonction doit renvoyer des objets réutilisables. `Write-Verbose` explique l'activité avec `-Verbose` ; `Write-Warning` signale une réserve ; `Write-Error` signale un problème. Ne pas utiliser `Write-Host` comme seul résultat métier.

```powershell
function Get-LabDisk {
  [CmdletBinding()]
  param([ValidateSet('C:')][string]$Drive='C:')
  $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
  [pscustomobject]@{Drive=$Drive;FreeGB=[math]::Round($d.FreeSpace/1GB,2)}
}
Get-LabDisk | ConvertTo-Json
$p = @{Path='C:\Lab\preuves';ItemType='Directory';Force=$true}
New-Item @p
```

`1GB` est une constante binaire, 1 073 741 824 octets. Le splatting transmet les paramètres d'une table sans construire une commande textuelle. Éviter `Invoke-Expression` pour exécuter des données.

### Erreurs, ressources et dry run

`try/catch` attrape les erreurs terminantes. Beaucoup de cmdlets émettent par défaut une erreur non terminante : employer `-ErrorAction Stop` ou `$ErrorActionPreference='Stop'` quand l'étape doit bloquer le traitement. `finally` ferme une session même après une erreur.

```powershell
try {
  Get-Item C:\fichier-inexistant.txt -ErrorAction Stop
} catch {
  [pscustomobject]@{Etat='ECHEC';Message=$_.Exception.Message}
} finally {
  Write-Verbose 'Fin du traitement'
}
```

`-WhatIf` n'est utile que si le script implémente `SupportsShouldProcess` et entoure **toutes ses mutations** de `$PSCmdlet.ShouldProcess(...)`. Le dry run ne garantit ni les droits réels, ni la réussite au moment de l'exécution. Dans ce cours, il ne crée ni dossiers, ni comptes, ni sessions de publication.

### Idempotence, convergence et transaction

Idempotence : répéter le même traitement n'ajoute pas de doublons ni d'effets métier supplémentaires. Convergence : les paramètres reviennent à l'état désiré, même après une dérive. Transaction : l'ensemble réussit ou est annulé. Un script « créer si absent » peut être idempotent sans corriger une mauvaise ACL, et sans être transactionnel. L'import AD de ce TP est additif et peut laisser un résultat partiel après une panne ; le déploiement web remet le chemin précédent si sa validation échoue. Ne pas promettre une transaction globale pour tout le laboratoire.

## 6. TP1 — Découverte, pipeline et données

**Machine : ADM01 en console. Identité : administrateur local. Durée : 60 min.**

### Objectif et notions

Produire un inventaire local structuré en comprenant ce qui circule dans le pipeline. Distinguer une sortie métier d'une mise en forme. Savoir découvrir un paramètre sans recopier un script trouvé en ligne.

### À réaliser

1. Relever version, édition et identité : `$PSVersionTable`, `whoami`, `hostname`.
2. Trouver les commandes relatives aux services ; lire les exemples de `Get-Service` ; examiner les membres d'un résultat.
3. Lister les services en cours d'exécution, garder Name et Status, trier Name ; exporter dans `C:\Lab\preuves\tp1-services.csv`.
4. Produire un objet avec nom machine, mémoire totale en Go et espace libre sur C:. Utiliser `Get-CimInstance Win32_ComputerSystem` et `Win32_LogicalDisk`.
5. Lire `commun/config/lab.json` et afficher uniquement les noms et adresses des trois machines.
6. Écrire `Get-LabDisk` à partir des repères ; vérifier son résultat JSON.
7. Comparer `Get-Service | Format-Table | Export-Csv` à `Get-Service | Select-Object Name,Status | Export-Csv`. Ouvrir les deux CSV et expliquer pourquoi le premier est inutilisable.

### Résultats et preuves

Le CSV de services contient des noms et statuts, sans objets de mise en forme. Le JSON est lisible avec `ConvertFrom-Json`. Conserver le script et un extrait de 5 lignes du CSV. Aucun nombre de services n'est imposé : il dépend de la version/du build Windows.

### Questions et vérifications

Qu'apporte `Get-Member` ? Pourquoi filtrer avant de formater ? Quelle différence entre `$m`, `$config.VMs` et la chaîne '$m' ? Pourquoi les propriétés d'un objet sont-elles préférables à une découpe du texte de `systeminfo` ? Le binôme doit pouvoir réécrire son pipeline sans ses notes.

En cas de blocage : vérifier le dossier de sortie et le moteur utilisé. `Get-CimInstance` interroge localement WMI/CIM ici ; il n'exige pas de domaine.

## 7. TP2 — Administrer Windows Server Core et son réseau

**Machines : les trois VM, en console locale. Identité : administrateur local. Durée : 100 min.**

### Pourquoi Core ?

Core limite les composants installés et encourage une administration explicite à distance. Il ne remplace ni les mises à jour, ni le contrôle d'accès, ni les sauvegardes. L'option est choisie pendant l'installation : on ne transforme pas ce Core en Desktop Experience par une simple installation de fonctionnalité dans les versions du TP.

### À réaliser

1. Lire `01-Initialize-Core.ps1` et identifier les commandes qui changent le réseau, le nom et le pare-feu. Expliquer la garde « une seule carte active » et le refus d'une autre IPv4.
2. Si les VM ont déjà été préparées, comparer leur état au JSON ; sinon appliquer la procédure initiale. Ne pas relancer une initialisation réseau depuis une session dépendant de ce réseau.
3. Sur chaque VM :

```powershell
Get-NetAdapter
Get-NetIPConfiguration
Get-DnsClientServerAddress -AddressFamily IPv4
Get-NetConnectionProfile
Get-NetFirewallProfile | Select-Object Name,Enabled
Get-Service WinRM
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
  Select-Object ProductName,InstallationType
```

4. Depuis ADM01, tester SRV01 par IP. `Test-Connection 10.77.10.20 -Count 2` vérifie ICMP ; `Test-NetConnection 10.77.10.20 -Port 5985` vérifie TCP. Un ping réussi ne prouve pas qu'un service fonctionne.
5. Relever les règles WinRM et leur portée :

```powershell
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' |
  Get-NetFirewallAddressFilter
```

6. Créer un script de contrôle local qui retourne un objet comprenant IPv4, DNS, nom et état du pare-feu. Comparer l'état réel au `lab.json`. Il doit **contrôler**, sans reconfigurer.

### Résultats et portes de sortie

Les trois VM annoncent Server Core et les bonnes adresses. Le DNS pointe vers DC01, mais la résolution du domaine n'est pas encore disponible avant le TP3. L'absence d'accès Internet est attendue. Les règles WinRM entrantes sont limitées à ADM01. À ce stade, aucune administration WinRM entre comptes de domaine n'est attendue.

Preuves : état réseau des trois VM et règle WinRM. Questions : pourquoi ne pas utiliser le DNS de l'opérateur sur les membres ? Pourquoi ne pas désactiver le pare-feu pour diagnostiquer ? Pourquoi un changement d'IP à distance peut-il couper la session ?

## 8. TP3 — Construire AD DS, DNS et joindre les membres

**DC01 : administrateur local puis administrateur CAMPUS. Membres : console admin locale. Durée : 80 min.**

### Principes

Un domaine AD publie des enregistrements DNS SRV : les clients y trouvent LDAP et Kerberos. Un membre doit interroger le DNS du domaine ; un DNS public ne connaît pas ces enregistrements. Le mot de passe DSRM sert à la restauration du contrôleur de domaine, et n'est pas un mot de passe d'utilisateur métier. La promotion entraîne un redémarrage : traiter cette étape comme une rupture de session.

### Sur DC01, construire la forêt

```powershell
# Console locale DC01, Windows PowerShell 5.1 administrateur.
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
$dsrm = Read-Host 'Mot de passe DSRM de la séance' -AsSecureString
Test-ADDSForestInstallation -DomainName campus.test -DomainNetbiosName CAMPUS `
  -InstallDns -SafeModeAdministratorPassword $dsrm
Install-ADDSForest -DomainName campus.test -DomainNetbiosName CAMPUS `
  -InstallDns -SafeModeAdministratorPassword $dsrm
```

Vérifier les préconditions avant de confirmer. Le message de délégation DNS peut être normal pour ce domaine de laboratoire sans zone parente : l'expliquer, pas ignorer tous les avertissements. Après redémarrage, ouvrir une session avec le compte administrateur du domaine (nom selon langue) ; vérifier `whoami` et `Get-ADDomain`.

```powershell
Import-Module ActiveDirectory
Get-ADDomain | Select-Object DNSRoot,NetBIOSName,DomainMode
Get-Service NTDS,DNS,Netlogon
Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV
Resolve-DnsName dc01.campus.test
```

### Sur ADM01 puis SRV01, joindre le domaine

```powershell
# Console locale de chaque membre.
Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV
$joinCred = Get-Credential -Message 'Compte autorisé à joindre CAMPUS'
Add-Computer -DomainName campus.test -Credential $joinCred -PassThru
Restart-Computer
```

Après redémarrage, ouvrir une session d'administration du domaine sur ADM01. Dans ce laboratoire jetable, le compte privilégié de montage est accepté ; ne pas en faire un compte quotidien en production. Vérifier `Test-ComputerSecureChannel -Verbose` et `(Get-CimInstance Win32_ComputerSystem).Domain` sur chaque membre. Tester les FQDN depuis ADM01. Si le profil réseau reste Private après jointure, vérifier DNS et disponibilité de DC01 puis redémarrer le membre ; ne pas tenter de forcer DomainAuthenticated.

### Résultats, preuves et dépannage

DC01 est le seul contrôleur ; les deux membres sont dans campus.test ; la découverte DNS SRV réussit. Relever les enregistrements SRV et les canaux sécurisés. Une erreur de jointure doit d'abord faire contrôler IP, DNS, nom du domaine, date/heure et disponibilité du DC. Ne pas installer une seconde forêt pour contourner une erreur.

Questions : pourquoi renommer avant promotion ? Que change le redémarrage ? Pourquoi DSRM doit-il rester hors transcript et Git ? Peut-on appeler l'IP d'un serveur pour obtenir le même résultat Kerberos qu'avec son FQDN ?

## 9. TP4 — WinRM, sessions et inventaire distant

**Machine : ADM01. Identité : administrateur du laboratoire. Durée : 60 min.**

### Authentification, transport et second saut

Les connexions utilisent les noms DNS et Kerberos. WinRM sur 5985 est un transport HTTP, mais le contenu de la session est protégé au niveau des messages avec Kerberos ; HTTP ne signifie donc pas « commandes en clair ». Cela ne remplace pas une architecture de production adaptée. Le port 5986 utilise TLS avec un certificat valable. TrustedHosts n'est pas une preuve d'identité.

Le second saut apparaît lorsqu'une session ADM01 → SRV01 tente d'accéder à un partage sur DC01 en votre nom. Les informations d'authentification ne sont pas simplement transférées au troisième système. Pour ce TP, **copier depuis ADM01 avec `Copy-Item -ToSession`**, puis traiter localement sur la cible, évite ce besoin. Pas de CredSSP.

### À réaliser

```powershell
$admin = Get-Credential -Message 'Administration du laboratoire CAMPUS'
Test-WSMan srv01.campus.test -Authentication Kerberos -Credential $admin
$s = New-PSSession -ComputerName srv01.campus.test -Authentication Kerberos `
  -ConfigurationName Microsoft.PowerShell -Credential $admin
Invoke-Command -Session $s {hostname; $PSVersionTable.PSVersion}
Invoke-Command -Session $s {
  Get-CimInstance Win32_OperatingSystem | Select-Object Caption,LastBootUpTime
}
Remove-PSSession $s
```

1. Écrire `etudiant/templates/Get-Inventory.ps1` : une session par cible, collecte nom, OS, domaine, mémoire, espace disque, dernier boot et version PowerShell.
2. Retourner un objet OK ou ECHEC par machine ; fermer la session dans `finally` ; poursuivre si une cible échoue.
3. Exporter les objets dans un CSV, sans propriétés de remoting parasites. Utiliser une projection `Select-Object` avant l'export.
4. Ajouter `absent.campus.test` aux cibles : trois succès, une erreur explicite, pas d'arrêt global.
5. Passer une variable à la cible avec `-ArgumentList` et `param(...)` ; expliquer la différence avec une variable locale.

Les objets distants sont souvent désérialisés : leurs propriétés survivent, pas forcément leurs méthodes. Si l'on doit agir sur un service, on exécute l'action dans la session distante.

### Résultats et preuve

Exporter l'inventaire avec une ligne par cible et conserver l'erreur de la cible absente. Prendre S1-Domaine sur les trois VM après arrêt propre. Le formateur valide S1 avant J2.

Question de synthèse : sur quelle machine s'exécute chaque ligne de votre script ? Avec quelle identité ? Quels ports et quelles résolutions de noms utilise-t-elle ?

## 10. TP5 — Provisioning AD à partir de données

**Écriture sur ADM01 ; exécution sur DC01 après copie directe. Identité : administrateur du laboratoire. Durée : 170 min.**

### Phase A : validation sans mutation, 70 min

Le CSV valide décrit six salariés fictifs. Le CSV invalide contient un doublon, un service non autorisé, un identifiant invalide et un nom manquant. Le script doit **analyser toutes les lignes et refuser le fichier avant de créer quoi que ce soit**. Une validation ligne par ligne suivie immédiatement d'une création laisserait un état partiel.

Règles : colonnes exactes `SamAccountName;GivenName;Surname;Department`, non vide, identifiant de 3 à 20 caractères selon `^[a-z][a-z0-9.]{2,19}$`, unicité sans tenir compte de la casse, GivenName et Surname non vides ; Department dans IT/RH/Direction. La limite et le motif sont des règles pédagogiques de ce jeu de données, pas une définition universelle des identifiants AD.

```powershell
$rows = @(Import-Csv C:\Lab\commun\data\utilisateurs.csv -Delimiter ';' -Encoding UTF8)
$rows | Group-Object Department | Select-Object Name,Count
$rows | Group-Object SamAccountName | Where-Object Count -gt 1
```

Créer une fonction `Test-LabCsv` réutilisable qui retourne les lignes valides ou lève une erreur détaillée. La tester avant d'importer ActiveDirectory. Pour chaque erreur, identifier la ligne CSV ; aucune donnée réelle ne doit être ajoutée au jeu fourni.

### Phase B : état AD désiré, 100 min

| Objet | Emplacement / composition |
|---|---|
| OU racine | OU=PSLAB,DC=campus,DC=test |
| OU enfants | Utilisateurs, Groupes, Serveurs |
| Groupes globaux | GG_IT, GG_RH, GG_Direction |
| Groupes locaux de domaine | DL_IT_M, DL_RH_M, DL_Direction_M |
| Appartenance | utilisateur → GG_service → DL_service_M |
| Utilisateurs | les six lignes du CSV, sous OU=Utilisateurs |

AGDLP signifie Accounts → Global groups → Domain Local groups → Permissions. Les groupes globaux représentent les personnes d'un service ; les groupes locaux de domaine représentent l'accès à une ressource. On attribue les ACL aux DL, pas directement à chaque utilisateur. L'OU Serveurs est préparée pour une future organisation ; le déplacement des comptes ordinateurs n'est pas exigé dans ce parcours.

Compléter `Sync-Users.ps1` : paramètres, `SupportsShouldProcess`, garde campus.test, validation complète préalable, OU protégées contre suppression accidentelle, groupes de sécurité, comptes et appartenances. Ne pas supprimer les comptes absents du CSV. Ne pas modifier le mot de passe d'un compte existant. En cas de compte/groupe homonyme hors OU ou de service différent, signaler une collision/dérive et arrêter plutôt que l'écraser.

Le mot de passe initial est saisi en SecureString, jamais dans le CSV. Les six nouveaux comptes utilisent un mot de passe temporaire commun uniquement pour la démonstration de provisioning ; ils portent ChangePasswordAtLogon. En entreprise, prévoir une délivrance individuelle hors bande. Avant les tests SMB/JEA, le formateur fait définir **deux mots de passe distincts** pour Alice et Chloé et retire l'obligation de changement pour ces seuls comptes de test ; voir ci-dessous.

### Copie et exécution sur DC01

```powershell
# Sur ADM01 : copier le script terminé et son module, si utilisé.
$dc = New-PSSession dc01.campus.test -Authentication Kerberos -Credential $admin
Copy-Item C:\Lab\etudiant\templates\Sync-Users.ps1 C:\Lab\Sync-Users.ps1 -ToSession $dc
# Si un .psm1 est requis, le copier dans le même dossier.
Invoke-Command -Session $dc {
  & C:\Lab\Sync-Users.ps1 -CsvPath C:\Lab\commun\data\utilisateurs.csv -WhatIf
}
Remove-PSSession $dc
# En console DC01, pour le passage réel :
$initial = Read-Host 'Mot de passe temporaire des comptes du TP' -AsSecureString
& C:\Lab\Sync-Users.ps1 -CsvPath C:\Lab\commun\data\utilisateurs.csv -InitialPassword $initial
```

### Batterie de contrôles

1. Passer le CSV invalide ; relever les erreurs ; comparer le nombre de comptes avant/après : aucun ajout.
2. Passer le CSV valide avec `-WhatIf` : aucune OU, aucun compte et aucun groupe ajoutés.
3. Passer réellement : trois OU enfants, six groupes, six utilisateurs et les bonnes appartenances.
4. Repasser : mêmes comptes et groupes, aucun nouveau, mots de passe inchangés.
5. Tester une collision avec un utilisateur existant hors OU seulement si le formateur fournit un environnement de secours ; sinon expliquer la garde dans le code.
6. Si une panne réseau/service survient après quelques créations : noter les créations effectuées, rétablir le service, relancer le même CSV. Le traitement additif reprend ; il n'est pas une transaction AD globale.

```powershell
# Sur DC01, après contrôle du provisioning ; préparer uniquement les identités de test.
foreach ($u in @('alice.martin','chloe.bernard')) {
  $p = Read-Host "Nouveau mot de passe distinct pour $u" -AsSecureString
  Set-ADAccountPassword -Identity $u -Reset -NewPassword $p
  Set-ADUser -Identity $u -ChangePasswordAtLogon $false
}
```

### Preuves, questions, dépannage

Conserver les résultats avant/après, la sortie WhatIf et les appartenances directes de chaque GG/DL. `Get-ADGroupMember` sans `-Recursive` montre l'imbrication ; avec `-Recursive`, il déroule les membres.

Pourquoi une OU et un groupe ne servent-ils pas au même usage ? Pourquoi l'import doit-il refuser l'ensemble avant de muter ? Une relance suffit-elle à corriger un changement de service ? Pourquoi le stockage d'un SecureString n'est-il pas une solution universelle de coffre de secrets ?

Si les commandes AD sont introuvables, vérifier la machine d'exécution et l'installation des outils ; exécuter sur DC01. Si une création échoue pour mot de passe, vérifier la stratégie du domaine ; ne pas affaiblir cette stratégie. Si une OU existe, comparer son DN exact plutôt que créer un doublon homonyme.

## 11. TP6 — Partages SMB et ACL NTFS

**Configuration : SRV01 admin ; tests : ADM01 avec Alice puis Chloé. Durée : 90 min + 60 min de vérifications.**

### Deux barrières d'accès

À distance via SMB, les droits effectifs résultent des permissions de partage **et** NTFS. Si le partage donne Change et NTFS donne Read, on ne peut pas écrire. Une ACL NTFS protège aussi l'accès local ; le partage seul ne suffit pas. Une autorisation directe à un utilisateur complexifie la maintenance ; le modèle AGDLP centralise l'attribution par groupe.

Le caractère `$` masque le partage dans l'énumération ordinaire ; il ne sécurise pas son accès. Access Based Enumeration masque certains éléments à l'énumération, mais ne remplace pas les ACL. Une règle Deny générale est rarement nécessaire quand l'absence d'Allow suffit.

### État attendu

| Dossier | Partage | ACL SMB | ACL NTFS du dossier |
|---|---|---|---|
| C:\LabData\IT | IT$ | CAMPUS\DL_IT_M : Change | DL_IT_M : Modify |
| C:\LabData\RH | RH$ | CAMPUS\DL_RH_M : Change | DL_RH_M : Modify |
| C:\LabData\Direction | Direction$ | CAMPUS\DL_Direction_M : Change | DL_Direction_M : Modify |

NTFS conserve aussi SYSTEM et Administrateurs locaux en FullControl, hérités par les enfants. Les autres permissions héritées du parent sont retirées sur ces **nouveaux dossiers de TP**. Ne jamais appliquer ce remplacement d'ACL à un dossier de production. Les partages sont chiffrés (`EncryptData`) ; SMB 1 n'est pas requis. Le pare-feu ne permet le port TCP 445 entrant que depuis ADM01.

### À réaliser

1. Sur SRV01, créer les trois dossiers et construire leurs ACL. Utiliser les SID pour SYSTEM (`S-1-5-18`) et Administrateurs (`S-1-5-32-544`) afin de ne pas dépendre de la langue Windows ; résoudre les noms des groupes CAMPUS.
2. Configurer l'héritage ContainerInherit et ObjectInherit. Exporter les SDDL avec `(Get-Acl <chemin>).Sddl` avant/après.
3. Créer les trois partages avec `New-SmbShare`, FolderEnumerationMode AccessBased, EncryptData et le seul groupe métier autorisé en Change.
4. Si un partage existe, vérifier son chemin avant d'en changer les droits. Repasser le script ; vérifier qu'aucune ACE ne s'accumule.
5. Désactiver les règles SMB Windows générales du laboratoire et créer une règle dédiée à 10.77.10.30. Relever le filtre d'adresse.

### Tester réellement comme un salarié

Ne pas utiliser votre session administrateur pour « prouver » l'absence de droits. Depuis ADM01, ouvrir une **nouvelle console avec un contexte réseau propre** :

```powershell
runas /netonly /user:CAMPUS\alice.martin "powershell.exe -NoProfile"
# Dans cette NOUVELLE console : saisir le mot de passe Alice lors de runas.
'test Alice' | Set-Content '\\srv01.campus.test\IT$\alice.txt'
Get-Content '\\srv01.campus.test\IT$\alice.txt'
Get-ChildItem '\\srv01.campus.test\RH$' -ErrorAction Stop
```

Le troisième accès doit être refusé. Avec `/netonly`, `whoami` affiche toujours l'identité locale d'origine : c'est l'identité **réseau** qui change. Ne pas utiliser cette console pour un test de droits locaux. Fermer cette console, puis ouvrir une autre avec `chloe.bernard` : écrire dans RH$ doit réussir ; IT$ doit être refusé ; Direction$ doit être refusé aux deux.

Windows refuse souvent plusieurs connexions SMB concurrentes avec des identités différentes dans le même contexte (erreur 1219). Utiliser les consoles runas séparées ; ne pas effacer des connexions réseau non liées au TP. Si un utilisateur vient d'être ajouté à un groupe, renouveler sa session réseau/son ticket ; le jeton existant n'est pas mis à jour instantanément.

### Recette et questions

| Identité réseau | IT$ lire/écrire | RH$ lire/écrire | Direction$ |
|---|---|---|---|
| Alice, service IT | autorisé | refusé | refusé |
| Chloé, service RH | refusé | autorisé | refusé |

Preuves : ACL SMB, SDDL NTFS, filtre pare-feu, résultats des six cellules, inventaire de fichiers créé par chaque identité. Une erreur attendue doit être conservée dans le compte rendu comme preuve de contrôle d'accès. Arrêter proprement les VM et prendre S2-Acces.

Expliquez la différence entre Read, Modify et FullControl ; pourquoi l'accès administratif local n'implique-t-il pas forcément un droit SMB sur le partage métier ? Pourquoi ne pas retirer les droits SYSTEM ? Qu'arrive-t-il si on désactive uniquement le partage mais laisse le dossier lisible localement ?

## 12. TP7 — Déployer un intranet avec intégrité et rollback

**Configuration IIS : SRV01 admin. Orchestration : ADM01 admin de SRV01. Durée : 170 min.**

### Pipeline de déploiement

Les données de la release sont séparées du moteur de publication. ADM01 contrôle l'artefact, copie le fichier vers SRV01 via sa session directe, vérifie de nouveau l'empreinte sur SRV01, mémorise le chemin IIS actuel, change le chemin, puis vérifie le service. Si HTTP ou le contenu attendu échoue, l'ancien chemin est restauré.

Un SHA256 garantit la cohérence avec une référence de confiance. Si un attaquant modifie à la fois l'artefact et son manifeste, leur cohérence reste possible : le hash n'est pas une signature. Le manifeste doit venir d'un canal contrôlé. Pour ce TP, les fichiers sont des données HTML statiques ; aucune installation de package Internet n'est nécessaire.

### Phase A : IIS et première release, 70 min

1. Sur SRV01, installer les composants :

```powershell
Install-WindowsFeature Web-Server,Web-Static-Content,Web-Default-Doc,Web-Mgmt-Tools,Web-Scripting-Tools
Import-Module WebAdministration
```

2. Créer C:\LabWeb\bootstrap et un index.html initial. Autoriser SYSTEM et Administrateurs à modifier l'arbre, IIS_IUSRS (`S-1-5-32-568`) à lire/exécuter. Créer un pool Campus pour contenu statique et le site Campus sur **8080**, sans conflit avec Default Web Site sur 80. Démarrer W3SVC/pool/site.
3. Créer une règle HTTP 8080 limitée à ADM01 ; tester localement sur SRV01 puis depuis ADM01. L'HTTP applicatif du TP est limité au LAN isolé ; en production, prévoir TLS et un certificat.
4. Lire le manifeste v1 et vérifier son SHA256 depuis ADM01 :

```powershell
$release = 'C:\Lab\commun\releases\v1'
$m = Get-Content "$release\manifest.json" -Raw | ConvertFrom-Json
(Get-FileHash "$release\index.html" -Algorithm SHA256).Hash -eq $m.Sha256
```

5. Compléter `Publish-Campus.ps1`. Pour cette première version, valider le format vN et le seul fichier autorisé index.html ; utiliser un staging unique. Copier avec `-ToSession`, pas depuis un partage tiers.
6. Tester `-WhatIf`, puis publier v1 ; vérifier HTTP 200 et le marqueur **Campus - v1** depuis ADM01.

### Phase B : seconde release et échecs, 100 min

1. Publier v2. Conserver PreviousPath, CurrentPath, Version, SHA256 et Etat en preuve. Repasser v2 : même résultat, aucun doublon et pas d'écrasement d'une version différente au même numéro.
2. Copier v2 dans un dossier de travail ; altérer index.html sans modifier manifest.json. Le script doit refuser **avant la copie/bascule**. Le site reste v2.
3. Pour tester un vrai rollback après bascule, fabriquer une release v3 avec un hash valide mais un contenu sans marqueur Campus :

```powershell
# Sur ADM01 ; uniquement dans le répertoire de travail du TP.
Copy-Item C:\Lab\commun\releases\vbad C:\Lab\v3 -Recurse
$m = Get-Content C:\Lab\v3\manifest.json -Raw | ConvertFrom-Json
$m.Version = 'v3'
$m | ConvertTo-Json | Set-Content C:\Lab\v3\manifest.json -Encoding UTF8
# Le hash du fichier reste valide ; le contrôle fonctionnel doit échouer.
```

4. Publier cette v3 : l'intégrité doit passer, puis le contrôle fonctionnel échouer, puis le chemin repointer vers v2. Le script renvoie un échec explicite. Prouver que le site sert encore Campus - v2 depuis ADM01.
5. Vérifier la fermeture des sessions et la conservation de v1/v2. Une release v3 défectueuse peut rester pour analyse ; réutiliser son numéro avec un contenu différent doit être refusé. Corriger avec **v4**, ou analyser puis supprimer uniquement la release de test avec le formateur.
6. Documenter le retour manuel vers v1 en console SRV01 : changer le physicalPath avec `Set-ItemProperty IIS:\Sites\Campus`, puis vérifier HTTP. Revenir ensuite à v2 pour la recette.

### Critères de réussite

- Le site fonctionne localement et depuis ADM01 ; IIS n'écrit pas dans le code.
- La référence de hash est vérifiée avant transfert et sur la cible.
- WhatIf ne publie rien ; version existante différente refusée.
- L'erreur fonctionnelle déclenche le retour au chemin précédent et un échec visible.
- Le compte rendu distingue hash, authenticité, disponibilité et validation métier.

Limites : bascule de chemin à but pédagogique, pas de garantie « zéro interruption » ni de migration de base de données. Un contrôle local n'évalue pas le pare-feu externe : le test HTTP depuis ADM01 est obligatoire. Une panne de W3SVC ne disparaît pas par simple rollback de fichiers.

## 13. TP8 — Contrôle de santé et tâche planifiée

**Machine : SRV01 admin. Durée : 60 min.**

### Conception

Une tâche n'a ni votre console, ni forcément votre profil, ni vos lecteurs réseau. Utiliser un chemin absolu et un exécutable précis. Le contrôle doit vérifier service W3SVC, réponse HTTP locale et espace disque, puis écrire un JSON horodaté UTC ; `exit 0` si sain, `exit 1` sinon. Le fichier de rapport est local : le compte SYSTEM n'emprunte pas vos identifiants réseau.

### À réaliser

1. Compléter `Write-Health.ps1`. Prévoir le rapport d'échec dans catch ; seuil d'espace libre 2 Go ; délai HTTP de 5 s.
2. Exécuter manuellement dans un nouveau processus `powershell.exe -NoProfile -File <chemin>` et lire `$LASTEXITCODE`. Ne pas appeler un script avec exit directement dans votre console de travail.
3. Protéger **C:\LabOps** (code de la tâche) et **C:\LabReports** (résultats) avec SYSTEM/Administrateurs seulement. Un script modifiable par un utilisateur ordinaire puis exécuté par SYSTEM est une élévation de privilèges.
4. Copier le script dans C:\LabOps\Write-Health.ps1. Construire action, déclencheur toutes les 5 min, principal SYSTEM et paramètres (durée max 2 min, IgnoreNew).
5. Enregistrer PSLAB-Health, démarrer à la demande et consulter :

```powershell
Get-ScheduledTask -TaskName PSLAB-Health
Get-ScheduledTaskInfo -TaskName PSLAB-Health
Get-Content C:\LabReports\health.json -Raw | ConvertFrom-Json
Get-Acl C:\LabOps | Format-List
```

6. Arrêter W3SVC volontairement sur SRV01, lancer la tâche, attendre son retour puis observer rapport et LastTaskResult. Rétablir avec Start-Service W3SVC, relancer, vérifier 0 et Healthy=true. Utiliser une attente bornée ; ne pas prendre un résultat ancien pour un succès.

Résultats : JSON récent, Healthy vrai/faux selon le service, codes 0/1, chemin protégé. SYSTEM est accepté ici pour une supervision **locale de laboratoire** ; un déploiement réel doit évaluer un compte de service au minimum de droits. Ne pas ajouter un mot de passe dans l'action de la tâche.

Questions : pourquoi `$LASTEXITCODE` n'est-il pas `$?` ? Pourquoi ne pas utiliser un lecteur Z: ? Comment détecter un rapport ancien ? Que se passe-t-il si une tâche dure plus longtemps que son intervalle ?

## 14. TP9 — Journalisation et diagnostic d'incident

**SRV01 et ADM01. Identité : admin du laboratoire. Durée : 50 min.**

### Traces utiles et limites

Les événements 4104 consignent des blocs de script lorsque Script Block Logging est activé ; 4103 concerne Module Logging. Un transcript enregistre l'entrée/sortie de console, mais ce n'est pas une preuve exhaustive de tous les effets d'un programme. Ces mécanismes peuvent capturer des données sensibles : réserver l'accès aux logs, éviter les secrets dans les commandes et définir une conservation. Le TP n'exporte pas les secrets ni les transcripts bruts dans Git.

### À réaliser

1. Sur SRV01, activer Script Block Logging, Module Logging et la transcription Windows PowerShell 5.1 par les paramètres Policies du registre (ou la stratégie fournie par le formateur). Dossier C:\LabLogs protégé SYSTEM/Administrateurs. Ouvrir **une nouvelle session** pour appliquer le comportement.
2. Depuis ADM01, exécuter dans une session distante un bloc contenant un marqueur inoffensif `TP9-CAMPUS` et `Get-Service W3SVC`.
3. Sur SRV01, lire les événements du journal `Microsoft-Windows-PowerShell/Operational` et retrouver le marqueur :

```powershell
Get-WinEvent -FilterHashtable @{
  LogName='Microsoft-Windows-PowerShell/Operational';Id=4103,4104
  StartTime=(Get-Date).AddMinutes(-15)
} | Select-Object TimeCreated,Id,Message
Get-ChildItem C:\LabLogs -Recurse
```

4. Exporter uniquement les extraits nécessaires, après contrôle d'absence de secrets. Ne pas interpréter l'absence d'un événement comme preuve d'absence d'activité avant d'avoir vérifié configuration, session et journal.
5. Le formateur injecte une panne parmi : DNS client incorrect sur ADM01, W3SVC arrêté, ou fichier index altéré. Votre binôme dispose de 20 min pour identifier la cause, corriger le minimum puis prouver le rétablissement.

### Méthode de diagnostic

Réseau/IP → résolution DNS → port TCP → authentification/identité → état du service → configuration et contenu → permissions. Formuler une hypothèse et un test discriminant à chaque étape. Exemples : DNS SRV absent avec ping IP réussi ; TCP 8080 refusé quand W3SVC est arrêté ; HTTP 200 mais contenu incorrect ; AccessDenied SMB alors que TCP 445 est ouvert.

Preuve attendue : symptôme initial, deux hypothèses, test de chacune, cause établie, correction et même test rejoué avec succès. Rétablir DNS sur 10.77.10.10, W3SVC en Running et release v2 saine avant la recette.

## 15. TP10 — Recette finale et transfert à l'exploitation

**Machine : ADM01. Durée : 60 min + 20 min de restitution.**

La recette ne se réduit pas à « le script n'a pas produit d'erreur ». Préparer des assertions oui/non et des preuves reproductibles. Les contrôles d'accès doivent être exécutés avec les bonnes identités et rester manuels si votre automate tourne en administrateur.

| ID | Contrôle | Résultat attendu |
|---|---|---|
| R01 | Installation des 3 VM | Server Core |
| R02 | IPv4/DNS/domaine | conforme au JSON, campus.test |
| R03 | DNS SRV et FQDN | résolution AD et serveurs |
| R04 | PSSession vers 3 VM | Kerberos, Microsoft.PowerShell |
| R05 | AD | six comptes, six groupes, bons services et imbrications |
| R06 | CSV invalide/WhatIf | aucun changement AD |
| R07 | Deuxième passage | aucun doublon ni mot de passe remis à zéro |
| R08 | SMB/NTFS | trois partages, ACL prévues, chiffrement et six tests métier |
| R09 | Pare-feu | profils actifs, ports 5985/445/8080 limités comme prévu |
| R10 | Publication | v2 active, hashes corrects, refus artefact altéré |
| R11 | Rollback | v3 invalide refusée, v2 encore servie |
| R12 | Santé | tâche lancée, résultat 0, JSON récent Healthy=true |
| R13 | Observabilité | événement marqueur et transcript protégé |
| R14 | Exploitation | procédure, scripts et preuves sans secret |

Créer un petit script de recette qui renvoie des objets Test/Passed/Detail et un code 1 si une assertion automatique échoue. Le corrigé formateur fournit un exemple qui couvre un **sous-ensemble** (Core, domaine, sessions, compteurs, SMB chiffré, santé, HTTP). Les ACL effectives, l'imbrication des groupes, le refus du CSV, WhatIf, rollback et logs nécessitent vos preuves complémentaires. Un résultat automatique vert n'est donc pas une validation complète de sécurité.

Restituer en 3 min : démonstration v2, test d'accès refusé, explication d'un catch/finally, limite d'un hash et une décision de conception. Prévoir 2 min de question individuelle par étudiant en parallèle du travail des binômes, selon la taille de classe.

## 16. Extensions pour les binômes en avance

### A. JEA : une administration déléguée, 45–60 min hors socle

Sur **SRV01 membre uniquement**, créer un endpoint RestrictedRemoteServer `CampusRead`, un rôle ne montrant que Get-Service pour W3SVC et WinRM, avec paramètres limités et un compte virtuel. Autoriser GG_IT à s'y connecter. Alice doit pouvoir obtenir le statut, mais `Restart-Service`, `Get-ChildItem C:\` et les exécutables externes doivent être refusés. Tester avec `-ConfigurationName CampusRead -Credential <Alice>` depuis ADM01. Conserver le transcript. Les comptes virtuels JEA ont des comportements particuliers sur DC ; ne pas transposer ce rôle au contrôleur de domaine. Cette extension n'est pas exigée pour la note de base.

### B. PowerShell 7, 30–45 min hors socle

Installer une version stable validée en amont par le formateur depuis un MSI officiel. Comparer `$PSVersionTable` dans powershell.exe et pwsh.exe. Exécuter la collecte d'objets et JSON, puis constater le moteur de l'endpoint Microsoft.PowerShell dans la session distante. Ne pas supposer qu'un client 7 transforme cet endpoint en 7. Les modules Windows/leur compatibilité se vérifient séparément ; ne pas migrer l'intégralité des corrigés pendant la séance.

### C. Tests de code, 45–60 min hors socle

Avec Pester préinstallé et version connue, tester uniquement `Test-LabCsv` : jeu valide, doublon, champ vide, département inconnu, mauvais en-têtes, fichier vide. Ces tests ne remplacent pas les essais d'intégration AD ni les essais de droits réseau. Pour une chaîne réelle, ajouter analyse statique et signature Authenticode selon la politique d'organisation.

### D. Infrastructure déclarative, 30 min de réflexion

Transformer le JSON en état désiré plus riche, comparer Get/Test/Set et votre script impératif. Le socle ne dépend pas de DSC ni d'une installation de module en ligne. Expliquer ce qu'apporterait un outil déclaratif et ses contraintes de version/distribution.

## 17. Dépannage : matrice rapide

| Symptôme | Hypothèse principale | Contrôle | Action ciblée |
|---|---|---|---|
| Domaine introuvable | mauvais DNS client | Get-DnsClientServerAddress, DNS SRV | DNS 10.77.10.10 |
| Kerberos échoue | IP utilisée, FQDN/heure/domaine incorrect | Resolve-DnsName, identité, date | FQDN et heure correcte ; pas TrustedHosts * |
| TCP 5985 échoue | WinRM/règle/scoping | service, Test-NetConnection, filtre adresse | corriger service ou règle dédiée en console |
| AD cmdlet introuvable | mauvais moteur/machine/module | PSVersionTable, Get-Module -ListAvailable | exécuter sur DC01 en 5.1 |
| SMB 1219 | autre identité dans même contexte | sessions et connexions du TP | nouvelle console runas /netonly |
| AccessDenied SMB | mauvaise identité/groupe/ACL | contexte réseau, GG/DL, ACL SMB/NTFS | corriger le droit attendu et renouveler session |
| Site 403/404 | ACL, chemin, document | physicalPath, fichier, logs IIS | corriger la cause locale |
| HTTP 200 mauvais contenu | release/fichier incorrect | hash + marqueur | rollback/release suivante |
| Tâche sans rapport | chemin, droits, exécutable | LastTaskResult, journal TaskScheduler | chemins absolus, ACL et moteur 5.1 |
| WhatIf a muté | mutations non protégées | inspection ShouldProcess | corriger avant essai réel |
| Accents corrompus | encodage script/CSV | lire octets/encodage éditeur | PS1 UTF-8 BOM ; Import-Csv UTF8 |

## 18. Bonnes pratiques, IA et sources

L'IA peut proposer un script ou expliquer une erreur. Vous restez responsable de vérifier le nom du cmdlet, ses paramètres, la machine d'exécution et les effets. Ne lui transmettre aucun secret. Avant d'exécuter : lire le code, rechercher les mutations, consulter la documentation officielle, tester WhatIf si prévu, puis tester dans le LAN isolé. Le compte rendu signale une proposition IA rejetée ou corrigée. L'évaluation porte aussi sur votre capacité à expliquer et modifier le code.

Bibliographie officielle consultée le 6 octobre 2026 ; les liens complets et leur usage figurent dans `Sources.md`. Références principales : options Server Core, SConfig, installation AD DS, sécurité WinRM et second saut, New-SmbShare, New-VM, JEA, ExecutionPolicy et Task Scheduler. Une documentation de cmdlet indique sa version de module ; vérifier la version locale avec Get-Command/Get-Help.

Fin du support étudiant. Votre objectif final est un laboratoire reproductible et une explication de ses limites, avec des preuves qui peuvent être rejouées.
