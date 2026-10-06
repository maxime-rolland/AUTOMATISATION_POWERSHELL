#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Créer les comptes et groupes du TP dans le domaine EXISTANT learn-it.local.
.DESCRIPTION
    Exécuter sur le contrôleur via WinRM ou dans sa console.
    Validation préalable ; créations additives ; aucune suppression d'utilisateur.
    Les comptes existants ne voient jamais leur mot de passe réinitialisé par ce script.
    Ce corrigé ne traite pas le changement de service d'une personne : il le signale.
.EXAMPLE
    .\02-Sync-AD.ps1 -ConfigPath C:\TP-Automatisation\scripts\lab.json `
        -CsvPath C:\TP-Automatisation\scripts\utilisateurs.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$CsvPath,
    [securestring]$InitialPassword
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
$config = Read-LabConfig $ConfigPath
$prefix = 'tp.' + $config.LabId.ToLowerInvariant() + '.'
$rows = @(Read-ValidatedUsers -Path $CsvPath -AllowedServices $config.Services -AccountPrefix $prefix)

# Lire le vrai domaine fournit son DN et son NetBIOS : on ne devine pas ces valeurs.
$domain = Get-ADDomain
if ($domain.DNSRoot -ne $config.DomainName) {throw 'Le serveur appartient à un autre domaine.'}
$labDN = "OU=TP-Automatisation-$($config.LabId),$($domain.DistinguishedName)"
$usersDN = "OU=Utilisateurs,$labDN"
$groupsDN = "OU=Groupes,$labDN"

# Précontrôle de toutes les collisions avant de créer les premières OU/groupes.
foreach ($row in $rows) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($row.SamAccountName)'" -Properties Department,Enabled
    if ($user -and ($user.DistinguishedName -notlike "*,$usersDN" -or $user.Department -ne $row.Service)) {
        throw "Compte $($row.SamAccountName) déjà présent hors du périmètre attendu ou service différent."
    }
    if ($user -and -not $user.Enabled) {
        throw "Compte $($row.SamAccountName) désactivé : diagnostiquer son état avant de relancer."
    }
}
foreach ($service in $config.Services) {
    foreach ($group in @(@{Name="GG_TP_$($config.LabId)_$service";Scope='Global'}, @{Name="DL_TP_$($config.LabId)_${service}_M";Scope='DomainLocal'})) {
        $existing = Get-ADGroup -Filter "SamAccountName -eq '$($group.Name)'"
        if ($existing -and ($existing.DistinguishedName -notlike "*,$groupsDN" -or
            $existing.GroupScope -ne $group.Scope -or $existing.GroupCategory -ne 'Security')) {
            throw "Collision avec le groupe $($group.Name)."
        }
    }
}
if (-not $WhatIfPreference -and -not $InitialPassword) {throw 'Fournir InitialPassword en SecureString.'}

# Une OU existe si son DN complet existe, pas simplement son nom d'affichage.
$ous = @(
    @{Name="TP-Automatisation-$($config.LabId)";Path=$domain.DistinguishedName},
    @{Name='Utilisateurs';Path=$labDN},
    @{Name='Groupes';Path=$labDN}
)
foreach ($ou in $ous) {
    $dn = "OU=$($ou.Name),$($ou.Path)"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'")) {
        if ($PSCmdlet.ShouldProcess($dn, 'Créer OU')) {
            New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -ProtectedFromAccidentalDeletion $true
        }
    }
}

# Un groupe global représente le service ; un DL représente l'accès au partage.
foreach ($service in $config.Services) {
    $global = "GG_TP_$($config.LabId)_$service"
    $local = "DL_TP_$($config.LabId)_${service}_M"
    foreach ($group in @(@{Name=$global;Scope='Global'}, @{Name=$local;Scope='DomainLocal'})) {
        if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($group.Name)'")) {
            if ($PSCmdlet.ShouldProcess($group.Name, 'Créer groupe de sécurité')) {
                New-ADGroup -Name $group.Name -SamAccountName $group.Name `
                    -GroupScope $group.Scope -GroupCategory Security -Path $groupsDN
            }
        }
    }
    if ($WhatIfPreference) {
        # Les groupes prévus ne sont pas forcément créés en dry run : ne pas les lire.
        Write-Verbose "Prévu : $global membre de $local"
    } else {
        $members = @(Get-ADGroupMember $local | Select-Object -ExpandProperty SamAccountName)
        if ($global -notin $members -and $PSCmdlet.ShouldProcess($local, "Ajouter $global")) {
            Add-ADGroupMember -Identity $local -Members $global
        }
    }
}

# Le résultat est un objet par personne. Une relance retrouve le même compte.
foreach ($row in $rows) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($row.SamAccountName)'"
    $state = 'EXISTANT'
    if (-not $user -and $PSCmdlet.ShouldProcess($row.SamAccountName, 'Créer compte du TP')) {
        # Le splatting rend les paramètres lisibles, sans construire une commande texte.
        $parameters = @{
            Name=$row.SamAccountName
            DisplayName="$($row.Prenom) $($row.Nom)"
            SamAccountName=$row.SamAccountName
            UserPrincipalName="$($row.SamAccountName)@$($domain.DNSRoot)"
            GivenName=$row.Prenom; Surname=$row.Nom; Department=$row.Service
            Path=$usersDN; AccountPassword=$InitialPassword; Enabled=$true
            ChangePasswordAtLogon=$false
            Description='Compte fictif du TP automatisation, à usage de laboratoire'
        }
        # Exception pédagogique : ces comptes fictifs peuvent faire les tests SMB tout de suite.
        # Le secret temporaire commun ne constitue pas une politique d'onboarding d'entreprise.
        New-ADUser @parameters
        $created = Get-ADUser -Identity $row.SamAccountName -Properties Enabled
        if (-not $created.Enabled) {throw "Création incomplète de $($row.SamAccountName) : vérifier la politique de mot de passe."}
        $state = 'CREE'
    }
    if ($WhatIfPreference) {$state = 'PLANIFIE'} else {
        $groupName = "GG_TP_$($config.LabId)_$($row.Service)"
        $members = @(Get-ADGroupMember $groupName | Select-Object -ExpandProperty SamAccountName)
        if ($row.SamAccountName -notin $members -and $PSCmdlet.ShouldProcess($groupName, "Ajouter $($row.SamAccountName)")) {
            Add-ADGroupMember -Identity $groupName -Members $row.SamAccountName
        }
    }
    [pscustomobject]@{SamAccountName=$row.SamAccountName;Service=$row.Service;State=$state}
}
