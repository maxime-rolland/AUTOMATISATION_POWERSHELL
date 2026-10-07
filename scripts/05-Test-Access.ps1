#Requires -Version 5.1
<#
.SYNOPSIS
    Vérifier l'accès SMB avec l'identité réseau de la console courante.
.DESCRIPTION
    Lancer dans une console runas /netonly de tp.alice ou tp.chloe.
    Le script N'UTILISE PAS une session WinRM administrateur pour tester les droits.
    Il tente de lire puis d'écrire dans chaque partage, et compare au service attendu.
    Ne pas l'appeler dans une console Domain Admin pour évaluer un salarié.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExpectedService,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
$config = Read-LabConfig $ConfigPath
if ($ExpectedService -cnotin $config.Services) {throw 'Service attendu inconnu.'}

# Tester tous les services, pas seulement celui autorisé : il faut aussi prouver le refus.
foreach ($service in $config.Services) {
    $root = '\\' + $config.FileServer + '\TP_' + $service + '$'
    $allowed = ($service -eq $ExpectedService)
    $file = Join-Path $root ('preuve-' + [guid]::NewGuid().ToString('N') + '.txt')
    $canList = $false; $canWrite = $false; $listError=''; $writeError=''
    try {
        # Un dossier vide peut être lisible sans renvoyer d'objet : le succès de la commande compte.
        Get-ChildItem -LiteralPath $root -ErrorAction Stop | Out-Null
        $canList = $true
    } catch {$listError = $_.Exception.Message}
    try {
        Set-Content -LiteralPath $file -Value 'Preuve fictive du TP automatisation' -Encoding UTF8 -ErrorAction Stop
        $canWrite = $true
    } catch {$writeError = $_.Exception.Message}
    finally {
        # Nettoyer uniquement le fichier GUID créé par CET essai ; aucune suppression globale.
        if ($canWrite) {Remove-Item -LiteralPath $file -ErrorAction Stop}
    }
    # Les booléens rendent le résultat comparable au contrat ; garder aussi les vraies erreurs.
    [pscustomobject]@{
        Service=$service;ExpectedAccess=$allowed;CanList=$canList;CanWrite=$canWrite
        Passed=($canList -eq $allowed -and $canWrite -eq $allowed)
        ListError=$listError;WriteError=$writeError
    }
}
# Un refus n'est une preuve d'ACL que si le même serveur est joignable et que l'accès
# au partage autorisé fonctionne avec cette identité. Lire les quatre résultats ensemble.
