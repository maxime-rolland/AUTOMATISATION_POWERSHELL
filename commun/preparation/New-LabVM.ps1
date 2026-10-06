#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
<# Cree trois VM vides. Ne fournit ni Windows ni licence. A executer sur l'hote Hyper-V. #>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateScript({Test-Path $_ -PathType Leaf})][string]$IsoPath,
      [string]$VMRoot='C:\VMs\PSLAB',
      [string]$ConfigPath=(Join-Path $PSScriptRoot '..\config\lab.json'))
$ErrorActionPreference='Stop'
$cfg=Get-Content $ConfigPath -Raw | ConvertFrom-Json
if (Get-VMSwitch -Name $cfg.Switch -ErrorAction SilentlyContinue) {
    if ((Get-VMSwitch -Name $cfg.Switch).SwitchType -ne 'Private') {throw 'Le switch existant doit etre prive.'}
} elseif ($PSCmdlet.ShouldProcess($cfg.Switch,'Creer un switch prive')) {
    New-VMSwitch -Name $cfg.Switch -SwitchType Private | Out-Null
}
foreach ($v in $cfg.VMs) {
    $existing=Get-VM -Name $v.Name -ErrorAction SilentlyContinue
    if ($existing) {Write-Warning "VM $($v.Name) deja presente: aucune modification.";continue}
    $folder=Join-Path $VMRoot $v.Name
    if (Test-Path $folder) {throw "Dossier deja present sans VM: $folder. Examiner avant de continuer."}
    if ($PSCmdlet.ShouldProcess($v.Name,'Creer VM Generation 2 et disque dynamique')) {
        New-Item $folder -ItemType Directory | Out-Null
        $vm=New-VM -Name $v.Name -Generation 2 -MemoryStartupBytes ($v.MemoryGB*1GB) `
            -NewVHDPath (Join-Path $folder "$($v.Name).vhdx") -NewVHDSizeBytes ($v.DiskGB*1GB) `
            -Path $folder -SwitchName $cfg.Switch
        Set-VMProcessor $vm -Count $v.Cpu
        Set-VMMemory $vm -DynamicMemoryEnabled $false
        Set-VM $vm -AutomaticCheckpointsEnabled $false
        Add-VMDvdDrive $vm -Path (Resolve-Path $IsoPath).Path
        Set-VMFirmware $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows `
            -FirstBootDevice (Get-VMDvdDrive $vm)
        Write-Output "$($v.Name): prete. Demarrer avec Start-VM, puis installer Windows Server Standard Core."
    }
}
