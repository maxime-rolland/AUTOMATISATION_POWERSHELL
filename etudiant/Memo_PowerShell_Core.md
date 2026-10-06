# Mémo de terrain — PowerShell & Server Core

## Avant une commande

Identifier machine (`hostname`), identité (`whoami`), moteur (`$PSVersionTable`) et portée. Lire `Get-Help <commande> -Examples`. Pour modifier, préparer sauvegarde/retour arrière et WhatIf si implémenté. Ne jamais saisir un secret en texte dans le code.

| Besoin | Commande repère |
|---|---|
| Découverte | Get-Command, Get-Help, Get-Member |
| Données | Where-Object, Select-Object, Sort-Object, Group-Object |
| Export | Export-Csv -NoTypeInformation -Delimiter ';' -Encoding UTF8 |
| Configuration | Get-Content -Raw puis ConvertFrom-Json |
| Machine | Get-CimInstance Win32_ComputerSystem |
| Réseau | Get-NetIPConfiguration, Get-DnsClientServerAddress |
| DNS AD | Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV |
| Port | Test-NetConnection srv01.campus.test -Port 5985 |
| Session | New-PSSession -ComputerName <FQDN> -Authentication Kerberos -Credential $cred |
| Exécution distante | Invoke-Command -Session $s -ScriptBlock {…} |
| Copie directe | Copy-Item <source> <destination> -ToSession $s |
| Fin de session | Remove-PSSession $s, dans finally |
| AD | Get-ADUser, Get-ADGroupMember, Get-ADDomain |
| Droits | Get-Acl <dossier>, Get-SmbShareAccess -Name 'IT$' |
| IIS | Import-Module WebAdministration ; Get-Website Campus |
| Intégrité | Get-FileHash <fichier> -Algorithm SHA256 |
| Santé | Get-ScheduledTaskInfo -TaskName PSLAB-Health |
| Logs | Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational';Id=4104} |

## Gestion d'erreur

```powershell
$s = $null
try {
  $s = New-PSSession -ComputerName srv01.campus.test `
    -Authentication Kerberos -Credential (Get-Credential) -ErrorAction Stop
  Invoke-Command -Session $s {Get-Service W3SVC} -ErrorAction Stop
} catch {
  Write-Error $_.Exception.Message
} finally {
  if ($s) {Remove-PSSession $s}
}
```

## Méthode de diagnostic

IP → DNS → TCP → identité → service → contenu → droits. Ne pas sauter à une désactivation globale du pare-feu. Tester avec la bonne identité : Domain Admin n'est pas Alice. HTTP 200 n'est pas la preuve du bon contenu. Un hash seul ne prouve pas l'auteur. Un rapport de santé ancien ne prouve pas l'état présent.

## Repères de maquette

DC01 10.77.10.10 ; SRV01 10.77.10.20 ; ADM01 10.77.10.30 ; masque /24 ; DNS DC01 ; aucune passerelle ; domaine campus.test. WinRM 5985, SMB 445, intranet 8080. Windows PowerShell 5.1 pour le parcours principal.
