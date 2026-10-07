# 05 — Une commande pour tout déployer, puis démontrer le résultat

[Accueil](../README.md) · [Partages](04-Partages-et-tests.md) · [Évaluation](../EVALUATION.md)

**Correction : [04-Deploy-Lab.ps1](../scripts/04-Deploy-Lab.ps1).**

## L'automatisation complète

Les étapes précédentes vous ont fait copier et lancer les scripts pour comprendre leur contexte. Maintenant, le poste ADMIN doit effectuer ces opérations avec une seule commande. C'est le rôle du pilote : il ne réécrit pas toute la logique AD et ACL ; il coordonne les scripts spécialisés.

```mermaid
flowchart TD
    A["Lire JSON et tout le CSV"] --> B{"Données valides ?"}
    B -->|Non| X["Refus explicite avant déploiement"]
    B -->|Oui| C["Ouvrir et vérifier les deux sessions Kerberos"]
    C --> D{"WhatIf ?"}
    D -->|Oui| P["Afficher le plan sans copier ni créer"]
    D -->|Non| E["Copier les fichiers et synchroniser AD"]
    E --> F["Configurer dossiers, ACL et partages"]
    F --> G["Écrire les rapports et fermer les sessions"]
    C -.->|"Erreur"| X
    E -.->|"Erreur"| X
    F -.->|"Erreur"| X
    X --> H["Fermer les sessions ; corriger la cause puis relancer"]
```

Une erreur peut laisser des objets déjà créés si elle survient pendant la synchronisation. Le pilote n'efface pas tout pour revenir à zéro ; il explique l'échec et permet une reprise additive. La validation du CSV et des deux connexions se fait avant les premières modifications de déploiement.

## Lire la correction par responsabilités

| Responsabilité | Code à repérer | Pourquoi |
|---|---|---|
| Paramétrer | ConfigPath, CsvPath, ResultPath, Credential | Réutiliser le pilote et changer son jeu d'entrée |
| Vérifier | Read-LabConfig, Read-ValidatedUsers | Ne pas copier/déployer des données incorrectes |
| S'authentifier | New-PSSession, Kerberos | Utiliser la bonne identité et les noms DNS |
| Confirmer le contexte | Get-ADDomain, Win32_ComputerSystem | Vérifier le domaine et le rôle du serveur de fichiers |
| Planifier | WhatIfPreference et ShouldProcess | Décrire l'opération sans l'effectuer |
| Distribuer | Copy-Item -ToSession | Copier directement depuis ADMIN vers la cible |
| Ordonnancer | AD avant partages | Les groupes doivent exister avant la résolution de SID |
| Transmettre | ArgumentList et param | Passer chemins, secret sécurisé et NetBIOS comme objets |
| Rendre compte | comptes.csv, partages.csv, deploiement.json | Montrer créations, conservation et horodatage |
| Libérer | finally puis Remove-PSSession | Fermer les connexions après succès ou échec |

Le secret temporaire n'est pas écrit dans les rapports. Une fois la session établie, WinRM Kerberos protège les échanges de messages. Le fichier CSV et les scripts sont poussés par ADMIN vers la cible. Le serveur n'essaie pas d'aller lire un partage sur une troisième machine avec votre identité : cela évite le problème de second saut.

## Premier lancement

```powershell
# ADMIN : utiliser les chemins relatifs depuis la racine du dépôt.
Set-Location C:\TP-PowerShell

# Saisir le compte qui peut administrer les deux cibles ; ne pas tester les droits métiers avec lui.
$admin = Get-Credential -Message 'Administration de la maquette'

# Valider données et connexions, puis afficher le plan sans copier ni créer les ressources.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -WhatIf

# Saisir une seule fois le secret temporaire des comptes fictifs en SecureString.
$password = Read-Host 'Secret temporaire des comptes fictifs' -AsSecureString

# Déployer réellement avec le CSV initial : six comptes, quatre groupes et deux partages.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password

# Lire le bilan récent ; Created/Existing reflètent l'état trouvé lors de ce passage.
Get-Content .\resultats\deploiement.json -Raw | ConvertFrom-Json

# Relire les rapports détaillés produits localement sur ADMIN.
Import-Csv .\resultats\comptes.csv -Delimiter ';' -Encoding UTF8
Import-Csv .\resultats\partages.csv -Delimiter ';' -Encoding UTF8
```

Sur une maquette sans objets du TP, le résumé annonce Created=6, Existing=0, Shares=2. Si vous avez déjà fait l'étape AD séparément, il doit annoncer Created=0 et Existing=6 ; ce n'est pas une erreur. La vérité est l'état présent, pas un chiffre de démonstration obtenu en supprimant manuellement des comptes.

State=OK signifie que les étapes administratives du pilote sont terminées. Il reste à vérifier l'accès SMB avec les identités métiers : le pilote tourne en administrateur et ne peut donc pas conclure seul à l'isolation d'Alice.

## Second lancement et preuve d'idempotence

```powershell
# Garder la sortie détaillée du passage précédent pour comparer les états.
Copy-Item .\resultats\comptes.csv .\resultats\comptes-avant-relance.csv

# Rejouer la même commande et le même CSV, sans suppression ni changement de secret.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password

# Attendu au deuxième passage : Created = 0, Existing = 6, Shares = 2.
Get-Content .\resultats\deploiement.json -Raw | ConvertFrom-Json
```

Attendu : zéro nouveau compte ; les mêmes groupes et partages ; mêmes accès autorisés/refusés. Les ACL sont réappliquées, ce qui est une opération technique répétée, mais les ressources métier ne se multiplient pas. Le script ne réinitialise pas les mots de passe des comptes existants.

Comparer les vrais objets AD, les listes de partages et les résultats métiers. Un script qui affiche EXISTANT mais modifie indûment les droits n'est pas correctement vérifié par son seul rapport.

## Test d'entrée invalide

Noter le nombre d'utilisateurs de votre OU, lancer avec le CSV invalide, puis recompter :

```powershell
# ADMIN : fournir volontairement le jeu invalide, sans changer les scripts corrigés.
# La validation locale doit lever une erreur avant toute copie/création AD ou SMB.
# Attendu : message précis ; le nombre d'objets avant/après reste identique.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin `
    -CsvPath .\donnees\utilisateurs-invalides.csv -InitialPassword $password
```

L'erreur apparaît avant le déploiement. Aucun nouvel utilisateur, groupe ou partage ne doit être ajouté. L'ancien rapport d'un passage réussi peut toujours être présent : **ne pas confondre un ancien State=OK avec le résultat de l'appel qui vient d'échouer**. Lire l'erreur réelle et les compteurs avant/après.

## Test d'une cible inaccessible

Créer une copie du JSON dans `config/lab-erreur.json` et y remplacer FileServer par `absent.learn-it.local`. Lancer le pilote avec `-ConfigPath` vers cette copie. Il doit produire une erreur explicite et fermer toute session déjà ouverte. Le vrai JSON n'est pas altéré.

```powershell
# ADMIN : conserver le vrai JSON intact et fabriquer une configuration de test distincte.
Copy-Item .\config\lab.json .\config\lab-erreur.json

# Modifier une propriété de l'objet en mémoire, puis enregistrer uniquement la copie.
$bad = Get-Content .\config\lab-erreur.json -Raw | ConvertFrom-Json
$bad.FileServer = 'absent.learn-it.local'
$bad | ConvertTo-Json | Set-Content .\config\lab-erreur.json -Encoding UTF8

# Cette cible doit ne pas exister dans le labo ; l'ouverture de session doit échouer.
# Le pilote ferme la session DC éventuellement ouverte et ne commence pas le déploiement.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin `
    -ConfigPath .\config\lab-erreur.json -InitialPassword $password

# Après lecture de l'erreur, relancer la commande normale, sans -ConfigPath lab-erreur.json.
```

Le pilote précontrôle les deux sessions avant de déployer ; cette panne doit donc empêcher le début des créations. Pour reprendre, revenir au vrai JSON. Il n'est pas nécessaire de désactiver le pare-feu, de promouvoir un nouveau domaine ou de supprimer l'OU.

## Adaptation courte, niveau Bac +3

Tous réalisent la même adaptation : **ajouter Gabriel Moreau, compte `tp.gabriel`, au service IT**, dans une copie du CSV initial. Conserver les six lignes d'origine. Au premier passage de cette copie, le rapport doit indiquer Created=1 et Existing=6 ; au deuxième, Created=0 et Existing=7. Les quatre groupes et les deux partages restent les mêmes.

Le [CSV à sept personnes](../donnees/utilisateurs-avec-gabriel.csv) est fourni comme correction. Construisez d'abord votre copie en ajoutant la ligne ci-dessous à la fin de `utilisateurs.csv`, puis comparez avec le fichier fourni :

```csv
tp.gabriel;Gabriel;Moreau;IT
```

Le premier champ est l'identifiant, les deux suivants sont le prénom et le nom, et IT est le service autorisé. Aucun mot de passe ne figure dans le CSV.

```powershell
# ADMIN : déployer le CSV enrichi ; la boucle retrouve les six comptes existants.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password `
    -CsvPath .\donnees\utilisateurs-avec-gabriel.csv

# Lire le nouveau bilan : une création, six comptes conservés, deux partages.
Get-Content .\resultats\deploiement.json -Raw | ConvertFrom-Json

# Rejouer avec les sept mêmes personnes : aucune nouvelle création cette fois.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password `
    -CsvPath .\donnees\utilisateurs-avec-gabriel.csv
```

Sur le DC, vérifier l'appartenance réelle :

```powershell
# DC01 : afficher les membres directs du groupe global IT après l'ajout du septième compte.
# Attendu : Alice, Bruno, Farid et Gabriel ; aucune modification de l'ACL n'est nécessaire.
Import-Module ActiveDirectory
Get-ADGroupMember GG_TP_IT
```

Depuis ADMIN, dans la console administrative d'origine de l'étape 04 :

```powershell
# $netbios contient le nom court réellement lu sur DC01 lors de l'étape des partages.
# Ouvrir une nouvelle console dont les accès réseau utilisent Gabriel, compte ordinaire.
runas /netonly "/user:$netbios\tp.gabriel" "powershell.exe -NoProfile"
```

Dans la **nouvelle console de Gabriel** :

```powershell
# Le script reste local à ADMIN ; ses tentatives d'accès vont vers les partages de SRV01.
Set-Location C:\TP-PowerShell

# Attendu : lecture/écriture dans IT, refus dans RH et Passed = True sur les deux lignes.
.\scripts\05-Test-Access.ps1 -ExpectedService IT | Format-List
```

Ce test prouve que la donnée supplémentaire a produit un compte et un accès fonctionnels, sans recopier un bloc de création.

L'enrichissement de l'inventaire de l'étape 02 est également commun à tous : ajouter la propriété LastBootUpTime. Les objectifs et la grille restent identiques pour l'ensemble de la classe.

## Démonstration devant l'enseignant : 8 à 10 min

1. **Contexte, 1 min :** montrer les noms des serveurs et le domaine learn-it.local.
2. **Déploiement, 2 min :** lancer le pilote ; lire le rapport récent ; montrer les comptes/groupes et les deux partages. Si tout est déjà présent, conserver cet état et expliquer Existing.
3. **Relance, 1 min :** rejouer et montrer zéro nouveau compte, puis vérifier le résultat présent.
4. **Droits, 2 min :** Alice IT oui/RH non ; Chloé RH oui/IT non, dans leurs consoles réseau séparées.
5. **Erreur et adaptation, 2 min :** montrer les deux erreurs préparées (CSV invalide et cible inaccessible), puis la création et les accès de Gabriel.
6. **Explication individuelle, 1 à 2 min :** chaque membre explique une partie choisie du script et la cause d'un résultat.

Une maquette qui démarre mais dont les droits n'ont jamais été testés n'est pas une démonstration complète. Les scripts peuvent être ceux de la correction : vous devez comprendre leur rôle et leurs limites.

## Remise minimale

- Scripts utilisés et fichiers JSON/CSV utilisés, sans secret.
- Résultats de déploiement/inventaire et quelques extraits d'erreur.
- Un [bilan court](../BILAN.md) : état final, tests, une erreur résolue, usage de l'IA et limite identifiée.

Le cœur de l'évaluation est le **fonctionnement en direct**. Le bilan aide à garder une trace ; il ne remplace pas la maquette.
