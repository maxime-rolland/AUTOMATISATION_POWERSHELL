#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Créer les dossiers et partages métiers sur le serveur de fichiers du TP.
.DESCRIPTION
    Le domaine et le nom du serveur sont vérifiés avant toute écriture.
    Le chemin C:\TP-Automatisation\Partages est réservé aux données fictives du TP.
    Ce script remplace les ACL des dossiers racines métiers, pas celles d'un serveur réel.
    Exécuter après 02-Sync-AD.ps1 : les groupes doivent exister pour obtenir leur SID.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]{1,15}$')][string]$NetBIOSName
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
$config = Read-LabConfig $ConfigPath
$system = Get-CimInstance Win32_ComputerSystem
if ($system.Domain -ne $config.DomainName -or $system.DomainRole -ge 4) {
    throw 'Le serveur de fichiers doit être un membre de learn-it.local, pas un contrôleur.'
}
if ($env:COMPUTERNAME -ne $config.FileServer.Split('.')[0]) {throw 'Mauvaise machine cible.'}

# Le pilote a lu le vrai NetBIOS sur le DC et le transmet comme paramètre.
# On évite de supposer qu'il vaut LEARN-IT simplement à partir du nom DNS.
$netbios = $NetBIOSName

# Tout résoudre avant les créations limite les modifications partielles si un groupe manque.
$plans = foreach ($service in $config.Services) {
    $account = "$netbios\DL_TP_$($config.LabId)_${service}_M"
    $sid = ([System.Security.Principal.NTAccount]$account).Translate([System.Security.Principal.SecurityIdentifier])
    $path = Join-Path (Join-Path $config.DataRoot $config.LabId) $service
    $shareName = 'TP_' + $config.LabId + '_' + $service + '$'
    $existing = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
    if ($existing -and $existing.Path -ne $path) {throw "Le partage $shareName pointe ailleurs."}
    [pscustomobject]@{Service=$service;Account=$account;SID=$sid.Value;Path=$path;Share=$shareName}
}

foreach ($plan in $plans) {
    if ($PSCmdlet.ShouldProcess($plan.Path, 'Créer dossier et appliquer les droits du TP')) {
        New-Item -Path $plan.Path -ItemType Directory -Force | Out-Null

        # Construire une nouvelle ACL évite d'accumuler les mêmes ACE à chaque relance.
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false) # Retirer l'héritage du parent du dossier métier.

        # SID universels : SYSTEM et Administrateurs, quelle que soit la langue Windows.
        $rules = @(
            @{SID='S-1-5-18';Rights='FullControl'},
            @{SID='S-1-5-32-544';Rights='FullControl'},
            @{SID=$plan.SID;Rights='Modify'}
        )
        foreach ($rule in $rules) {
            $id = [System.Security.Principal.SecurityIdentifier]$rule.SID
            $ace = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $id, $rule.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow'
            )
            $acl.AddAccessRule($ace)
        }
        # Modify permet créer/modifier/supprimer les fichiers, pas changer les permissions.
        Set-Acl -LiteralPath $plan.Path -AclObject $acl

        $share = Get-SmbShare -Name $plan.Share -ErrorAction SilentlyContinue
        if (-not $share) {
            New-SmbShare -Name $plan.Share -Path $plan.Path -ChangeAccess $plan.Account `
                -EncryptData $true | Out-Null
        }

        # Converger la liste SMB vers le seul groupe attendu, y compris après une dérive.
        foreach ($entry in @(Get-SmbShareAccess -Name $plan.Share)) {
            if ($entry.AccessControlType -eq 'Deny') {
                Unblock-SmbShareAccess -Name $plan.Share -AccountName $entry.AccountName -Force | Out-Null
            } else {
                Revoke-SmbShareAccess -Name $plan.Share -AccountName $entry.AccountName -Force | Out-Null
            }
        }
        Grant-SmbShareAccess -Name $plan.Share -AccountName $plan.Account -AccessRight Change -Force | Out-Null
        Set-SmbShare -Name $plan.Share -EncryptData $true -Force
    }
    [pscustomobject]@{Service=$plan.Service;Share=$plan.Share;Path=$plan.Path;Group=$plan.Account}
}

$ruleName = 'TP-Auto-SMB-' + $config.LabId
if ($PSCmdlet.ShouldProcess($ruleName, 'Autoriser SMB depuis le poste de test')) {
    # Les règles SMB Windows générales sont retirées sur ce serveur DÉDIÉ au TP.
    # Cela ne constitue pas une politique globale : d'autres règles/GPO peuvent autoriser 445.
    Get-NetFirewallRule -Name 'FPS-SMB-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $ruleName -DisplayName "TP automatisation SMB $($config.LabId)" `
            -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress $config.AdminIPAddress `
            -Action Allow | Out-Null
    } else {
        Set-NetFirewallRule -Name $ruleName -RemoteAddress $config.AdminIPAddress -Enabled True
    }
}
