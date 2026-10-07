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
| 04 | Partages et droits | Deux partages ; Alice IT oui/RH non et Chloé RH oui/IT non |
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

## Contrôles déjà effectués sur les sources

Les fichiers Markdown, liens locaux, JSON/CSV, encodages et cohérence du parcours ont été contrôlés. Les scripts ont été relus et commentés. Les essais **sur Windows et le domaine learn-it.local n'ont pas été exécutés dans l'environnement de création du dépôt** : vos tests sur les VM doivent établir le fonctionnement réel AD/SMB. Distinguez ces tests des seuls contrôles de fichiers.
