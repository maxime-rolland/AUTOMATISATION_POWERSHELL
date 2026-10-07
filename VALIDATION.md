# Vérifier votre maquette et préparer la démonstration

[Accueil](README.md) · [Démonstration](docs/05-Pilotage-et-demonstration.md)

Ce fichier rassemble vos points de contrôle. Utilisez-le au fil des étapes 01 à 05, puis pour répéter votre démonstration. Les contrôles de déploiement ne sont pas des prérequis à réaliser avant le TP : ils correspondent au travail que vous allez construire.

## Vos contrôles au fil du TP

| Étape | Vérification | Résultat à constater |
|---|---|---|
| 01 | Contexte et WinRM | Vrais FQDN et IP du poste ; domaine existant ; copie isolée ; WinRM joignable sur les deux cibles |
| 01, puis après vos modifications | Syntaxe des scripts | Aucun ParseError en Windows PowerShell 5.1 |
| 02 | Accès administratifs et inventaire | Sessions Kerberos ; données des deux vraies cibles en OK ; cible fictive en ECHEC ; date de démarrage dans le CSV |
| 03 | Données et AD | CSV invalide refusé avant création ; six comptes, quatre groupes et bonnes appartenances |
| 04 | Partages et droits | Deux partages ; Alice IT oui/RH non et Chloé RH oui/IT non ; TCP 445 de SRV01 ouvert au seul poste ADMIN |
| 05, avant Gabriel | Pilote et relance | Six comptes conservés ; zéro ajout lors de la relance ; mêmes groupes, partages et accès |
| 05 | Deux erreurs et reprise | CSV invalide et cible inaccessible signalés ; pas d'ajout ; relance normale réussie |
| 05, après Gabriel | Adaptation et état final | Sept comptes ; quatre membres dans GG_TP_IT ; mêmes quatre groupes/deux partages ; Gabriel IT oui/RH non ; relance Created=0 et Existing=7 |

Notez les versions Windows utilisées, conservez les rapports des passages à six puis à sept comptes et gardez l'erreur réelle si un point échoue. Préparez les consoles métiers avant votre passage pour limiter les manipulations pendant la démonstration.

## Contrôle syntaxique non exécutant

Sur ADMIN, en `powershell.exe` 5.1, depuis la racine du dépôt :

```powershell
# ADMIN, powershell.exe 5.1 : contrôler la syntaxe sans exécuter les scripts.
$failed = $false
Get-ChildItem .\scripts -Filter *.ps1 | ForEach-Object {
    # Le parseur remplit ces deux variables par référence pour le fichier courant.
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null

    # Signaler le fichier et les erreurs avec leurs emplacements ; poursuivre les autres fichiers.
    if ($parseErrors.Count -gt 0) {
        $failed = $true
        Write-Output $_.FullName
        $parseErrors | Select-Object Message,Extent
    }
}

# Bloquer la suite de la préparation si au moins un script est syntaxiquement incorrect.
if ($failed) {throw 'Corriger la syntaxe avant de déployer.'}
```

Ce parseur ne lance aucune création. Il valide la syntaxe, pas les droits, les modules disponibles ou le fonctionnement AD/SMB. Poursuivez ensuite avec les contrôles réels des étapes du TP.

## Trace courte de répétition

Date : … · Machines et versions : … · Copie de maquette : …

Syntaxe : … · CSV : … · Déploiement : … · Relance : … · Droits : … · Erreur/adaptation : …

Correction à apporter puis contrôle à rejouer : …

## Contrôles effectués par l'auteur sur une maquette réelle

Le 7 octobre 2026, le parcours corrigé a été rejoué de bout en bout sur une maquette KVM construite par [kvm/lab.sh](kvm/README.md) : DC01 et SRV01 sous Windows Server 2022 Standard Evaluation en Server Core (build 20348, anglais), ADMIN sous Windows 11 Pro 25H2 (build 26200, français), Windows PowerShell 5.1. La [recette](kvm/invite/Invoke-Recette.ps1) enchaîne les commandes des étapes 01 à 05 et compare chaque résultat à l'attendu des supports : 29 contrôles, tous OK, sur une maquette reconstruite à blanc.

Ces essais ont conduit aux corrections de la version 2.3 :

| Constat sur la maquette | Correction |
|---|---|
| `04-Deploy-Lab.ps1 -WhatIf` laissait deux sessions WinRM ouvertes : `Remove-PSSession` respecte lui aussi WhatIf et se contentait d'annoncer la fermeture | `-WhatIf:$false` sur les deux fermetures du bloc `finally` |
| Le port 445 de SRV01 restait ouvert à tout le LAN : sous Server 2022, la règle « File and Printer Sharing (SMB-In) » du profil Domaine porte un nom GUID, et « File Server Remote Management (SMB-In) » ouvre aussi 445 | `03-Sync-Shares.ps1` repère les règles par leur port ; la recette vérifie l'accès depuis ADMIN et le refus depuis DC01 |
| Windows 11 est en `Restricted` par défaut, et une console `runas /netonly` n'hérite pas d'une stratégie de portée `Process` | Étape 01 : portée `CurrentUser` ; étapes 04 et 05 : `-ExecutionPolicy RemoteSigned` dans les commandes `runas` |
| Sans passerelle par défaut, Windows affiche « Réseau non identifié » et applique le profil pare-feu Public | Étape 01 : déclarer une passerelle, même sans routeur |
| Les fichiers copiés depuis un DVD gardent l'attribut lecture seule | Étape 01 : `robocopy ... /A-:R` |
| En WhatIf, `02-Sync-AD.ps1` annonçait PLANIFIE même pour un compte déjà présent | Un compte présent reste EXISTANT |

Limites de ces essais : la recette s'exécute en SYSTEM par l'agent invité et construit les credentials à partir de secrets transmis, là où l'étudiant utilise `Get-Credential` et `Read-Host`. Les tests métiers ouvrent une session réseau *NEW_CREDENTIALS*, le mécanisme de `runas /netonly`, sans la saisie interactive. Windows Server 2025 n'a pas été essayé. Vos propres tests sur les VM de la séance restent la preuve attendue à l'évaluation.
