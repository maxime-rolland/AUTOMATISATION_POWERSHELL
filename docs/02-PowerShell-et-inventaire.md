# 02 — Comprendre PowerShell et faire un inventaire

[Accueil](../README.md) · [Maquette](01-Maquette-et-demarrage.md) · [Étape suivante](03-Automatiser-AD.md)

**Travail sur le poste ADMIN. Correction : [01-Get-Inventory.ps1](../scripts/01-Get-Inventory.ps1).**

Ouvrez Windows PowerShell 5.1 sur ADMIN et placez-vous dans `C:\TP-PowerShell`, comme à la fin de l'étape 01. Exécutez les exemples dans cette même console ; les blocs suivants réutilisent les variables définies plus haut. Les sessions `$s` et `$session` sont des connexions vers les serveurs, pas de nouvelles consoles locales.

## Ce que vous allez construire

Un script contacte les deux serveurs, relève leur OS, leur domaine et leur espace disque, puis produit un CSV. Une cible inaccessible doit apparaître en ECHEC sans faire disparaître les résultats des cibles qui répondent. Cette activité prépare les mêmes connexions que le pilote de déploiement utilisera ensuite. La correction fournie inclut aussi LastBootUpTime, l'enrichissement commun demandé plus bas.

## Une commande renvoie des objets

```powershell
# ADMIN : afficher les services du poste local ; rien n'est exécuté à distance ici.
Get-Service

# Découvrir les propriétés/méthodes des objets ServiceController renvoyés.
Get-Service | Get-Member

# Garder les services actifs, choisir deux propriétés, puis trier par nom.
# Le caractère | transmet les objets à la commande suivante.
Get-Service | Where-Object Status -eq Running |
    Select-Object Name,Status | Sort-Object Name
```

`Get-Service` renvoie des objets services. `Get-Member` décrit leur type, leurs propriétés et leurs méthodes. Le pipeline transmet ces objets, pas seulement les lignes affichées dans le terminal. `Where-Object` sélectionne les objets dont Status vaut Running ; `Select-Object` choisit les propriétés ; `Sort-Object` classe les résultats.

Pour conserver les données :

```powershell
# Créer le dossier local des rapports ; -Force permet de rejouer s'il existe déjà.
New-Item .\resultats -ItemType Directory -Force

# Exporter les données brutes, avec un séparateur commun au TP et les accents UTF-8.
# Ne pas insérer Format-Table avant Export-Csv : il transformerait les objets.
Get-Service | Select-Object Name,Status |
    Export-Csv .\resultats\services.csv -NoTypeInformation -Delimiter ';' -Encoding UTF8

# Relire le fichier produit : on récupère un objet par ligne, avec Name et Status.
Import-Csv .\resultats\services.csv -Delimiter ';' -Encoding UTF8
```

`Format-Table` sert à l'affichage final. Si vous le placez avant `Export-Csv`, vous exportez des objets de mise en forme plutôt que les services. Faites l'essai dans un autre fichier et comparez : comprendre cette erreur évite de produire des rapports inexploités.

## Variables et données de configuration

```powershell
# Transformer le JSON en objet et le conserver dans une variable locale à ADMIN.
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json

# Lire deux propriétés de l'objet : le domaine et la liste IT/RH.
$config.DomainName
$config.Services

# Construire un tableau de deux destinations, puis parcourir chacune sans dupliquer le code.
$servers = @($config.DomainController, $config.FileServer)
foreach ($server in $servers) {
    # Les guillemets remplacent $server par sa valeur dans la chaîne affichée.
    "Cible : $server"
}
```

Une variable stocke une valeur ou un objet. Le JSON devient un objet dont on peut lire les propriétés. `@(...)` force une collection, même avec une seule entrée. `foreach` applique le même traitement à chaque élément. Les guillemets développent `$server` ; les apostrophes garderaient la chaîne littérale. Utiliser `$($config.DomainName)` pour développer une propriété à l'intérieur d'une chaîne.

## Fonction et script paramétré

```powershell
# Définir une fonction réutilisable ; la définition seule ne lance aucune lecture disque.
function Get-FreeDisk {
    # Activer les paramètres communs tels que -Verbose.
    [CmdletBinding()]
    # Permettre un autre lecteur ; sans argument, le lecteur demandé est C:.
    param([string]$Drive = 'C:')

    # Lire le disque LOCAL correspondant ; le filtre évite de récupérer tous les lecteurs.
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"

    # Renvoyer un objet exploitable dans un CSV, avec l'espace libre arrondi en Go binaires.
    [pscustomobject]@{
        Drive = $Drive
        FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    }
}

# Appeler la fonction : c'est seulement maintenant que la lecture CIM a lieu.
Get-FreeDisk
```

`param` décrit ce que l'appelant peut fournir. Ici, Drive vaut C: si l'on ne précise rien. CIM lit les informations Windows de manière structurée. `1GB` est une constante binaire ; Round rend l'affichage lisible. L'objet personnalisé contient les propriétés que vous avez choisies. La fonction ne doit pas terminer par `Format-Table`, car l'appelant pourrait vouloir du JSON ou un CSV.

Une table de hachage `@{...}` représente des paires clé/valeur. Elle pourra aussi fournir les paramètres d'un cmdlet avec le splatting, par exemple `New-ADUser @parameters` dans l'étape AD.

## Session distante : préciser le lieu d'exécution

```powershell
# ADMIN : saisir le compte qui a les droits d'administration sur les deux cibles.
$admin = Get-Credential -Message 'Administration du laboratoire'

# Ouvrir une connexion WinRM vers SRV01 avec Kerberos et le moteur Windows PowerShell.
# $config provient du bloc précédent ; le nom DNS est utilisé, pas l'IP.
$s = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos `
    -ConfigurationName Microsoft.PowerShell -Credential $admin

# Le bloc entre accolades s'exécute SUR SRV01, et non sur ADMIN.
Invoke-Command -Session $s {
    # Constater le lieu d'exécution : le nom renvoyé doit être celui du serveur.
    hostname
    # Lire le nom et le domaine de ce serveur.
    Get-CimInstance Win32_ComputerSystem | Select-Object Name,Domain
}

# ADMIN : fermer la connexion quand les commandes sont terminées.
Remove-PSSession $s
```

La session s'ouvre vers le serveur. Le bloc entre accolades s'exécute **sur ce serveur** ; son hostname doit donc être celui de la cible. `$config` appartient au poste appelant, pas automatiquement à la session distante. Pour transmettre un paramètre, utiliser ArgumentList et param :

```powershell
# ADMIN : ouvrir une nouvelle session, la précédente ayant été fermée.
$s = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos -Credential $admin

# Transmettre la valeur C: au bloc distant ; param la reçoit dans $drive sur SRV01.
Invoke-Command -Session $s -ArgumentList 'C:' {
    param($drive)
    # Le lecteur est lu sur le serveur ; la variable locale $config n'est pas utilisée ici.
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
}

# Libérer la session après réception du résultat.
Remove-PSSession $s
```

Une sortie distante ajoute des propriétés comme PSComputerName et peut être désérialisée. Sélectionner explicitement les propriétés du rapport avant l'export ; exécuter les actions sur la cible plutôt que tenter d'appeler localement une méthode perdue.

## Erreurs et fermeture des ressources

```powershell
# Initialiser la variable : si la connexion échoue, aucune session ne sera à fermer.
$session = $null
try {
    # -ErrorAction Stop transforme une erreur en interruption traitable par catch.
    $session = New-PSSession -ComputerName $config.FileServer `
        -Authentication Kerberos -Credential $admin -ErrorAction Stop
    # Interroger le service WinRM sur la cible ; renvoyer l'erreur réelle s'il y en a une.
    Invoke-Command -Session $session {Get-Service WinRM} -ErrorAction Stop
} catch {
    # Construire un résultat d'échec lisible, en gardant le message de l'exception.
    [pscustomobject]@{State='ECHEC';Error=$_.Exception.Message}
} finally {
    # Ce bloc est exécuté après succès ou erreur ; fermer seulement une session créée.
    if ($session) {Remove-PSSession $session}
}
```

`try` contient l'opération tentée ; `catch` traite l'erreur terminante ; `finally` s'exécute aussi après une erreur. Beaucoup de cmdlets émettent une erreur non terminante par défaut : `-ErrorAction Stop` ou `$ErrorActionPreference='Stop'` rend le traitement cohérent avec catch. La fermeture de session évite de laisser des connexions ouvertes après plusieurs essais.

## Travail demandé

1. Reproduire les petits exemples et expliquer le résultat de chacun.
2. Écrire votre inventaire, ou partir du corrigé pour en expliquer puis adapter chaque bloc. Conserver les mêmes colonnes pour tous les résultats.
3. Exécuter le script corrigé avec votre credential ; lire le CSV en le réimportant.
4. Ajouter une cible fictive au paramètre ComputerName. Les deux serveurs réels doivent rester en OK et la cible absente doit être en ECHEC.
5. Ajouter la propriété LastBootUpTime, puis l'inclure dans la projection et l'export. Vérifier le résultat, pas seulement l'absence d'erreur.

```powershell
# ADMIN : inventorier les deux serveurs définis dans lab.json ; $admin a été saisi plus haut.
.\scripts\01-Get-Inventory.ps1 -Credential $admin

# Ajouter une cible absente pour tester catch, sans arrêter l'inventaire des vraies cibles.
# Le fichier distinct conserve le rapport du premier essai.
.\scripts\01-Get-Inventory.ps1 -Credential $admin `
    -ComputerName $config.DomainController,$config.FileServer,'absent.learn-it.local' `
    -OutPath .\resultats\inventaire-erreur.csv

# Vérifier deux lignes OK et une ligne ECHEC portant le message réel de connexion.
Import-Csv .\resultats\inventaire-erreur.csv -Delimiter ';' -Encoding UTF8
```

Le DNS/WinRM peut mettre un certain temps à échouer sur la cible fictive ; conserver l'erreur réelle plutôt que fabriquer un résultat.

## Correction de l'enrichissement commun : dernier démarrage

La date est une propriété de l'objet `$os` lu **sur le serveur**, dans le bloc distant. Dans votre script, ajoutez `LastBootUpTime = $os.LastBootUpTime.ToString('o')` à l'objet de succès. Le format `o` produit une date ISO 8601 lisible et exploitable ; il évite qu'une présentation propre à la langue de Windows change la forme du rapport.

Ajoutez également `LastBootUpTime=''` à l'objet du `catch` : une cible inaccessible conserve la même structure, avec une date inconnue. Enfin, ajoutez la propriété à `Select-Object` juste avant `Export-Csv`. Si vous ne changez que l'objet distant, la projection finale retire la nouvelle propriété et le CSV ne la contient pas.

```powershell
# ADMIN : lancer votre inventaire enrichi et produire un rapport distinct.
# La correction 01-Get-Inventory.ps1 contient déjà les trois modifications expliquées ci-dessus.
.\scripts\01-Get-Inventory.ps1 -Credential $admin -OutPath .\resultats\inventaire-enrichi.csv

# Réimporter le vrai fichier, plutôt que se limiter à l'affichage du script.
# Attendu : une date de démarrage pour chaque serveur joignable, et State = OK.
Import-Csv .\resultats\inventaire-enrichi.csv -Delimiter ';' -Encoding UTF8 |
    Select-Object Machine,LastBootUpTime,State
```

## Lire la correction

| Bloc du script | Pourquoi il existe |
|---|---|
| param et valeurs par défaut | Réutiliser le script sans éditer ses commandes |
| Read-LabConfig | Vérifier le domaine et lire les destinations |
| foreach | Traiter toutes les cibles avec le même algorithme |
| Invoke-Command et CIM | Lire le vrai serveur, pas le poste ADMIN |
| objet ECHEC dans catch | Garder une trace de la cible qui ne répond pas |
| finally | Fermer la session créée dans cette itération |
| Select-Object puis Export-Csv | Produire des données et retirer les propriétés de remoting |

**Preuve à conserver :** inventaire réel, inventaire avec une erreur et une courte explication du lieu d'exécution de chaque partie. Vous devez pouvoir montrer où ajouter une propriété et pourquoi elle apparaît dans le rapport.
