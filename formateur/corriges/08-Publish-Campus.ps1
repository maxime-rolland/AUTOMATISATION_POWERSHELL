#Requires -Version 5.1
<# Sur ADM01. Le manifest local est la reference. Un hash prouve l'integrite, pas l'identite de l'auteur. #>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateScript({Test-Path $_ -PathType Container})][string]$ReleasePath,
      [Parameter(Mandatory)][pscredential]$Credential,
      [string]$ComputerName='srv01.campus.test')
$ErrorActionPreference='Stop'
$manifest=Get-Content (Join-Path $ReleasePath manifest.json) -Raw | ConvertFrom-Json
if ($manifest.Version -notmatch '^v[0-9]+$' -or $manifest.File -ne 'index.html' -or $manifest.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {throw 'Manifest invalide (version vN attendue).'}
$file=Join-Path $ReleasePath 'index.html'
if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $manifest.Sha256) {throw 'Integrite locale invalide.'}
if (-not $PSCmdlet.ShouldProcess($ComputerName,"Publier $($manifest.Version) avec validation et rollback")) {return}
$s=$null
try {
    $s=New-PSSession -ComputerName $ComputerName -Authentication Kerberos -ConfigurationName Microsoft.PowerShell -Credential $Credential
    $stage=Invoke-Command -Session $s -ArgumentList $manifest.Version {
        param($version)
        $path="C:\LabWeb\staging\$version-$([guid]::NewGuid().ToString('N'))"
        New-Item $path -ItemType Directory -Force | Out-Null
        $path
    }
    Copy-Item $file -Destination (Join-Path $stage 'index.html') -ToSession $s
    Invoke-Command -Session $s -ArgumentList $stage,$manifest.Version,$manifest.Sha256 {
        param($stage,$version,$expectedHash)
        $ErrorActionPreference='Stop';Import-Module WebAdministration
        $source=Join-Path $stage 'index.html'
        if ((Get-FileHash $source -Algorithm SHA256).Hash -ne $expectedHash) {throw 'Integrite distante invalide.'}
        $release="C:\LabWeb\releases\$version"
        if (Test-Path $release) {
            if ((Get-FileHash (Join-Path $release index.html) -Algorithm SHA256).Hash -ne $expectedHash) {throw 'Version existante differente: utiliser un nouveau numero.'}
        } else {
            New-Item $release -ItemType Directory | Out-Null
            Copy-Item $source (Join-Path $release index.html)
        }
        $old=(Get-ItemProperty IIS:\Sites\Campus -Name physicalPath).physicalPath
        try {
            Set-ItemProperty IIS:\Sites\Campus -Name physicalPath -Value $release
            $ok=$false
            for ($attempt=1;$attempt -le 5;$attempt++) {
                try {
                    $r=Invoke-WebRequest 'http://localhost:8080/index.html' -UseBasicParsing -TimeoutSec 3
                    if ($r.StatusCode -eq 200 -and $r.Content.Contains("Campus - $version")) {$ok=$true;break}
                } catch {Write-Verbose $_.Exception.Message}
                Start-Sleep -Seconds 1
            }
            if (-not $ok) {throw 'Controle HTTP/contenu invalide.'}
            [pscustomobject]@{Version=$version;PreviousPath=$old;CurrentPath=$release;Etat='OK';SHA256=$expectedHash}
        } catch {
            Set-ItemProperty IIS:\Sites\Campus -Name physicalPath -Value $old
            throw "Rollback vers $old effectue apres echec: $($_.Exception.Message)"
        } finally {
            # Seul le staging cree par ce script est efface. Les releases restent pour le retour arriere.
            if (Test-Path $stage) {Remove-Item $stage -Recurse -Force}
        }
    }
} finally {if ($s) {Remove-PSSession $s}}
