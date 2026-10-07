# 04 — Automatiser les partages et prouver les droits

[Accueil](../README.md) · [Étape AD](03-Automatiser-AD.md) · [Étape suivante](05-Pilotage-et-demonstration.md)

**Corrections : [03-Sync-Shares.ps1](../scripts/03-Sync-Shares.ps1) et [05-Test-Access.ps1](../scripts/05-Test-Access.ps1).**

Reprenez sur ADMIN après avoir vérifié les six comptes et les quatre groupes de l'étape 03. Gardez votre console administrative d'origine pour `$admin` et les connexions WinRM. Les consoles ouvertes avec `runas /netonly` serviront uniquement aux tests métiers ; fermez-les après chaque identité testée.

Si vous avez fermé la console administrative entre les deux journées, rouvrez Windows PowerShell 5.1 sur ADMIN, placez-vous dans `C:\TP-PowerShell` et resaisissez `$admin = Get-Credential`. Le premier bloc d'appel ci-dessous relira la configuration et le nom NetBIOS ; vous pourrez ensuite ouvrir les consoles métiers avec le secret attribué aux comptes à l'étape 03.

## Le résultat métier à obtenir

Alice et ses collègues IT ont accès au dossier IT. Chloé et ses collègues RH ont accès à RH. Aucun de ces comptes ne doit accéder au dossier de l'autre service. Les administrateurs peuvent gérer localement les dossiers, mais leurs privilèges ne sont pas utilisés pour faire le test métier.

État attendu dans toutes les maquettes :

| Ressource | Groupe autorisé | SMB | NTFS |
|---|---|---|---|
| TP_IT$ → C:\TP-Automatisation\Partages\IT | DL_TP_IT_M | Change | Modify |
| TP_RH$ → C:\TP-Automatisation\Partages\RH | DL_TP_RH_M | Change | Modify |

Le caractère `$` masque le partage dans une énumération habituelle. Il ne protège pas l'accès : un utilisateur qui connaît le chemin peut le tenter. La protection vient des permissions.

## SMB et NTFS : deux niveaux à comprendre

Les permissions SMB s'appliquent à l'entrée par le partage réseau. Les permissions NTFS s'appliquent au dossier et à ses fichiers, y compris localement. À travers SMB, l'utilisateur doit satisfaire **les deux**. Un partage qui autorise Change et un dossier qui n'autorise que Read ne permettent pas d'écrire.

Modify permet de lire, créer, modifier et supprimer le contenu. FullControl ajoute notamment la gestion des permissions. Les comptes métiers ont Modify ; SYSTEM et le groupe Administrateurs locaux conservent FullControl. Le serveur et ses administrateurs peuvent ainsi maintenir la ressource sans donner la gestion des droits aux utilisateurs.

Le script attribue la permission au **DL**, pas à Alice directement. Lorsque l'on ajoute une personne à GG_TP_IT, l'imbrication existante transmet l'autorisation sans modifier l'ACL de chaque dossier.

## Comprendre la construction d'une ACL

Une ACL est une liste de règles, ou ACE. Une règle relie une identité, un droit, une portée et un type Allow/Deny. Dans le corrigé :

```powershell
# Exemple de construction EN MÉMOIRE : aucune permission sur disque n'est encore changée.
# DirectorySecurity représente la liste de permissions NTFS d'un dossier.
$acl = New-Object System.Security.AccessControl.DirectorySecurity

# Protéger la liste de l'héritage du dossier parent, sans recopier les règles héritées.
$acl.SetAccessRuleProtection($true, $false)

# Utiliser le SID de SYSTEM : il est identique quelle que soit la langue de Windows.
$sid = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'

# Créer une ACE : SYSTEM, contrôle total, dossier courant et héritage vers fichiers/sous-dossiers.
# None est le drapeau de propagation ; Allow signifie autorisation, pas refus.
$ace = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
)

# Ajouter cette règle à l'objet ACL ; Set-Acl l'appliquera au disque dans le script corrigé.
# Le corrigé ajoute aussi Administrateurs et le DL métier avant cette application.
$acl.AddAccessRule($ace)
```

`DirectorySecurity` construit la liste de droits d'un dossier. La nouvelle ACL empêche l'accumulation d'ACE au fil des relances. `SetAccessRuleProtection(true,false)` coupe l'héritage du parent et ne recopie pas ses anciennes règles. Cette décision est acceptable sur les **nouveaux dossiers réservés au TP** ; elle ne doit pas être appliquée sans analyse à des dossiers réels.

ContainerInherit propage la règle aux sous-dossiers ; ObjectInherit la propage aux fichiers. None laisse la règle s'appliquer aussi au dossier courant. Allow autorise le droit. Le script n'ajoute pas de Deny général : l'absence d'autorisation du groupe RH sur IT suffit dans cette ACL contrôlée.

Les SID intégrés `S-1-5-18` (SYSTEM) et `S-1-5-32-544` (Administrateurs) ne dépendent pas de la langue de Windows. Pour le groupe métier, la correction construit `NetBIOS\DL_TP_IT_M` puis résout ce nom en SID. Le groupe AD doit donc exister **avant** la configuration des dossiers dans ce script : la conversion de son nom en SID échouerait sinon.

### GG, DL et ACL : qui fait quoi ?

`DL` signifie **Domain Local**, ou **Domaine local** : c'est la portée du groupe AD, pas un dossier ni un groupe local du serveur. `DL_` est une convention de nommage ; c'est le paramètre `-GroupScope DomainLocal` qui définit réellement cette portée.

| Élément | Exemple | Rôle |
|---|---|---|
| Compte | tp.alice | Identifie la personne |
| GG, groupe global | GG_TP_IT | Rassemble les personnes du service IT |
| DL, groupe local de domaine | DL_TP_IT_M | Reçoit le droit Modify sur la ressource IT |
| ACL, liste de permissions | ACL du dossier IT | Contient l'ACE qui autorise le SID du DL |

Alice est membre du GG ; le GG est membre du DL ; l'ACL autorise le DL. On crée donc les groupes et les appartenances dans AD avant de configurer les droits. Ajouter Gabriel au GG donnera accès au même dossier sans ajouter une ACE individuelle. Une ACL stocke des SID : l'ordre du TP vient de notre besoin de **résoudre le nom du groupe**, pas d'une interdiction générale des SID non résolus.

## Ce que fait le script de partages

| Bloc | Rôle |
|---|---|
| Vérification machine/domaine | Refuser une exécution sur un autre serveur ou sur le DC |
| Paramètre NetBIOSName | Utiliser la valeur réellement lue sur le DC |
| Préparation des plans | Résoudre les identités et contrôler les chemins avant de modifier |
| New-Item puis Set-Acl | Créer le dossier et appliquer la liste voulue |
| New-SmbShare si absent | Créer un partage, sans multiplier les noms à la relance |
| Revoke/Unblock puis Grant | Revenir à la seule autorisation SMB prévue, même après une dérive |
| EncryptData | Exiger le chiffrement SMB pour ces partages |
| Règle réseau TP-Auto-SMB | Autoriser le poste de test sans couper Windows Firewall |

Si un partage homonyme pointe vers un autre chemin, le script s'arrête au lieu de le détourner. La correction réapplique les ACL du dossier racine métier ; elle ne prétend pas nettoyer toutes les permissions explicites ajoutées manuellement à chaque fichier enfant. La liste de partage, elle, converge vers l'état prévu.

Sur le serveur réservé à votre copie de la maquette, les règles SMB Windows générales sont désactivées au profit de la règle du TP. Une autre règle/GPO peut également autoriser 445. Ajouter une règle Allow ne prouve pas à elle seule qu'il n'existe aucun autre accès possible. Le test d'isolation métier repose aussi sur les ACL.

## Appel séparé, depuis ADMIN

On réutilise les copies de l'étape AD et on transmet la valeur NetBIOS obtenue sur le DC :

```powershell
# ADMIN : récupérer la configuration et ouvrir une session administrative vers DC01.
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$dc = New-PSSession -ComputerName $config.DomainController -Authentication Kerberos -Credential $admin

# Lire le vrai nom NetBIOS du domaine ; le nom DNS ne suffit pas à le deviner.
$domain = Invoke-Command -Session $dc {
    Import-Module ActiveDirectory
    Get-ADDomain | Select-Object DNSRoot,NetBIOSName
}
Remove-PSSession $dc

# Ouvrir la session vers SRV01, où les dossiers et partages seront configurés.
$srv = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos -Credential $admin
$remote = 'C:\TP-Automatisation\scripts'

# Créer le dossier de travail sur SRV01 ; ArgumentList passe le chemin au bloc distant.
Invoke-Command -Session $srv -ArgumentList $remote {
    param($folder)
    New-Item $folder -ItemType Directory -Force | Out-Null
}

# Pousser les fichiers nécessaires depuis ADMIN vers SRV01.
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $srv
Copy-Item .\scripts\03-Sync-Shares.ps1 -Destination $remote -ToSession $srv
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $srv

# Vérifier le plan sans appliquer les droits ; les groupes AD doivent déjà exister.
Invoke-Command -Session $srv -ArgumentList $remote,$domain.NetBIOSName {
    param($folder,$netbios)
    & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios -WhatIf
}
```

Après lecture du plan, exécutez le bloc suivant pour appliquer les droits, vérifier l'état réel sur SRV01 et fermer la session :

```powershell
# ADMIN : appliquer réellement le script de partages sur SRV01, sans -WhatIf.
Invoke-Command -Session $srv -ArgumentList $remote,$domain.NetBIOSName {
    param($folder,$netbios)
    & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios
}

# Lire l'état réel SUR SRV01, indépendamment de la sortie du script de création.
Invoke-Command -Session $srv {
    # Attendu : deux noms distincts, les bons chemins et EncryptData = True.
    Get-SmbShare -Name 'TP_IT$','TP_RH$' | Select-Object Name,Path,EncryptData

    # Attendu pour IT : le DL IT avec l'autorisation SMB Change.
    Get-SmbShareAccess -Name 'TP_IT$'

    # Lire les ACE NTFS : SYSTEM/Administrateurs en FullControl et DL IT en Modify.
    # Les drapeaux doivent propager les autorisations aux fichiers et sous-dossiers.
    (Get-Acl C:\TP-Automatisation\Partages\IT).Access |
        Select-Object IdentityReference,FileSystemRights,InheritanceFlags
}

# Fermer la session administrative avant les essais métiers en consoles séparées.
Remove-PSSession $srv
```

Comparer les listes à la table d'état attendu.

## Tester avec Alice, pas avec l'administrateur

Depuis ADMIN, lancer une nouvelle console avec une identité **réseau** dédiée :

```powershell
# ADMIN : $domain a été récupéré sur DC01 dans le bloc précédent.
$netbios = $domain.NetBIOSName

# Ouvrir une NOUVELLE console ; ses accès réseau utiliseront le compte ordinaire Alice.
# /netonly conserve l'identité locale, donc whoami ne devient pas tp.alice.
# Saisir le secret temporaire commun quand runas le demande.
runas /netonly "/user:$netbios\tp.alice" "powershell.exe -NoProfile"
```

Saisir le secret temporaire des comptes fictifs lorsque runas le demande. Dans la **nouvelle** console :

```powershell
# Dans la NOUVELLE console d'Alice : se placer dans le dépôt local sur ADMIN.
Set-Location C:\TP-PowerShell

# Tester les deux partages ; seul IT doit être lisible ET accessible en écriture.
# Format-List sert uniquement à afficher les objets de résultat à la fin du pipeline.
# Attendu : Passed = True pour IT et RH, avec les droits inversés entre les deux services.
.\scripts\05-Test-Access.ps1 -ExpectedService IT | Format-List
```

Vous devez obtenir CanList=true et CanWrite=true pour IT, puis false et false pour RH. Passed doit être vrai sur les deux lignes. Le test utilise un nom GUID pour son fichier de preuve et ne supprime que ce fichier s'il a réussi à l'écrire.

Fermer la console d'Alice. Dans la console administrative d'origine, ouvrir celle de Chloé :

```powershell
# ADMIN, console d'origine : réutiliser le vrai NetBIOS lu sur DC01.
# Cette nouvelle console utilisera Chloé pour les connexions réseau, avec le même secret de TP.
runas /netonly "/user:$netbios\tp.chloe" "powershell.exe -NoProfile"
```

Puis exécuter dans la **nouvelle console de Chloé** :

```powershell
# Se placer dans le dépôt local ; les partages à tester sont lus dans config\lab.json.
Set-Location C:\TP-PowerShell

# Attendu : lecture/écriture autorisées sur RH, refusées sur IT ; Passed = True sur les deux lignes.
.\scripts\05-Test-Access.ps1 -ExpectedService RH | Format-List
```

Les résultats doivent être inversés par rapport à Alice.

Fermez ensuite la console de Chloé et revenez à la console administrative d'origine pour poursuivre le TP. Une commande de déploiement doit utiliser le compte d'administration ; une preuve d'accès métier doit utiliser Alice, Chloé ou Gabriel.

| Identité réseau | Partage IT lire/écrire | Partage RH lire/écrire |
|---|---|---|
| Alice | autorisé | refusé |
| Chloé | refusé | autorisé |

Avec `/netonly`, `whoami` indique toujours l'identité locale d'origine. Ce n'est pas un test de droits locaux ; ce sont les connexions réseau qui utilisent la credential spécifiée. L'utilisateur ordinaire n'a pas besoin d'être autorisé à ouvrir une session interactive sur le serveur.

Si Windows signale l'erreur SMB 1219, vous avez probablement plusieurs identités vers le même serveur dans un même contexte. Utiliser les consoles runas séparées plutôt que supprimer indistinctement les connexions du poste. Après modification d'une appartenance, fermer et rouvrir la console réseau pour renouveler le contexte.

## Distinguer refus attendu et panne

Un accès refusé à RH ne prouve rien si le serveur est éteint. Avant d'accepter un refus comme preuve, vérifier que le partage autorisé fonctionne avec la même identité. Le script compare les deux services ; il faut interpréter les deux lignes ensemble et lire le message d'erreur.

Si tous les accès échouent, contrôler : nom/IP, port TCP 445, AdminIPAddress du JSON, secret, état du compte, groupes et ACL. Si tout est autorisé, contrôler la credential réseau réellement utilisée et les permissions SMB/NTFS. Ne pas essayer de « réparer » en ajoutant Everyone FullControl.

## Travail demandé

1. Construire les deux partages à partir de config.Services, pas avec deux blocs copiés-collés différents.
2. Expliquer les trois autorisations NTFS et leur héritage.
3. Tester les quatre combinaisons Alice/Chloé × IT/RH.
4. Rejouer le script puis vérifier l'absence de doublons dans les ACL, la liste SMB attendue et la conservation des quatre tests d'accès.

**Preuves :** liste des vrais partages, droits SMB/NTFS, quatre tests métiers et résultats après relance. Le fonctionnement doit être montré en direct pendant l'évaluation.
