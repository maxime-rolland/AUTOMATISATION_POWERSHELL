# 03 — Transformer un CSV en comptes et groupes AD

[Accueil](../README.md) · [Inventaire](02-PowerShell-et-inventaire.md) · [Étape suivante](04-Partages-et-tests.md)

**Correction : [Lab.Common.ps1](../scripts/Lab.Common.ps1) et [02-Sync-AD.ps1](../scripts/02-Sync-AD.ps1). Le script AD s'exécute sur le DC du domaine existant.**

## Les données pilotent les opérations

Le [CSV](../donnees/utilisateurs.csv) décrit six personnes. Les deux services autorisés proviennent du JSON. Si vous changez le nom d'un serveur dans JSON, les scripts doivent continuer à fonctionner ; si vous ajoutez une personne au CSV, il ne doit pas être nécessaire de dupliquer une ligne de code de création.

```powershell
# ADMIN : charger les services autorisés dans la configuration.
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json

# Lire les personnes ; @() conserve une collection même si le CSV n'a qu'une ligne.
$users = @(Import-Csv .\donnees\utilisateurs.csv -Delimiter ';' -Encoding UTF8)

# Vérifier les quatre champs utiles, sans déclencher de création AD.
$users | Select-Object SamAccountName,Prenom,Nom,Service

# Compter les personnes par service : trois IT et trois RH attendues dans le jeu initial.
$users | Group-Object Service | Select-Object Name,Count
```

Dans le jeu commun, trois personnes sont dans IT et trois dans RH. `SamAccountName` est l'identifiant de connexion court ; Prenom/Nom décrivent la personne ; Service détermine son groupe métier. Les comptes sont fictifs et préfixés pour distinguer le TP des utilisateurs existants.

## Valider toutes les lignes avant de modifier AD

Le CSV invalide contient quatre types d'erreur : doublon, caractère interdit dans l'identifiant, service non configuré et prénom manquant. Si vous créez les comptes pendant que vous lisez chaque ligne, la ligne 1 peut être créée avant de découvrir l'erreur de la ligne 4. L'état devient partiel à cause d'une donnée que l'on aurait pu refuser dès le départ.

L'algorithme attendu est : lire **tout** le fichier → accumuler les erreurs → arrêter s'il y en a → appliquer les changements seulement si le fichier entier est valide.

```powershell
# ADMIN : le point suivi d'un espace charge les fonctions dans la console courante.
. .\scripts\Lab.Common.ps1

# Lire ET valider le JSON avec la fonction commune.
$config = Read-LabConfig .\config\lab.json

# Valider toutes les lignes du jeu correct : six personnes doivent être renvoyées.
# Cette fonction ne crée aucune OU, aucun compte et aucun groupe.
Read-ValidatedUsers -Path .\donnees\utilisateurs.csv `
    -AllowedServices $config.Services

# Test négatif : cet appel doit lever une erreur détaillant les problèmes du fichier.
# Exécuter ce second appel séparément pour lire son message avant de continuer.
Read-ValidatedUsers -Path .\donnees\utilisateurs-invalides.csv `
    -AllowedServices $config.Services
```

Le second appel **doit lever une erreur**. Ce résultat est un succès du contrôle de données. Une erreur attendue n'est pas quelque chose à cacher pour rendre la démonstration « verte ».

Règles de la correction : colonnes exactes, fichier non vide, noms non vides, compte en minuscules avec le préfixe commun `tp.` et maximum 20 caractères, aucun identifiant répété, service dans la liste autorisée. Ce sont les règles du TP, pas une présentation exhaustive des limites AD.

### Fonction de validation, bloc par bloc

| Ligne ou notion | Explication |
|---|---|
| Import-Csv + @() | Charger les personnes et obtenir toujours une collection |
| Compare-Object des en-têtes | Détecter une colonne renommée ou oubliée |
| $seen = @{} | Retrouver un identifiant déjà rencontré sans reparcourir tout le CSV |
| $line = $i + 2 | Donner le vrai numéro de ligne à corriger |
| -cnotmatch | Vérifier un motif en tenant compte de la casse |
| liste $errors | Signaler plusieurs problèmes en une seule lecture |
| throw avant return | Refuser le jeu complet avant toute création |

## État AD attendu pour tous

| Objet | Nom / emplacement |
|---|---|
| OU racine | TP-Automatisation sous le domaine |
| OU utilisateurs | Utilisateurs sous l'OU racine |
| OU groupes | Groupes sous l'OU racine |
| Groupes globaux | GG_TP_IT, GG_TP_RH |
| Groupes locaux de domaine | DL_TP_IT_M, DL_TP_RH_M |
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
# ADMIN : charger les destinations et utiliser $admin saisi à l'étape 02.
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json

# Ouvrir la connexion vers DC01 ; toutes les commandes AD seront exécutées sur ce DC.
$s = New-PSSession -ComputerName $config.DomainController -Authentication Kerberos -Credential $admin

# Même dossier de travail distant pour tous ; cette variable contient un chemin, pas une session.
$remote = 'C:\TP-Automatisation\scripts'
Invoke-Command -Session $s -ArgumentList $remote {
    # Recevoir le chemin envoyé par ADMIN dans une variable du bloc distant.
    param($folder)
    # Créer le répertoire sur DC01 ; masquer uniquement sa sortie, pas ses erreurs.
    New-Item $folder -ItemType Directory -Force | Out-Null
}

# Pousser les deux scripts depuis ADMIN vers DC01, sans récupération depuis un partage tiers.
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $s
Copy-Item .\scripts\02-Sync-AD.ps1 -Destination $remote -ToSession $s

# Copier les paramètres et les données que le script AD lira sur DC01.
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $s
Copy-Item .\donnees\utilisateurs.csv -Destination "$remote\utilisateurs.csv" -ToSession $s

# Planifier les créations AD ; -WhatIf ne crée aucun objet dans l'annuaire.
# Les fichiers ont déjà été copiés par les commandes précédentes : ce n'est pas le pilote global.
Invoke-Command -Session $s -ArgumentList $remote {
    param($folder)
    # & appelle le script dont le chemin est contenu dans une chaîne.
    & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" `
        -CsvPath "$folder\utilisateurs.csv" -WhatIf
}
```

Vérifier qu'aucun objet n'a été créé par le dry run. Pour le vrai passage, puis sa répétition :

```powershell
# ADMIN : saisir un secret temporaire conforme à la stratégie du domaine, en SecureString.
$password = Read-Host 'Secret temporaire de la maquette' -AsSecureString

# Envoyer le chemin et le secret comme paramètres au bloc exécuté sur DC01.
Invoke-Command -Session $s -ArgumentList $remote,$password {
    param($folder,$password)
    # Exécuter réellement : créer ce qui manque et conserver les comptes déjà présents.
    & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" `
        -CsvPath "$folder\utilisateurs.csv" -InitialPassword $password
}

# Avant de fermer : réexécuter le même Invoke-Command pour obtenir six états EXISTANT.
# Ne pas resaisir de mot de passe ni supprimer de comptes pour provoquer des créations.
Remove-PSSession $s
```

Les commandes de copie ci-dessus servent à découvrir l'étape. En fin de TP, le pilote doit effectuer ces copies sans intervention manuelle.

## Vérifier AD, pas seulement la sortie du script

Sur le DC, dans une console Windows PowerShell :

```powershell
# DC01 : charger les commandes AD dans la console où ces vérifications sont exécutées.
Import-Module ActiveDirectory

# Construire le DN de l'OU racine : OU=TP-Automatisation,DC=learn-it,DC=local.
# Le DN du domaine est lu dans AD plutôt que reconstruit à la main.
$base = 'OU=TP-Automatisation,' + (Get-ADDomain).DistinguishedName

# Lister uniquement les comptes de l'OU Utilisateurs du TP.
# -Properties Department ajoute le service ; Enabled fait partie des propriétés par défaut.
# Attendu : six comptes, trois IT/trois RH, tous activés.
Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,$base" -Properties Department |
    Select-Object SamAccountName,Department,Enabled

# Lister uniquement les groupes du TP ; vérifier deux Global et deux DomainLocal,
# tous de catégorie Security. Une OU organise les objets ; ce n'est pas un groupe d'accès.
Get-ADGroup -Filter * -SearchBase "OU=Groupes,$base" |
    Select-Object Name,GroupScope,GroupCategory

# Vérifier les membres directs du groupe métier : Alice, Bruno et Farid.
Get-ADGroupMember GG_TP_IT

# Vérifier l'imbrication : le DL doit contenir GG_TP_IT comme membre direct.
# Sans -Recursive, cette commande montre le groupe, pas les trois comptes qu'il contient.
Get-ADGroupMember DL_TP_IT_M
```

Le GG IT contient trois comptes ; le DL IT contient le GG, et non trois permissions individuelles.

## Travail demandé et preuves

1. Expliquer pourquoi la validation doit précéder New-ADUser.
2. Tester le fichier invalide sans effectuer de créations.
3. Déployer les six comptes et quatre groupes ; vérifier OU et appartenances.
4. Rejouer et montrer zéro nouvelle création, les mêmes comptes et les mêmes groupes.
5. Préparer l'adaptation commune de l'étape 05 : ajouter `tp.gabriel` (Gabriel Moreau, IT) dans une copie du CSV, puis montrer une seule création supplémentaire. Effectuer cet ajout après la vérification du socle de six comptes.

**Preuves :** données initiales, erreur de validation, sortie WhatIf, premier/deuxième passage et lecture des vrais objets AD. Les captures d'une sortie « terminé » ne remplacent pas ces vérifications.
