#Requires -Version 5.1
<#
.SYNOPSIS
    Première ouverture de session d'une VM de la maquette KVM.
.DESCRIPTION
    Lancé une seule fois par FirstLogonCommands, depuis l'ISO d'installation de la VM.
    Installe les pilotes virtio (réseau, série, ballon mémoire) puis l'agent invité QEMU.
    L'agent permet ensuite à lab.sh de configurer la VM sans réseau entre l'hôte et le LAN du TP.
    Journal : C:\Windows\Temp\lab-firstlogon.log
#>
$ErrorActionPreference = 'Stop'
Start-Transcript -LiteralPath 'C:\Windows\Temp\lab-firstlogon.log' -Append | Out-Null

function Install-Msi {
    param([Parameter(Mandatory)][string]$Path)
    # /qn : aucune fenêtre ; 3010 signifie succès avec redémarrage demandé.
    $process = Start-Process msiexec.exe -Wait -PassThru `
        -ArgumentList '/i', ('"{0}"' -f $Path), '/qn', '/norestart'
    if ($process.ExitCode -notin 0, 3010) {throw "Échec de $Path : code $($process.ExitCode)"}
    "OK $Path ($($process.ExitCode))"
}

try {
    Install-Msi (Join-Path $PSScriptRoot 'virtio-win-gt-x64.msi')
    Install-Msi (Join-Path $PSScriptRoot 'qemu-ga-x86_64.msi')

    # Une VM en veille ne répond plus à l'agent : garder le poste éveillé.
    powercfg.exe /hibernate off
    powercfg.exe /change standby-timeout-ac 0
    powercfg.exe /change monitor-timeout-ac 0

    Get-Service QEMU-GA | Select-Object Name, Status
} finally {
    Stop-Transcript | Out-Null
}
