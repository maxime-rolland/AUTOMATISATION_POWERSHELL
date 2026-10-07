#Requires -Version 5.1
<#
.SYNOPSIS
    Recette enseignant : jouer le parcours corrigé du TP (étapes 01 à 05) depuis ADMIN.
.DESCRIPTION
    Lancé par « kvm/lab.sh recette » via l'agent QEMU, en SYSTEM, sur une maquette à l'état
    initial. Il enchaîne les commandes des supports : inventaire, appels séparés AD puis
    partages, tests métiers, pilote, relances, erreurs prévues et ajout de Gabriel.
    Différences assumées avec la séance : les credentials sont construits à partir des secrets
    transmis (l'étudiant utilise Get-Credential et Read-Host), et les tests métiers ouvrent une
    session réseau NEW_CREDENTIALS, le mécanisme de runas /netonly.
    La maquette est modifiée : revenir ensuite à l'instantané etat-initial (lab.sh restaurer).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AdminPassword,
    [Parameter(Mandatory)][string]$UserPassword,
    [string]$Root = 'C:\TP-PowerShell'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location -LiteralPath $Root

$checks = New-Object System.Collections.Generic.List[object]
function Test-Step {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Script)
    Write-Output "--- $Name"
    try {
        $detail = (& $Script | Out-String).Trim()
        $checks.Add([pscustomobject]@{Résultat = 'OK'; Contrôle = $Name; Détail = $detail})
    } catch {
        $checks.Add([pscustomobject]@{Résultat = 'ÉCHEC'; Contrôle = $Name; Détail = $_.Exception.Message})
    }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {throw $Message}
}

# Ouverture réseau sous une autre identité, comme runas /netonly : l'identité locale reste
# SYSTEM, mais les connexions SMB utilisent le compte métier.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LabNetOnly {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string password,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
function Invoke-NetOnly {
    param([string]$Domain, [string]$User, [string]$Password, [scriptblock]$ScriptBlock)
    $token = [IntPtr]::Zero
    # 9 = LOGON32_LOGON_NEW_CREDENTIALS ; 3 = LOGON32_PROVIDER_WINNT50.
    if (-not [LabNetOnly]::LogonUser($User, $Domain, $Password, 9, 3, [ref]$token)) {
        throw "LogonUser $Domain\$User : code $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    $context = [System.Security.Principal.WindowsIdentity]::Impersonate($token)
    try {& $ScriptBlock} finally {
        $context.Undo()
        [LabNetOnly]::CloseHandle($token) | Out-Null
    }
}

$config = Get-Content .\config\lab.json -Raw | ConvertFrom-Json
$admin = New-Object System.Management.Automation.PSCredential(
    "Administrator@$($config.DomainName)", (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))
$password = ConvertTo-SecureString $UserPassword -AsPlainText -Force
$remote = 'C:\TP-Automatisation\scripts'
$remoting = @{Credential = $admin; Authentication = 'Kerberos'}

function Get-LabCount {
    Invoke-Command -ComputerName $config.DomainController @remoting {
        $base = 'OU=TP-Automatisation,' + (Get-ADDomain).DistinguishedName
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$base'")) {return 0}
        @(Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,$base").Count
    }
}
function Get-PasswordStamp {
    Invoke-Command -ComputerName $config.DomainController @remoting {
        (Get-ADUser tp.alice -Properties pwdLastSet).pwdLastSet
    }
}
function Get-Summary {Get-Content .\resultats\deploiement.json -Raw | ConvertFrom-Json}
function Test-Summary {
    param($Summary, [int]$Created, [int]$Existing)
    Assert-True ($Summary.State -eq 'OK' -and $Summary.Created -eq $Created -and
        $Summary.Existing -eq $Existing -and $Summary.Shares -eq 2) `
        "Attendu Created=$Created Existing=$Existing Shares=2 ; obtenu $($Summary | ConvertTo-Json -Compress)"
    "Created=$($Summary.Created) Existing=$($Summary.Existing) Shares=$($Summary.Shares)"
}
function Test-Business {
    param([string]$User, [string]$Service)
    $rows = @(Invoke-NetOnly $netbios $User $UserPassword {
        & .\scripts\05-Test-Access.ps1 -ExpectedService $Service
    })
    $text = ($rows | ForEach-Object {"$($_.Service) lire=$($_.CanList) écrire=$($_.CanWrite)"}) -join ' ; '
    Assert-True ($rows.Count -eq 2 -and @($rows | Where-Object Passed).Count -eq 2) "Accès inattendus : $text"
    $text
}

# ---------------------------------------------------------------- état de départ
Test-Step '00 Maquette à l''état initial' {
    Assert-True ((Get-LabCount) -eq 0) 'Objets du TP déjà présents : lab.sh restaurer avant la recette'
    Remove-Item .\resultats -Recurse -Force -ErrorAction SilentlyContinue
    "$env:COMPUTERNAME, PowerShell $($PSVersionTable.PSVersion)"
}

# ---------------------------------------------------------------- étape 01
Test-Step '01 DNS et WinRM des deux serveurs' {
    $srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$($config.DomainName)" -Type SRV | Where-Object Type -eq SRV
    Assert-True ([bool]$srv) 'Enregistrement SRV des DC introuvable'
    foreach ($name in $config.DomainController, $config.FileServer) {
        $test = Test-NetConnection $name -Port 5985 -WarningAction SilentlyContinue
        Assert-True $test.TcpTestSucceeded "WinRM injoignable sur $name"
        "$name=$($test.RemoteAddress)"
    }
}
Test-Step '01 Contrôle syntaxique (VALIDATION.md)' {
    $bad = foreach ($file in Get-ChildItem .\scripts -Filter *.ps1) {
        $tokens = $null; $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count) {$file.Name}
    }
    Assert-True (-not $bad) "Erreurs de syntaxe : $bad"
    'aucune ParseError'
}

# ---------------------------------------------------------------- étape 02
Test-Step '02 Inventaire : deux serveurs OK avec LastBootUpTime' {
    .\scripts\01-Get-Inventory.ps1 -Credential $admin | Out-Null
    $rows = @(Import-Csv .\resultats\inventaire.csv -Delimiter ';' -Encoding UTF8)
    Assert-True ($rows.Count -eq 2 -and @($rows | Where-Object {$_.State -eq 'OK' -and $_.LastBootUpTime}).Count -eq 2) `
        'Deux lignes OK avec date de démarrage attendues'
    ($rows | ForEach-Object {"$($_.Machine) $($_.Installation) $($_.FreeGB) Go"}) -join ' ; '
}
Test-Step '02 Inventaire : cible absente en ECHEC' {
    .\scripts\01-Get-Inventory.ps1 -Credential $admin -OutPath .\resultats\inventaire-erreur.csv `
        -ComputerName $config.DomainController, $config.FileServer, 'absent.learn-it.local' | Out-Null
    $rows = @(Import-Csv .\resultats\inventaire-erreur.csv -Delimiter ';' -Encoding UTF8)
    Assert-True (@($rows | Where-Object State -eq 'OK').Count -eq 2 -and
        @($rows | Where-Object State -eq 'ECHEC').Count -eq 1) 'Deux OK et un ECHEC attendus'
    ($rows | Where-Object State -eq 'ECHEC').Error
}

# ---------------------------------------------------------------- étape 03
. .\scripts\Lab.Common.ps1
$validated = Read-LabConfig .\config\lab.json
Test-Step '03 Validation : CSV correct accepté, CSV invalide refusé' {
    $users = @(Read-ValidatedUsers -Path .\donnees\utilisateurs.csv -AllowedServices $validated.Services)
    Assert-True ($users.Count -eq 6) "Six personnes attendues, $($users.Count) lues"
    $message = $null
    try {Read-ValidatedUsers -Path .\donnees\utilisateurs-invalides.csv -AllowedServices $validated.Services | Out-Null}
    catch {$message = $_.Exception.Message}
    Assert-True ([bool]$message) 'Le CSV invalide a été accepté'
    $message -replace "`r?`n", ' | '
}

$s = New-PSSession -ComputerName $config.DomainController @remoting
Invoke-Command -Session $s -ArgumentList $remote {param($folder) New-Item $folder -ItemType Directory -Force | Out-Null}
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $s
Copy-Item .\scripts\02-Sync-AD.ps1 -Destination $remote -ToSession $s
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $s
Copy-Item .\donnees\utilisateurs.csv -Destination "$remote\utilisateurs.csv" -ToSession $s
$syncAd = {
    param($folder, $password)
    if ($password) {
        & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" -CsvPath "$folder\utilisateurs.csv" -InitialPassword $password
    } else {
        & "$folder\02-Sync-AD.ps1" -ConfigPath "$folder\lab.json" -CsvPath "$folder\utilisateurs.csv" -WhatIf
    }
}
Test-Step '03 WhatIf AD : plan sans création' {
    $plan = @(Invoke-Command -Session $s -ScriptBlock $syncAd -ArgumentList $remote, $null)
    Assert-True ((Get-LabCount) -eq 0) 'Des objets ont été créés pendant WhatIf'
    Assert-True ($plan.Count -eq 6) "Six lignes de plan attendues, $($plan.Count) obtenues"
    ($plan | Group-Object State | ForEach-Object {"$($_.Name)=$($_.Count)"}) -join ' '
}
Test-Step '03 Synchronisation AD : six comptes CREE' {
    $rows = @(Invoke-Command -Session $s -ScriptBlock $syncAd -ArgumentList $remote, $password)
    Assert-True (@($rows | Where-Object State -eq 'CREE').Count -eq 6) "États : $($rows.State -join ',')"
    'CREE=6'
}
$passwordStamp = Get-PasswordStamp
Test-Step '03 Relance AD : six EXISTANT' {
    $rows = @(Invoke-Command -Session $s -ScriptBlock $syncAd -ArgumentList $remote, $password)
    Assert-True (@($rows | Where-Object State -eq 'EXISTANT').Count -eq 6) "États : $($rows.State -join ',')"
    'EXISTANT=6'
}
Test-Step '03 Annuaire : comptes, groupes et imbrication AGDLP' {
    $ad = Invoke-Command -Session $s {
        Import-Module ActiveDirectory
        $base = 'OU=TP-Automatisation,' + (Get-ADDomain).DistinguishedName
        [pscustomobject]@{
            Users = @(Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,$base" -Properties Department |
                Where-Object Enabled | ForEach-Object {"$($_.SamAccountName):$($_.Department)"})
            Groups = @(Get-ADGroup -Filter * -SearchBase "OU=Groupes,$base" |
                ForEach-Object {"$($_.Name):$($_.GroupScope):$($_.GroupCategory)"})
            GGIT = @(Get-ADGroupMember GG_TP_IT | Select-Object -ExpandProperty SamAccountName)
            DLIT = @(Get-ADGroupMember DL_TP_IT_M | Select-Object -ExpandProperty SamAccountName)
        }
    }
    Assert-True ($ad.Users.Count -eq 6) "Six comptes activés attendus : $($ad.Users -join ',')"
    Assert-True ($ad.Groups.Count -eq 4 -and @($ad.Groups -like '*:Global:Security').Count -eq 2 -and
        @($ad.Groups -like '*:DomainLocal:Security').Count -eq 2) "Groupes : $($ad.Groups -join ',')"
    Assert-True ($ad.GGIT.Count -eq 3 -and (@($ad.DLIT) -join ',') -eq 'GG_TP_IT') "GG_TP_IT=$($ad.GGIT -join ',') DL=$($ad.DLIT -join ',')"
    "GG_TP_IT=$($ad.GGIT -join ',') ; DL_TP_IT_M=$($ad.DLIT -join ',')"
}
Remove-PSSession $s

# ---------------------------------------------------------------- étape 04
$dc = New-PSSession -ComputerName $config.DomainController @remoting
$domain = Invoke-Command -Session $dc {Import-Module ActiveDirectory; Get-ADDomain | Select-Object DNSRoot, NetBIOSName}
Remove-PSSession $dc
$netbios = $domain.NetBIOSName
$srv = New-PSSession -ComputerName $config.FileServer @remoting
Invoke-Command -Session $srv -ArgumentList $remote {param($folder) New-Item $folder -ItemType Directory -Force | Out-Null}
Copy-Item .\scripts\Lab.Common.ps1 -Destination $remote -ToSession $srv
Copy-Item .\scripts\03-Sync-Shares.ps1 -Destination $remote -ToSession $srv
Copy-Item .\config\lab.json -Destination "$remote\lab.json" -ToSession $srv
$getShares = {
    param($netbios)
    foreach ($service in 'IT', 'RH') {
        $share = Get-SmbShare -Name "TP_$service`$" -ErrorAction SilentlyContinue
        $acl = Get-Acl "C:\TP-Automatisation\Partages\$service" -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Service = $service
            Exists = [bool]$share
            Encrypt = $share.EncryptData
            Smb = @(if ($share) {Get-SmbShareAccess -Name $share.Name |
                ForEach-Object {"$($_.AccountName):$($_.AccessRight):$($_.AccessControlType)"}})
            Ntfs = @(if ($acl) {$acl.Access | ForEach-Object {"$($_.IdentityReference):$($_.FileSystemRights)"}})
            Protected = $acl.AreAccessRulesProtected
        }
    }
}
Test-Step '04 WhatIf partages : plan sans création' {
    $plan = @(Invoke-Command -Session $srv -ArgumentList $remote, $netbios {
        param($folder, $netbios)
        & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios -WhatIf
    })
    $state = @(Invoke-Command -Session $srv -ScriptBlock $getShares -ArgumentList $netbios)
    Assert-True (@($state | Where-Object Exists).Count -eq 0) 'Un partage a été créé pendant WhatIf'
    ($plan | ForEach-Object {"$($_.Share)->$($_.Group)"}) -join ' ; '
}
Test-Step '04 Partages : deux partages configurés' {
    $rows = @(Invoke-Command -Session $srv -ArgumentList $remote, $netbios {
        param($folder, $netbios)
        & "$folder\03-Sync-Shares.ps1" -ConfigPath "$folder\lab.json" -NetBIOSName $netbios
    })
    Assert-True ($rows.Count -eq 2) "Deux partages attendus, $($rows.Count) rapportés"
    ($rows | ForEach-Object {"$($_.Share)=$($_.Path)"}) -join ' ; '
}
$checkShares = {
    $state = @(Invoke-Command -Session $srv -ScriptBlock $getShares -ArgumentList $netbios)
    foreach ($row in $state) {
        $dl = "$netbios\DL_TP_$($row.Service)_M"
        Assert-True ($row.Exists -and $row.Encrypt) "Partage $($row.Service) absent ou non chiffré"
        Assert-True ($row.Smb.Count -eq 1 -and $row.Smb[0] -eq "${dl}:Change:Allow") "SMB $($row.Service) : $($row.Smb -join ',')"
        Assert-True ($row.Protected -and $row.Ntfs.Count -eq 3 -and @($row.Ntfs -like "${dl}:Modify*").Count -eq 1) `
            "NTFS $($row.Service) : $($row.Ntfs -join ',')"
    }
    ($state | ForEach-Object {"$($_.Service): SMB $($_.Smb -join ',') | NTFS $($_.Ntfs -join ',')"}) -join "`n"
}
Test-Step '04 État réel SMB et NTFS' $checkShares
Remove-PSSession $srv
Test-Step '04 Alice : IT oui, RH non' {Test-Business 'tp.alice' 'IT'}
Test-Step '04 Chloé : RH oui, IT non' {Test-Business 'tp.chloe' 'RH'}

# ---------------------------------------------------------------- étape 05
Test-Step '05 Pilote -WhatIf : plan et sessions fermées' {
    $before = @(Get-PSSession).Count
    $plan = .\scripts\04-Deploy-Lab.ps1 -Credential $admin -WhatIf
    $after = @(Get-PSSession).Count
    Assert-True ($plan.State -eq 'PLANIFIE') "État : $($plan.State)"
    Assert-True ($after -eq $before) "Sessions encore ouvertes après -WhatIf : $($after - $before)"
    "PLANIFIE, Users=$($plan.Users)"
}
Test-Step '05 Pilote : Created=0 Existing=6 Shares=2' {
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password | Out-Null
    Test-Summary (Get-Summary) 0 6
}
Test-Step '05 Relance du pilote : aucun doublon' {
    Copy-Item .\resultats\comptes.csv .\resultats\comptes-avant-relance.csv
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password | Out-Null
    Test-Summary (Get-Summary) 0 6
}
Test-Step '05 CSV invalide refusé sans ajout' {
    $before = Get-LabCount
    $message = $null
    try {
        .\scripts\04-Deploy-Lab.ps1 -Credential $admin -CsvPath .\donnees\utilisateurs-invalides.csv `
            -InitialPassword $password | Out-Null
    } catch {$message = $_.Exception.Message}
    Assert-True ([bool]$message) 'Le pilote a accepté le CSV invalide'
    Assert-True ((Get-LabCount) -eq $before) 'Le nombre de comptes a changé'
    $message -replace "`r?`n", ' | '
}
Test-Step '05 Cible inaccessible refusée, sessions fermées' {
    Copy-Item .\config\lab.json .\config\lab-erreur.json
    $bad = Get-Content .\config\lab-erreur.json -Raw | ConvertFrom-Json
    $bad.FileServer = 'absent.learn-it.local'
    $bad | ConvertTo-Json | Set-Content .\config\lab-erreur.json -Encoding UTF8
    $before = @(Get-PSSession).Count
    $message = $null
    try {
        .\scripts\04-Deploy-Lab.ps1 -Credential $admin -ConfigPath .\config\lab-erreur.json `
            -InitialPassword $password | Out-Null
    } catch {$message = $_.Exception.Message}
    Assert-True ([bool]$message) 'Le pilote n''a pas signalé la cible absente'
    Assert-True (@(Get-PSSession).Count -eq $before) 'Une session est restée ouverte'
    $message
}
Test-Step '05 Gabriel : Created=1 Existing=6' {
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password `
        -CsvPath .\donnees\utilisateurs-avec-gabriel.csv | Out-Null
    Test-Summary (Get-Summary) 1 6
}
Test-Step '05 Relance à sept : Created=0 Existing=7' {
    .\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password `
        -CsvPath .\donnees\utilisateurs-avec-gabriel.csv | Out-Null
    Test-Summary (Get-Summary) 0 7
}
Test-Step '05 Relances : mot de passe d''Alice jamais réinitialisé' {
    $now = Get-PasswordStamp
    Assert-True ($now -eq $passwordStamp) "pwdLastSet a changé : $passwordStamp -> $now"
    "pwdLastSet identique depuis la création ($([DateTime]::FromFileTime($now).ToString('s')))"
}
Test-Step '05 GG_TP_IT : quatre membres' {
    $members = @(Invoke-Command -ComputerName $config.DomainController @remoting {
        Get-ADGroupMember GG_TP_IT | Select-Object -ExpandProperty SamAccountName
    })
    Assert-True ($members.Count -eq 4 -and 'tp.gabriel' -in $members) "Membres : $($members -join ',')"
    $members -join ','
}
Test-Step '05 Gabriel : IT oui, RH non' {Test-Business 'tp.gabriel' 'IT'}
Test-Step '05 Alice et Chloé après relances' {
    (Test-Business 'tp.alice' 'IT') + ' || ' + (Test-Business 'tp.chloe' 'RH')
}
$srv = New-PSSession -ComputerName $config.FileServer @remoting
Test-Step '05 SMB et NTFS sans doublon après relances' $checkShares
Test-Step '05 Pare-feu de SRV01 : règles entrantes actives sur TCP 445' {
    $rules = Invoke-Command -Session $srv {
        Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow | ForEach-Object {
            $port = $_ | Get-NetFirewallPortFilter
            if ($port.Protocol -eq 'TCP' -and '445' -in @($port.LocalPort)) {
                $address = ($_ | Get-NetFirewallAddressFilter).RemoteAddress -join ','
                "$($_.Name) [$address]"
            }
        }
    }
    Assert-True (@($rules).Count -eq 1 -and $rules -like 'TP-Auto-SMB*') "Règles 445 : $($rules -join ' ; ')"
    $rules -join ' ; '
}
Remove-PSSession $srv
Test-Step '05 Pare-feu : 445 de SRV01 ouvert pour ADMIN, fermé pour DC01' {
    $fromAdmin = (Test-NetConnection $config.FileServer -Port 445 -WarningAction SilentlyContinue).TcpTestSucceeded
    $fromDc = Invoke-Command -ComputerName $config.DomainController @remoting -ArgumentList $config.FileServer {
        param($server)
        (Test-NetConnection $server -Port 445 -WarningAction SilentlyContinue).TcpTestSucceeded
    }
    Assert-True ($fromAdmin -and -not $fromDc) "ADMIN=$fromAdmin DC01=$fromDc"
    "ADMIN=$fromAdmin DC01=$fromDc"
}

# ---------------------------------------------------------------- bilan
$checks | Format-Table -AutoSize -Wrap Résultat, Contrôle, Détail | Out-String -Width 220
$failed = @($checks | Where-Object Résultat -ne 'OK').Count
"Recette : $($checks.Count - $failed) contrôle(s) OK, $failed échec(s)."
exit ([int]($failed -gt 0))
