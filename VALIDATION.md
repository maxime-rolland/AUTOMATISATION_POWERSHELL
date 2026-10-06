# Validation et répétition sur la maquette

[Accueil](README.md) · [Démonstration](docs/05-Pilotage-et-demonstration.md)

## État de cette livraison

Les sources, liens locaux, fichiers JSON/CSV, encodages et cohérence des deux journées ont été contrôlés. Les scripts ont été relus et commentés. Les essais **sur Windows et le domaine learn-it.local n'ont pas été exécutés dans l'environnement de création du dépôt** ; le fonctionnement doit être vérifié sur la maquette réelle, selon les étapes ci-dessous. Aucune preuve d'AD/SMB ne doit être inventée à partir de ces seuls contrôles de fichiers.

## Avant le cours : sept vérifications

| Vérification | Résultat à constater |
|---|---|
| Contexte | Vrais FQDN et IP du poste ; domaine existant ; LabId unique |
| Accès administratifs | Sessions Kerberos vers les deux cibles ; AD sur le DC ; admin du serveur membre |
| Syntaxe des scripts | Aucun ParseError en Windows PowerShell 5.1 |
| Données | CSV valide lu ; CSV invalide refusé avant déploiement |
| Déploiement | Six comptes, quatre groupes, deux partages avec le jeu initial |
| Relance | Zéro compte ajouté, mêmes groupes et partages |
| Droits | Alice IT oui/RH non et Chloé RH oui/IT non, avec de bonnes identités réseau |

Puis effectuer le scénario d'erreur et la petite adaptation de la démonstration. Noter les versions Windows utilisées et l'erreur réelle si un point échoue.

## Contrôle syntaxique non exécutant

Sur ADMIN, en `powershell.exe` 5.1, depuis la racine du dépôt :

```powershell
$failed = $false
Get-ChildItem .\scripts -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $failed = $true
        Write-Output $_.FullName
        $parseErrors | Select-Object Message,Extent
    }
}
if ($failed) {throw 'Corriger la syntaxe avant de déployer.'}
```

Ce parseur ne lance aucune création. Il valide la syntaxe, pas les droits, les modules disponibles ou le fonctionnement AD/SMB. Il faut ensuite faire la répétition réelle.

## Trace courte de répétition

Date : … · Machines et versions : … · LabId : …

Syntaxe : … · CSV : … · Déploiement : … · Relance : … · Droits : … · Erreur/adaptation : …

Correction nécessaire avant distribution : …
