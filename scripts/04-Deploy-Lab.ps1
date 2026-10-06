#Requires -Version 5.1
<#
.SYNOPSIS
    Piloter l'automatisation complète depuis le poste d'administration.
.DESCRIPTION
    Une seule commande pour enchaîner AD puis les partages, sans copier à la main.
    L'administrateur fournit sa credential et le secret temporaire des comptes fictifs.
    Les connexions sont directes : poste -> DC, puis poste -> serveur de fichiers.
    Il n'y a pas de lecture de partage tiers depuis une session distante (second saut).
.EXAMPLE
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password
.EXAMPLE
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][pscredential]$Credential,
    [securestring]$InitialPassword,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.json'),
    [string]$CsvPath = (Join-Path $PSScriptRoot '..\donnees\utilisateurs.csv'),
    [string]$ResultPath = (Join-Path $PSScriptRoot '..\resultats')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
$config = Read-LabConfig $ConfigPath

# Validation LOCALE intégrale avant toute copie, OU, groupe ou compte créé.
$prefix = 'tp.' + $config.LabId.ToLowerInvariant() + '.'
$users = @(Read-ValidatedUsers -Path $CsvPath -AllowedServices $config.Services -AccountPrefix $prefix)
if (-not $WhatIfPreference -and -not $InitialPassword) {throw 'Fournir InitialPassword en SecureString.'}

$dcSession = $null
$fileSession = $null
$remotePath = "C:\TP-Automatisation\scripts\$($config.LabId)"
try {
    # Les deux connexions et leurs contextes sont validés avant le déploiement.
    $dcSession = New-PSSession -ComputerName $config.DomainController -Credential $Credential `
        -Authentication Kerberos -ConfigurationName Microsoft.PowerShell
    $fileSession = New-PSSession -ComputerName $config.FileServer -Credential $Credential `
        -Authentication Kerberos -ConfigurationName Microsoft.PowerShell
    $domain = Invoke-Command -Session $dcSession {
        Import-Module ActiveDirectory
        Get-ADDomain | Select-Object DNSRoot,NetBIOSName
    }
    $fileContext = Invoke-Command -Session $fileSession {Get-CimInstance Win32_ComputerSystem | Select-Object Domain,DomainRole}
    if ($domain.DNSRoot -ne $config.DomainName -or $fileContext.Domain -ne $config.DomainName -or $fileContext.DomainRole -ge 4) {
        throw 'La maquette ne correspond pas au domaine et aux rôles attendus.'
    }

    # Le dry run teste la configuration, le CSV et les connexions ; il ne copie rien.
    # Ce plan ne certifie pas que les droits d'écriture réels seront suffisants.
    if ($WhatIfPreference) {
        [pscustomobject]@{State='PLANIFIE';Domain=$domain.DNSRoot;Users=$users.Count;Services=@($config.Services).Count}
        return
    }
    if (-not $PSCmdlet.ShouldProcess($config.DomainName, 'Créer objets du TP et configurer les partages')) {return}

    foreach ($session in @($dcSession,$fileSession)) {
        Invoke-Command -Session $session -ArgumentList $remotePath {
            param($folder)
            # Seul le répertoire réservé aux scripts du TP est créé ici.
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
        # -ToSession pousse depuis le poste admin ; la cible n'utilise pas votre credential
        # pour aller récupérer un fichier sur un troisième système.
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Lab.Common.ps1') -Destination $remotePath -ToSession $session
        Copy-Item -LiteralPath $ConfigPath -Destination "$remotePath\lab.json" -ToSession $session
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '02-Sync-AD.ps1') -Destination $remotePath -ToSession $dcSession
    Copy-Item -LiteralPath $CsvPath -Destination "$remotePath\utilisateurs.csv" -ToSession $dcSession

    # ArgumentList transmet des objets : aucune commande texte contenant un secret.
    $adResults = Invoke-Command -Session $dcSession -ArgumentList $remotePath,$InitialPassword {
        param($folder,$password)
        & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" `
            -CsvPath "$folder\utilisateurs.csv" -InitialPassword $password
    }

    # Les groupes existent désormais. Le serveur peut résoudre leurs noms en SID.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '03-Sync-Shares.ps1') -Destination $remotePath -ToSession $fileSession
    $shareResults = Invoke-Command -Session $fileSession -ArgumentList $remotePath,$domain.NetBIOSName {
        param($folder,$netbios)
        & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios
    }

    # Sauvegarder des résultats lisibles localement ; aucun password n'est exporté.
    New-Item -Path $ResultPath -ItemType Directory -Force | Out-Null
    $adResults | Select-Object SamAccountName,Service,State |
        Export-Csv (Join-Path $ResultPath 'comptes.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
    $shareResults | Select-Object Service,Share,Path,Group |
        Export-Csv (Join-Path $ResultPath 'partages.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8
    $summary = [pscustomobject]@{
        State='OK';Domain=$domain.DNSRoot;Utc=(Get-Date).ToUniversalTime().ToString('o')
        Created=@($adResults | Where-Object State -eq 'CREE').Count
        Existing=@($adResults | Where-Object State -eq 'EXISTANT').Count
        Shares=@($shareResults).Count
    }
    $summary | ConvertTo-Json | Set-Content (Join-Path $ResultPath 'deploiement.json') -Encoding UTF8
    $summary
} catch {
    # On signale un échec réel. Des objets AD peuvent avoir été créés avant une panne.
    # On ne promet pas de transaction : rétablir la cause puis relancer le même jeu.
    throw "Automatisation interrompue : $($_.Exception.Message)"
} finally {
    if ($dcSession) {Remove-PSSession $dcSession}
    if ($fileSession) {Remove-PSSession $fileSession}
}
