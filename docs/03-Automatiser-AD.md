# 03 — Transformer un CSV en comptes et groupes AD

[Accueil](../README.md) · [Inventaire](02-PowerShell-et-inventaire.md) · [Étape suivante](04-Partages-et-tests.md)

**Correction : [Lab.Common.ps1](../scripts/Lab.Common.ps1) et [02-Sync-AD.ps1](../scripts/02-Sync-AD.ps1). Le script AD s'exécute sur le DC du domaine existant.**

## Les données pilotent les opérations

Le [CSV](../donnees/utilisateurs.csv) décrit six personnes. Les deux services autorisés proviennent du JSON. Si vous changez le nom d'un serveur dans JSON, les scripts doivent continuer à fonctionner ; si vous ajoutez une personne au CSV, il ne doit pas être nécessaire de dupliquer une ligne de code de création.

```powershell
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$users = @(Import-Csv .\donnees\utilisateurs.csv -Delimiter ';' -Encoding UTF8)
$users | Select-Object SamAccountName,Prenom,Nom,Service
$users | Group-Object Service | Select-Object Name,Count
```

Pour B01, trois personnes sont dans IT et trois dans RH. `SamAccountName` est l'identifiant de connexion court ; Prenom/Nom décrivent la personne ; Service détermine son groupe métier. Les comptes sont fictifs et préfixés pour distinguer le TP des utilisateurs existants.

## Valider toutes les lignes avant de modifier AD

Le CSV invalide contient quatre types d'erreur : doublon, caractère interdit dans l'identifiant, service non configuré et prénom manquant. Si vous créez les comptes pendant que vous lisez chaque ligne, la ligne 1 peut être créée avant de découvrir l'erreur de la ligne 4. L'état devient partiel à cause d'une donnée que l'on aurait pu refuser dès le départ.

L'algorithme attendu est : lire **tout** le fichier → accumuler les erreurs → arrêter s'il y en a → appliquer les changements seulement si le fichier entier est valide.

```powershell
. .\scripts\Lab.Common.ps1
$config = Read-LabConfig .\config\lab.json
$prefix = 'tp.' + $config.LabId.ToLowerInvariant() + '.'
Read-ValidatedUsers -Path .\donnees\utilisateurs.csv `
    -AllowedServices $config.Services -AccountPrefix $prefix
Read-ValidatedUsers -Path .\donnees\utilisateurs-invalides.csv `
    -AllowedServices $config.Services -AccountPrefix $prefix
```

Le second appel **doit lever une erreur**. Ce résultat est un succès du contrôle de données. Une erreur attendue n'est pas quelque chose à cacher pour rendre la démonstration « verte ».

Règles de la correction : colonnes exactes, fichier non vide, noms non vides, compte en minuscules avec le préfixe de votre LabId et maximum 20 caractères, aucun identifiant répété, service dans la liste autorisée. Ce sont les règles du TP, pas une présentation exhaustive des limites AD.

### Fonction de validation, bloc par bloc

| Ligne ou notion | Explication |
|---|---|
| Import-Csv + @() | Charger les personnes et obtenir toujours une collection |
| Compare-Object des en-têtes | Détecter une colonne renommée ou oubliée |
| $seen = @{} | Retrouver un identifiant déjà rencontré sans reparcourir tout le CSV |
| $line = $i + 2 | Donner le vrai numéro de ligne à corriger |
| -cnotmatch | Vérifier un motif en tenant compte de la casse |
| StartsWith du préfixe | Empêcher B02 de créer les identifiants de B01 par erreur |
| liste $errors | Signaler plusieurs problèmes en une seule lecture |
| throw avant return | Refuser le jeu complet avant toute création |

## État AD attendu, pour B01

| Objet | Nom / emplacement |
|---|---|
| OU racine | TP-Automatisation-B01 sous le domaine |
| OU utilisateurs | Utilisateurs sous l'OU racine |
| OU groupes | Groupes sous l'OU racine |
| Groupes globaux | GG_TP_B01_IT, GG_TP_B01_RH |
| Groupes locaux de domaine | DL_TP_B01_IT_M, DL_TP_B01_RH_M |
| Comptes | les six SamAccountName du CSV sous Utilisateurs |

Les personnes sont membres du groupe global de leur service. Ce groupe est membre du groupe local de domaine correspondant. Le groupe local de domaine recevra les permissions sur le dossier. **AGDLP** : Accounts → Global groups → Domain Local groups → Permissions.

Une OU sert à organiser et à déléguer l'administration ; ce n'est pas une liste d'accès à un partage. Un groupe sert ici à porter les appartenances et les autorisations. Placer Alice dans l'OU Utilisateurs ne lui donne, à lui seul, aucun droit sur IT.

## Idempotence : créer seulement ce qui manque

Avant New-ADUser, le script recherche le compte. S'il existe au bon endroit avec le bon service, il le conserve et rapporte EXISTANT. S'il n'existe pas, il le crée et rapporte CREE. Il ajoute l'appartenance au groupe seulement si elle manque.

Ce comportement permet de rejouer le même CSV sans dupliquer les comptes ni réinitialiser leurs mots de passe. Il ne promet pas de tout corriger : si le compte homonyme existe ailleurs, est désactivé ou possède un service différent, le script s'arrête pour que vous diagnostiquiez le cas. Il ne supprime aucun compte absent du CSV.

Une validation d'entrée préalable n'est pas une transaction AD. Une panne pendant la création peut laisser quelques objets présents. Le bon comportement est de signaler l'erreur, rétablir le service, puis relancer le même jeu. La relance retrouve les objets déjà créés.

## WhatIf et secrets

`SupportsShouldProcess` expose WhatIf au script. Chaque mutation doit passer par `$PSCmdlet.ShouldProcess(...)`. Ajouter simplement le mot WhatIf dans le nom d'un paramètre ne suffit pas.

En dry run, les groupes prévus n'existent pas encore forcément : la correction ne tente pas de lire leurs membres comme s'ils étaient déjà créés. Elle décrit le plan. Le pilote de l'étape 05 fait son propre plan après validation des données et des connexions ; il ne copie pas les scripts dans ce mode.

Le paramètre InitialPassword est un SecureString saisi avec Read-Host. Pour la maquette fictive, un secret temporaire commun et `ChangePasswordAtLogon=false` permettent les essais SMB immédiats. En entreprise, prévoir des secrets individuels et un canal de remise adapté. Ne pas faire de ces valeurs de laboratoire une politique d'identité. Ne jamais exporter le mot de passe dans les preuves ou le CSV.

Si le mot de passe ne respecte pas la stratégie du domaine, AD peut laisser un compte désactivé même si sa création a commencé. La correction vérifie l'état et s'arrête. Il faut diagnostiquer et réparer ce compte de TP explicitement ; il n'est pas « OK » parce qu'il existe.

## Exécuter cette étape séparément pour la comprendre

Depuis ADMIN, ouvrir une session vers le DC, puis copier les ressources directement :

```powershell
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$s = New-PSSession -ComputerName $config.DomainController -Authentication Kerberos -Credential $admin
$remote = "C:\TP-Automatisation\scripts\$($config.LabId)"
Invoke-Command -Session $s -ArgumentList $remote {
    param($folder)
    New-Item $folder -ItemType Directory -Force | Out-Null
}
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $s
Copy-Item .\scripts\02-Sync-AD.ps1 -Destination $remote -ToSession $s
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $s
Copy-Item .\donnees\utilisateurs.csv -Destination "$remote\utilisateurs.csv" -ToSession $s
Invoke-Command -Session $s -ArgumentList $remote {
    param($folder)
    & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" `
        -CsvPath "$folder\utilisateurs.csv" -WhatIf
}
```

Vérifier qu'aucun objet n'a été créé par le dry run. Pour le vrai passage, puis sa répétition :

```powershell
$password = Read-Host 'Secret temporaire de la maquette' -AsSecureString
Invoke-Command -Session $s -ArgumentList $remote,$password {
    param($folder,$password)
    & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" `
        -CsvPath "$folder\utilisateurs.csv" -InitialPassword $password
}
# Réexécuter exactement le même bloc pour comparer CREE et EXISTANT.
Remove-PSSession $s
```

Les commandes de copie ci-dessus servent à découvrir l'étape. En fin de TP, le pilote doit effectuer ces copies sans intervention manuelle.

## Vérifier AD, pas seulement la sortie du script

Sur le DC, pour B01 :

```powershell
Import-Module ActiveDirectory
$base = 'OU=TP-Automatisation-B01,' + (Get-ADDomain).DistinguishedName
Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,$base" -Properties Department |
    Select-Object SamAccountName,Department,Enabled
Get-ADGroup -Filter * -SearchBase "OU=Groupes,$base" |
    Select-Object Name,GroupScope,GroupCategory
Get-ADGroupMember GG_TP_B01_IT
Get-ADGroupMember DL_TP_B01_IT_M
```

Le GG IT contient trois comptes ; le DL IT contient le GG, et non trois permissions individuelles. Adapter B01 à votre identifiant.

## Travail demandé et preuves

1. Expliquer pourquoi la validation doit précéder New-ADUser.
2. Tester le fichier invalide sans effectuer de créations.
3. Déployer les six comptes et quatre groupes ; vérifier OU et appartenances.
4. Rejouer et montrer zéro nouvelle création, les mêmes comptes et les mêmes groupes.
5. Ajouter une septième personne fictive à votre CSV, avec un identifiant unique de votre binôme ; la relance doit créer une seule personne. Garder ce CSV pour la démonstration ou conserver aussi le jeu initial de six.

**Preuves :** données initiales, erreur de validation, sortie WhatIf, premier/deuxième passage et lecture des vrais objets AD. Les captures d'une sortie « terminé » ne remplacent pas ces vérifications.
