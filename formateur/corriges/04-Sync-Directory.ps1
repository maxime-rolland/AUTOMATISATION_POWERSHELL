#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<# Creation additive: ne supprime rien et ne remet pas les mots de passe existants a zero. #>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$CsvPath,
      [securestring]$InitialPassword)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.Common.psm1') -Force
$rows=@(Test-LabCsv $CsvPath) # Validation integrale AVANT toute mutation AD
if ((Get-ADDomain).DNSRoot -ne 'campus.test') {throw 'Domaine de TP attendu.'}
if (-not $WhatIfPreference -and -not $InitialPassword) {throw 'Fournir un mot de passe temporaire securise.'}
$base='DC=campus,DC=test';$lab="OU=PSLAB,$base"
$ous=@(@{Name='PSLAB';Path=$base},@{Name='Utilisateurs';Path=$lab},@{Name='Groupes';Path=$lab},@{Name='Serveurs';Path=$lab})
foreach ($ou in $ous) {
    $dn="OU=$($ou.Name),$($ou.Path)"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'")) {
        if ($PSCmdlet.ShouldProcess($dn,'Creer OU protegee')) {New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -ProtectedFromAccidentalDeletion $true}
    }
}
foreach ($dep in @('IT','RH','Direction')) {
    foreach ($g in @(@{Name="GG_$dep";Scope='Global'},@{Name="DL_${dep}_M";Scope='DomainLocal'})) {
        $existing=Get-ADGroup -Filter "SamAccountName -eq '$($g.Name)'"
        if ($existing -and ($existing.DistinguishedName -notlike "*,OU=Groupes,$lab" -or $existing.GroupScope -ne $g.Scope)) {throw "Collision groupe $($g.Name)."}
        if (-not $existing -and $PSCmdlet.ShouldProcess($g.Name,'Creer groupe de securite')) {
            New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope $g.Scope -GroupCategory Security -Path "OU=Groupes,$lab"
        }
    }
    if ($WhatIfPreference) {Write-Output "PREVU: GG_$dep dans DL_${dep}_M"} else {
        $members=@(Get-ADGroupMember "DL_${dep}_M" | Select-Object -ExpandProperty SamAccountName)
        if ("GG_$dep" -notin $members -and $PSCmdlet.ShouldProcess("DL_${dep}_M","Ajouter GG_$dep")) {Add-ADGroupMember "DL_${dep}_M" -Members "GG_$dep"}
    }
}
foreach ($r in $rows) {
    $user=Get-ADUser -Filter "SamAccountName -eq '$($r.SamAccountName)'" -Properties Department
    $state='Existant'
    if ($user -and ($user.DistinguishedName -notlike "*,OU=Utilisateurs,$lab" -or $user.Department -ne $r.Department)) {throw "Collision/derive pour $($r.SamAccountName): intervention manuelle."}
    if (-not $user -and $PSCmdlet.ShouldProcess($r.SamAccountName,'Creer utilisateur')) {
        New-ADUser -Name "$($r.GivenName) $($r.Surname)" -SamAccountName $r.SamAccountName `
            -UserPrincipalName "$($r.SamAccountName)@campus.test" -GivenName $r.GivenName -Surname $r.Surname `
            -Department $r.Department -Path "OU=Utilisateurs,$lab" -AccountPassword $InitialPassword `
            -Enabled $true -ChangePasswordAtLogon $true
        $state='Cree'
    }
    if ($WhatIfPreference) {$state='Planifie'} else {
        $members=@(Get-ADGroupMember "GG_$($r.Department)" | Select-Object -ExpandProperty SamAccountName)
        if ($r.SamAccountName -notin $members -and $PSCmdlet.ShouldProcess($r.SamAccountName,'Ajouter groupe service')) {
            Add-ADGroupMember "GG_$($r.Department)" -Members $r.SamAccountName
        }
    }
    [pscustomobject]@{SamAccountName=$r.SamAccountName;Department=$r.Department;Etat=$state}
}
