# 02 — Comprendre PowerShell et faire un inventaire

[Accueil](../README.md) · [Maquette](01-Maquette-et-demarrage.md) · [Étape suivante](03-Automatiser-AD.md)

**Travail sur le poste ADMIN. Correction : [01-Get-Inventory.ps1](../scripts/01-Get-Inventory.ps1).**

## Ce que vous allez construire

Un script contacte les deux serveurs, relève leur OS, leur domaine et leur espace disque, puis produit un CSV. Une cible inaccessible doit apparaître en ECHEC sans faire disparaître les résultats des cibles qui répondent. Cette activité prépare les mêmes connexions que le pilote de déploiement utilisera ensuite.

## Une commande renvoie des objets

```powershell
Get-Service
Get-Service | Get-Member
Get-Service | Where-Object Status -eq Running |
    Select-Object Name,Status | Sort-Object Name
```

`Get-Service` renvoie des objets services. `Get-Member` décrit leur type, leurs propriétés et leurs méthodes. Le pipeline transmet ces objets, pas seulement les lignes affichées dans le terminal. `Where-Object` sélectionne les objets dont Status vaut Running ; `Select-Object` choisit les propriétés ; `Sort-Object` classe les résultats.

Pour conserver les données :

```powershell
New-Item .\resultats -ItemType Directory -Force
Get-Service | Select-Object Name,Status |
    Export-Csv .\resultats\services.csv -NoTypeInformation -Delimiter ';' -Encoding UTF8
Import-Csv .\resultats\services.csv -Delimiter ';' -Encoding UTF8
```

`Format-Table` sert à l'affichage final. Si vous le placez avant `Export-Csv`, vous exportez des objets de mise en forme plutôt que les services. Faites l'essai dans un autre fichier et comparez : comprendre cette erreur évite de produire des rapports inexploités.

## Variables et données de configuration

```powershell
$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$config.DomainName
$config.Services
$servers = @($config.DomainController, $config.FileServer)
foreach ($server in $servers) {"Cible : $server"}
```

Une variable stocke une valeur ou un objet. Le JSON devient un objet dont on peut lire les propriétés. `@(...)` force une collection, même avec une seule entrée. `foreach` applique le même traitement à chaque élément. Les guillemets développent `$server` ; les apostrophes garderaient la chaîne littérale. Utiliser `$($config.DomainName)` pour développer une propriété à l'intérieur d'une chaîne.

## Fonction et script paramétré

```powershell
function Get-FreeDisk {
    [CmdletBinding()]
    param([string]$Drive = 'C:')
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
    [pscustomobject]@{
        Drive = $Drive
        FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    }
}
Get-FreeDisk
```

`param` décrit ce que l'appelant peut fournir. Ici, Drive vaut C: si l'on ne précise rien. CIM lit les informations Windows de manière structurée. `1GB` est une constante binaire ; Round rend l'affichage lisible. L'objet personnalisé contient les propriétés que vous avez choisies. La fonction ne doit pas terminer par `Format-Table`, car l'appelant pourrait vouloir du JSON ou un CSV.

Une table de hachage `@{...}` représente des paires clé/valeur. Elle pourra aussi fournir les paramètres d'un cmdlet avec le splatting, par exemple `New-ADUser @parameters` dans l'étape AD.

## Session distante : préciser le lieu d'exécution

```powershell
$admin = Get-Credential -Message 'Administration du laboratoire'
$s = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos `
    -ConfigurationName Microsoft.PowerShell -Credential $admin
Invoke-Command -Session $s {
    hostname
    Get-CimInstance Win32_ComputerSystem | Select-Object Name,Domain
}
Remove-PSSession $s
```

La session s'ouvre vers le serveur. Le bloc entre accolades s'exécute **sur ce serveur** ; son hostname doit donc être celui de la cible. `$config` appartient au poste appelant, pas automatiquement à la session distante. Pour transmettre un paramètre, utiliser ArgumentList et param :

```powershell
$s = New-PSSession -ComputerName $config.FileServer -Authentication Kerberos -Credential $admin
Invoke-Command -Session $s -ArgumentList 'C:' {
    param($drive)
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
}
Remove-PSSession $s
```

Une sortie distante ajoute des propriétés comme PSComputerName et peut être désérialisée. Sélectionner explicitement les propriétés du rapport avant l'export ; exécuter les actions sur la cible plutôt que tenter d'appeler localement une méthode perdue.

## Erreurs et fermeture des ressources

```powershell
$session = $null
try {
    $session = New-PSSession -ComputerName $config.FileServer `
        -Authentication Kerberos -Credential $admin -ErrorAction Stop
    Invoke-Command -Session $session {Get-Service WinRM} -ErrorAction Stop
} catch {
    [pscustomobject]@{State='ECHEC';Error=$_.Exception.Message}
} finally {
    if ($session) {Remove-PSSession $session}
}
```

`try` contient l'opération tentée ; `catch` traite l'erreur terminante ; `finally` s'exécute aussi après une erreur. Beaucoup de cmdlets émettent une erreur non terminante par défaut : `-ErrorAction Stop` ou `$ErrorActionPreference='Stop'` rend le traitement cohérent avec catch. La fermeture de session évite de laisser des connexions ouvertes après plusieurs essais.

## Travail demandé

1. Reproduire les petits exemples et expliquer le résultat de chacun.
2. Écrire votre inventaire, ou partir du corrigé pour en expliquer puis adapter chaque bloc. Conserver les mêmes colonnes pour tous les résultats.
3. Exécuter le script corrigé avec votre credential ; lire le CSV en le réimportant.
4. Ajouter une cible fictive au paramètre ComputerName. Les deux serveurs réels doivent rester en OK et la cible absente doit être en ECHEC.
5. Ajouter une propriété utile, par exemple LastBootUpTime, puis l'inclure dans la projection et l'export. Vérifier le résultat, pas seulement l'absence d'erreur.

```powershell
.\scripts\01-Get-Inventory.ps1 -Credential $admin
.\scripts\01-Get-Inventory.ps1 -Credential $admin `
    -ComputerName $config.DomainController,$config.FileServer,'absent.learn-it.local' `
    -OutPath .\resultats\inventaire-erreur.csv
```

Le DNS/WinRM peut mettre un certain temps à échouer sur la cible fictive ; conserver l'erreur réelle plutôt que fabriquer un résultat.

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
