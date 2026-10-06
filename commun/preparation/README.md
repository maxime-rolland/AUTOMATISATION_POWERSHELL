# Préparation de la maquette

[Support étudiant](../../etudiant/Support_TP_Etudiant.md) · [Guide formateur](../../formateur/Guide_Formateur.md)

| Script | Machine d'exécution | Effet |
|---|---|---|
| [New-LabVM.ps1](New-LabVM.ps1) | Hôte Hyper-V, administrateur | Switch privé et trois VM vides ; OS à installer |
| [Copy-LabToVM.ps1](Copy-LabToVM.ps1) | Hôte Hyper-V | Copie du dossier du cours par PowerShell Direct |
| [01-Initialize-Core.ps1](01-Initialize-Core.ps1) | Console locale de chaque VM | IPv4, DNS, nom, WinRM et règles de diagnostic |

Suivre la procédure complète du support. Lire les scripts et utiliser WhatIf lorsque disponible. L'installation Windows et ses redémarrages ne sont pas entièrement automatisés. Les VM doivent avoir une seule carte active et se trouver sur un réseau isolé. Le bootstrap ne doit pas être exécuté depuis une session réseau qu'il risque de couper.
