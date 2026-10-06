#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -ne 'SRV01') {throw 'SRV01 attendu.'}
$cs=Get-CimInstance Win32_ComputerSystem
if ($cs.Domain -ne 'campus.test') {throw 'Jointure domaine requise.'}
foreach ($dep in @('IT','RH','Direction')) {
    $path="C:\LabData\$dep";$name="${dep}$";$group="CAMPUS\DL_${dep}_M"
    # Resolves les identites avant de modifier un dossier.
    $sid=(New-Object System.Security.Principal.NTAccount($group)).Translate([System.Security.Principal.SecurityIdentifier])
    if ($PSCmdlet.ShouldProcess($path,'Appliquer ACL de TP explicites et partage chiffre')) {
        New-Item $path -ItemType Directory -Force | Out-Null
        $acl=New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($rule in @(@{Sid='S-1-5-18';Rights='FullControl'},@{Sid='S-1-5-32-544';Rights='FullControl'},@{Sid=$sid.Value;Rights='Modify'})) {
            $id=New-Object System.Security.Principal.SecurityIdentifier($rule.Sid)
            $ace=New-Object System.Security.AccessControl.FileSystemAccessRule($id,$rule.Rights,'ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($ace)
        }
        Set-Acl -Path $path -AclObject $acl
        $share=Get-SmbShare -Name $name -ErrorAction SilentlyContinue
        if ($share -and $share.Path -ne $path) {throw "Partage $name pointe ailleurs."}
        if (-not $share) {
            New-SmbShare -Name $name -Path $path -ChangeAccess $group -EncryptData $true -FolderEnumerationMode AccessBased | Out-Null
        } else {
            # Convergence de l'ACL SMB vers un seul groupe autorise. Aucune permission Deny attendue.
            foreach ($entry in @(Get-SmbShareAccess -Name $name)) {
                if ($entry.AccessControlType -eq 'Deny') {Unblock-SmbShareAccess -Name $name -AccountName $entry.AccountName -Force | Out-Null}
                else {Revoke-SmbShareAccess -Name $name -AccountName $entry.AccountName -Force | Out-Null}
            }
            Grant-SmbShareAccess -Name $name -AccountName $group -AccessRight Change -Force | Out-Null
            Set-SmbShare -Name $name -EncryptData $true -FolderEnumerationMode AccessBased -Force
        }
    }
}
if ($PSCmdlet.ShouldProcess('Pare-feu SMB','Autoriser uniquement ADM01')) {
    Get-NetFirewallRule -Name 'FPS-SMB-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    if (-not (Get-NetFirewallRule -Name 'PSLAB-SMB' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'PSLAB-SMB' -DisplayName 'PSLAB SMB ADM01' -Direction Inbound -Protocol TCP `
            -LocalPort 445 -RemoteAddress '10.77.10.30' -Action Allow | Out-Null
    }
}
