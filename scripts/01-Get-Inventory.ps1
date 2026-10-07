#Requires -Version 5.1
<#
.SYNOPSIS
    Inventorier les deux serveurs du laboratoire depuis le poste d'administration.
.EXAMPLE
    .\01-Get-Inventory.ps1 -Credential (Get-Credential)
.NOTES
    Exécuter dans Windows PowerShell 5.1, sur le poste membre de learn-it.local.
    Ce script ne modifie pas les serveurs ; il écrit un CSV sur le poste appelant.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][pscredential]$Credential,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.json'),
    [string[]]$ComputerName,
    [string]$OutPath = (Join-Path $PSScriptRoot '..\resultats\inventaire.csv')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
$config = Read-LabConfig -Path $ConfigPath
if (-not $ComputerName) {$ComputerName = @($config.DomainController, $config.FileServer)}

# Une itération renvoie un objet de même structure, que la cible réponde ou non.
$results = foreach ($computer in $ComputerName) {
    $session = $null
    try {
        # Le FQDN et Kerberos authentifient le serveur. Pas de TrustedHosts '*'.
        # Microsoft.PowerShell désigne explicitement l'endpoint Windows PowerShell 5.1.
        $session = New-PSSession -ComputerName $computer -Credential $Credential `
            -Authentication Kerberos -ConfigurationName Microsoft.PowerShell

        # Ce bloc s'exécute SUR LA CIBLE. Ses variables ne sont pas celles du poste admin.
        Invoke-Command -Session $session -ScriptBlock {
            $ErrorActionPreference = 'Stop' # Les erreurs CIM distantes doivent remonter au catch local.
            $system = Get-CimInstance Win32_ComputerSystem
            $os = Get-CimInstance Win32_OperatingSystem
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            $install = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

            # Conserver les données dans un objet permet l'export et d'autres contrôles.
            [pscustomobject]@{
                Machine = $env:COMPUTERNAME
                Domain = $system.Domain
                OS = $os.Caption
                Installation = $install.InstallationType
                # Correction de l'adaptation commune : date de dernier démarrage en ISO 8601.
                # Lire la propriété sur la cible avant de transmettre l'objet à ADMIN.
                LastBootUpTime = $os.LastBootUpTime.ToString('o')
                FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                State = 'OK'
                Error = ''
            }
        }
    } catch {
        # L'erreur d'une cible devient une ligne du rapport ; les autres restent traitées.
        [pscustomobject]@{
            # Garder aussi la nouvelle colonne en cas d'échec, pour un CSV de structure constante.
            Machine=$computer; Domain=''; OS=''; Installation=''; LastBootUpTime=''; FreeGB=$null
            State='ECHEC'; Error=$_.Exception.Message
        }
    } finally {
        # Une session est une ressource. On la ferme même quand Invoke-Command échoue.
        if ($session) {Remove-PSSession $session}
    }
}

# L'export est LOCAL. Select-Object retire les propriétés ajoutées par le remoting.
$folder = Split-Path -Parent $OutPath
if ($folder -and -not (Test-Path -LiteralPath $folder)) {New-Item $folder -ItemType Directory | Out-Null}
# Inclure la date dans la projection, sinon elle serait absente du fichier malgré sa lecture.
$results | Select-Object Machine,Domain,OS,Installation,LastBootUpTime,FreeGB,State,Error |
    Export-Csv -LiteralPath $OutPath -NoTypeInformation -Delimiter ';' -Encoding UTF8
$results # Sortie d'objets utilisable par l'appelant ; aucune Format-Table ici.
