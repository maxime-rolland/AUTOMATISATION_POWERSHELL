#Requires -Version 5.1
<#
.SYNOPSIS
    Fonctions communes au TP : lire la configuration et valider les données.
.DESCRIPTION
    Ce fichier ne crée ni utilisateur, ni groupe, ni dossier.
    Il est chargé par « dot sourcing » : . "$PSScriptRoot\Lab.Common.ps1"
    Le point suivi d'un espace importe les fonctions dans le script appelant.
    L'objectif est de séparer la validation des données des opérations Windows.
#>

function Read-LabConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    # Une erreur de lecture doit interrompre le traitement, pas produire un objet vide.
    $config = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json

    # Le TP cible le domaine donné par l'enseignant. Il ne crée aucune forêt.
    if ($config.DomainName -ne 'learn-it.local') {
        throw 'Ce TP doit être exécuté dans learn-it.local.'
    }

    # Les FQDN permettent l'authentification Kerberos ; on refuse les IP ici.
    foreach ($name in @($config.DomainController, $config.FileServer)) {
        if ($name -notmatch '^[a-zA-Z0-9-]+\.learn-it\.local$') {
            throw "FQDN invalide dans la configuration : $name"
        }
    }
    if ($config.DomainController -eq $config.FileServer) {
        throw 'Le contrôleur de domaine et le serveur de fichiers doivent être distincts.'
    }

    # Une liste contrôlée évite d'utiliser des données libres pour fabriquer les noms AD.
    $services = @($config.Services)
    if ($services.Count -eq 0 -or @($services | Select-Object -Unique).Count -ne $services.Count) {
        throw 'La liste Services doit être non vide et sans doublon.'
    }
    foreach ($service in $services) {
        if ($service -cnotmatch '^[A-Z]{2,12}$') {throw "Service invalide : $service"}
    }

    # B01, B02... évitent les collisions entre binômes partageant le même domaine.
    if ($config.LabId -cnotmatch '^B[0-9]{2}$') {throw 'LabId doit être B suivi de deux chiffres.'}

    # Les ACL seront remplacées sur les dossiers de ce chemin : on borne le périmètre.
    if ($config.DataRoot -ne 'C:\TP-Automatisation\Partages') {
        throw 'DataRoot doit rester C:\TP-Automatisation\Partages pour cette correction.'
    }

    # TryParse valide une IPv4 sans déclencher de modification du réseau.
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse([string]$config.AdminIPAddress, [ref]$ip) -or
        $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'AdminIPAddress doit être une IPv4 valide.'
    }

    # Retourner l'objet, pas une chaîne ou une mise en forme : il reste exploitable.
    return $config
}

function Read-ValidatedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$AllowedServices,
        [Parameter(Mandatory)][string]$AccountPrefix
    )

    # @() conserve un tableau même si le CSV ne contient qu'une personne.
    # UTF8 et ';' correspondent au format du fichier fourni dans le dépôt.
    $rows = @(Import-Csv -LiteralPath $Path -Delimiter ';' -Encoding UTF8 -ErrorAction Stop)
    if ($rows.Count -eq 0) {throw 'Le CSV ne contient aucune personne.'}

    # Refuser une colonne renommée évite de lire silencieusement une propriété vide.
    $expected = @('SamAccountName','Prenom','Nom','Service')
    $actual = @($rows[0].PSObject.Properties.Name)
    if (@(Compare-Object $expected $actual).Count -gt 0) {throw 'En-têtes du CSV incorrects.'}

    # Une table de hachage PowerShell est insensible à la casse pour ces clés.
    # tp.b01.alice et TP.B01.ALICE seront donc reconnus comme le même identifiant.
    $seen = @{}
    $errors = New-Object 'System.Collections.Generic.List[string]'

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $sam = [string]$row.SamAccountName # Une cellule absente devient une chaîne vide à valider.
        $line = $i + 2 # Ligne 1 = en-têtes ; le premier salarié est à la ligne 2.

        # Règle du TP : préfixe du binôme, minuscules, maximum 20 caractères au total.
        if ($sam -cnotmatch '^tp\.[a-z][a-z0-9.]{0,16}$') {
            $errors.Add("Ligne ${line} : SamAccountName invalide.")
        }
        if (-not $sam.StartsWith($AccountPrefix, [System.StringComparison]::Ordinal)) {
            $errors.Add("Ligne ${line} : préfixe attendu $AccountPrefix")
        }
        if ($seen.ContainsKey($sam)) {
            $errors.Add("Ligne ${line} : identifiant en double.")
        } else {
            $seen[$sam] = $true
        }
        if ([string]::IsNullOrWhiteSpace($row.Prenom) -or [string]::IsNullOrWhiteSpace($row.Nom)) {
            $errors.Add("Ligne ${line} : prénom ou nom manquant.")
        }
        if ($row.Service -cnotin $AllowedServices) {
            $errors.Add("Ligne ${line} : service non prévu dans lab.json.")
        }
    }

    # Important : toutes les lignes ont été lues AVANT les créations AD.
    # Une erreur de CSV entraîne un refus global, même si les premières lignes étaient valides.
    if ($errors.Count -gt 0) {throw ($errors -join [Environment]::NewLine)}
    return $rows
}
