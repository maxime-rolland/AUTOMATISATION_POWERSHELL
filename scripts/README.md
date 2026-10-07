# Corrections exécutables, communes à tous

[Accueil](../README.md) · [Support](../docs/01-Maquette-et-demarrage.md)

| Script | Machine d'exécution | Rôle | Explication |
|---|---|---|---|
| [Lab.Common.ps1](Lab.Common.ps1) | Chargé par les autres scripts | Fonctions de validation, aucune mutation Windows | [CSV et AD](../docs/03-Automatiser-AD.md) |
| [01-Get-Inventory.ps1](01-Get-Inventory.ps1) | ADMIN | Inventaire des deux serveurs et erreurs par cible | [PowerShell](../docs/02-PowerShell-et-inventaire.md) |
| [02-Sync-AD.ps1](02-Sync-AD.ps1) | DC via session ou console | OU, groupes et utilisateurs additifs | [AD](../docs/03-Automatiser-AD.md) |
| [03-Sync-Shares.ps1](03-Sync-Shares.ps1) | Serveur de fichiers via session ou console | Dossiers, ACL, SMB et règle de laboratoire | [Partages](../docs/04-Partages-et-tests.md) |
| [04-Deploy-Lab.ps1](04-Deploy-Lab.ps1) | ADMIN | Piloter les deux cibles, copies et rapports | [Pilotage](../docs/05-Pilotage-et-demonstration.md) |
| [05-Test-Access.ps1](05-Test-Access.ps1) | ADMIN, console runas /netonly métier | Tests lecture/écriture avec l'identité réseau | [Tests](../docs/04-Partages-et-tests.md) |

Moteur : Windows PowerShell 5.1 ; scripts UTF-8 avec BOM. Les commentaires expliquent les décisions et les effets ; ils ne dispensent pas de tester sur votre maquette. Le pilote appelle les scripts AD et partages : ne les lancer manuellement que pour comprendre ou diagnostiquer une étape.

Le fichier de configuration et les données sont copiés sur les cibles dans `C:\TP-Automatisation\scripts`. Les corrections sont disponibles dès le début du TP. Réutilisation et IA autorisées ; explication et démonstration obligatoires.
