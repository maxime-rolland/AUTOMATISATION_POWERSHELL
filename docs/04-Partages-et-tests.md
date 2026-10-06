# 04 — Automatiser les partages et prouver les droits

[Accueil](../README.md) · [Étape AD](03-Automatiser-AD.md) · [Étape suivante](05-Pilotage-et-demonstration.md)

**Corrections : [03-Sync-Shares.ps1](../scripts/03-Sync-Shares.ps1) et [05-Test-Access.ps1](../scripts/05-Test-Access.ps1).**

## Le résultat métier à obtenir

Alice et ses collègues IT ont accès au dossier IT. Chloé et ses collègues RH ont accès à RH. Aucun de ces comptes ne doit accéder au dossier de l'autre service. Les administrateurs peuvent gérer localement les dossiers, mais leurs privilèges ne sont pas utilisés pour faire le test métier.

Pour B01 :

| Ressource | Groupe autorisé | SMB | NTFS |
|---|---|---|---|
| TP_B01_IT$ → C:\TP-Automatisation\Partages\B01\IT | DL_TP_B01_IT_M | Change | Modify |
| TP_B01_RH$ → C:\TP-Automatisation\Partages\B01\RH | DL_TP_B01_RH_M | Change | Modify |

Le caractère `$` masque le partage dans une énumération habituelle. Il ne protège pas l'accès : un utilisateur qui connaît le chemin peut le tenter. La protection vient des permissions.

## SMB et NTFS : deux niveaux à comprendre

Les permissions SMB s'appliquent à l'entrée par le partage réseau. Les permissions NTFS s'appliquent au dossier et à ses fichiers, y compris localement. À travers SMB, l'utilisateur doit satisfaire **les deux**. Un partage qui autorise Change et un dossier qui n'autorise que Read ne permettent pas d'écrire.

Modify permet de lire, créer, modifier et supprimer le contenu. FullControl ajoute notamment la gestion des permissions. Les comptes métiers ont Modify ; SYSTEM et le groupe Administrateurs locaux conservent FullControl. Le serveur et ses administrateurs peuvent ainsi maintenir la ressource sans donner la gestion des droits aux utilisateurs.

Le script attribue la permission au **DL**, pas à Alice directement. Lorsque l'on ajoute une personne à GG_TP_B01_IT, l'imbrication existante transmet l'autorisation sans modifier l'ACL de chaque dossier.

## Comprendre la construction d'une ACL

Une ACL est une liste de règles, ou ACE. Une règle relie une identité, un droit, une portée et un type Allow/Deny. Dans le corrigé :

```powershell
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$sid = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'
$ace = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
)
$acl.AddAccessRule($ace)
```

`DirectorySecurity` construit la liste de droits d'un dossier. La nouvelle ACL empêche l'accumulation d'ACE au fil des relances. `SetAccessRuleProtection(true,false)` coupe l'héritage du parent et ne recopie pas ses anciennes règles. Cette décision est acceptable sur les **nouveaux dossiers réservés au TP** ; elle ne doit pas être appliquée sans analyse à des dossiers réels.

ContainerInherit propage la règle aux sous-dossiers ; ObjectInherit la propage aux fichiers. None laisse la règle s'appliquer aussi au dossier courant. Allow autorise le droit. Le script n'ajoute pas de Deny général : l'absence d'autorisation du groupe RH sur IT suffit dans cette ACL contrôlée.

Les SID intégrés `S-1-5-18` (SYSTEM) et `S-1-5-32-544` (Administrateurs) ne dépendent pas de la langue de Windows. Pour le groupe métier, la correction construit `NetBIOS\DL_TP_B01_IT_M` puis résout ce nom en SID. Le groupe AD doit donc exister **avant** la configuration des dossiers.

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
| Règle réseau nommée avec LabId | Autoriser le poste de test sans couper Windows Firewall |

Si un partage homonyme pointe vers un autre chemin, le script s'arrête au lieu de le détourner. La correction réapplique les ACL du dossier racine métier ; elle ne prétend pas nettoyer toutes les permissions explicites ajoutées manuellement à chaque fichier enfant. La liste de partage, elle, converge vers l'état prévu.

Sur un serveur réservé à votre maquette, les règles SMB Windows générales sont désactivées au profit de la règle du TP. Sur un serveur partagé par la classe, le formateur prépare cette partie réseau ; une autre règle/GPO peut également autoriser 445. Ajouter une règle Allow ne prouve pas à elle seule qu'il n'existe aucun autre accès possible. Le test d'isolation métier repose aussi sur les ACL.

## Appel séparé, depuis ADMIN

On réutilise les copies de l'étape AD et on transmet la valeur NetBIOS obtenue sur le DC :

```powershell
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$dc = New-PSSession -ComputerName $config.DomainController -Authentication Kerberos -Credential $admin
$domain = Invoke-Command -Session $dc {Get-ADDomain | Select-Object DNSRoot,NetBIOSName}
Remove-PSSession $dc

$srv = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos -Credential $admin
$remote = "C:\TP-Automatisation\scripts\$($config.LabId)"
Invoke-Command -Session $srv -ArgumentList $remote {
    param($folder)
    New-Item $folder -ItemType Directory -Force | Out-Null
}
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $srv
Copy-Item .\scripts\03-Sync-Shares.ps1 -Destination $remote -ToSession $srv
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $srv
Invoke-Command -Session $srv -ArgumentList $remote,$domain.NetBIOSName {
    param($folder,$netbios)
    & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios -WhatIf
}
```

Faire le vrai passage en rejouant le dernier bloc sans WhatIf. Vérifier sur la cible puis fermer la session :

```powershell
Invoke-Command -Session $srv {
    Get-SmbShare -Name 'TP_B01_IT$','TP_B01_RH$' | Select-Object Name,Path,EncryptData
    Get-SmbShareAccess -Name 'TP_B01_IT$'
    (Get-Acl C:\TP-Automatisation\Partages\B01\IT).Access |
        Select-Object IdentityReference,FileSystemRights,InheritanceFlags
}
Remove-PSSession $srv
```

Adapter B01 dans les contrôles si nécessaire. Comparer les listes à la table d'état attendu.

## Tester avec Alice, pas avec l'administrateur

Depuis ADMIN, lancer une nouvelle console avec une identité **réseau** dédiée :

```powershell
# $domain.NetBIOSName provient de la lecture précédente du DC.
$netbios = $domain.NetBIOSName
runas /netonly "/user:$netbios\tp.b01.alice" "powershell.exe -NoProfile"
```

Saisir le secret temporaire des comptes fictifs lorsque runas le demande. Dans la **nouvelle** console :

```powershell
Set-Location C:\TP-PowerShell
.\scripts\05-Test-Access.ps1 -ExpectedService IT | Format-List
```

Vous devez obtenir CanList=true et CanWrite=true pour IT, puis false et false pour RH. Passed doit être vrai sur les deux lignes. Le test utilise un nom GUID pour son fichier de preuve et ne supprime que ce fichier s'il a réussi à l'écrire.

Fermer la console, puis ouvrir une autre avec `tp.b01.chloe` et lancer `-ExpectedService RH`. Les résultats doivent être inversés.

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
4. Rejouer le script puis vérifier l'absence de doublons dans les ACL et la conservation des tests d'accès.
5. Si le formateur ajoute une autorisation SMB trop large sur **votre partage de TP**, montrer que la relance la retire. Ne pas faire ce test sur le partage d'un autre binôme.

**Preuves :** liste des vrais partages, droits SMB/NTFS, quatre tests métiers et résultats après relance. Le fonctionnement doit être montré en direct pendant l'évaluation.
