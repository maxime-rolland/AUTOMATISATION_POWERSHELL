# TP — Automatiser l'arrivée d'utilisateurs avec PowerShell

**Bachelor Réseau & Cybersécurité, Bac +3 · 2 jours · Domaine existant : `learn-it.local` · IA autorisée.**

Vous devez rendre une maquette qui fonctionne : un fichier CSV devient des comptes AD, des groupes et des accès à des dossiers partagés. Une seule commande doit piloter les opérations, et une deuxième exécution doit conserver le résultat sans créer de doublons.

Les exercices, explications et corrections sont disponibles ensemble. Lire, réutiliser et faire expliquer le corrigé par une IA est autorisé voir recommandé. La note porte sur le fonctionnement démontré, les tests et votre capacité à expliquer et adapter le script.

Suivez les étapes 01 à 05 dans l'ordre. Chaque consigne vous indique l'action à réaliser, la machine concernée et le résultat à vérifier. Vous utilisez le même support pour apprendre, consulter la correction et préparer votre démonstration.

## Le résultat à montrer

Avec le même jeu de données pour toute la classe : **six comptes, quatre groupes, deux partages**.

- `tp.alice` peut lire et écrire dans le partage IT, mais ne peut pas accéder à RH.
- `tp.chloe` peut lire et écrire dans RH, mais ne peut pas accéder à IT.
- Le pilote déploie à partir du CSV ; les rapports sont lisibles.
- Une relance crée **zéro nouveau compte** et conserve les accès.
- Un CSV invalide est refusé avant les modifications ; une cible inaccessible produit une erreur compréhensible.
- Après validation de ce socle, vous ajoutez `tp.gabriel` : **sept comptes au total**, toujours quatre groupes et deux partages. Gabriel obtient les mêmes accès IT qu'Alice.

## Parcours commun

| Lecture | Contenu |
|---|---|
| [01 — Maquette et mise en route](docs/01-Maquette-et-demarrage.md) | VM, domaine déjà présent, configuration et commandes de départ |
| [02 — Comprendre PowerShell et faire un inventaire](docs/02-PowerShell-et-inventaire.md) | Objets, pipeline, paramètres, erreurs et sessions ; correction expliquée |
| [03 — CSV vers Active Directory](docs/03-Automatiser-AD.md) | Validation complète, OU, comptes, groupes, WhatIf et relance |
| [04 — Automatiser les partages et tester les droits](docs/04-Partages-et-tests.md) | SMB/NTFS, héritage, AGDLP, tests avec de vraies identités réseau |
| [05 — Une commande pour tout déployer](docs/05-Pilotage-et-demonstration.md) | Orchestration, copies directes, rapports, erreurs et scénario de démonstration |
| [Évaluation sur 20](EVALUATION.md) | Cinq critères de quatre points, preuves à montrer en direct |
| [Travail avec l'IA](IA.md) | Méthode de travail autorisée et questions pour vérifier la compréhension |
| [Mémo](docs/Memo.md) | Commandes utiles et diagnostic rapide |
| [Maquette KVM (enseignant)](kvm/README.md) | Construire DC01, SRV01 et ADMIN sous KVM/libvirt, instantané initial et recette du corrigé |

Les [scripts commentés](scripts/README.md) sont les corrections exécutables. Les [données](donnees/) et la [configuration](config/lab.json) sont communes à tous les participants.

## Démarrage rapide

1. Disposer d'un DC du domaine `learn-it.local`, d'un serveur de fichiers membre et d'un poste d'administration membre. Favoriser **Server Core pour les serveurs**. Sous KVM/libvirt, [kvm/lab.sh](kvm/README.md) construit cette maquette.
2. Copier ou cloner le dépôt dans `C:\TP-PowerShell` sur le poste d'administration.
3. Vérifier `config/lab.json` : noms des deux serveurs et IP du poste de test. Le CSV, les noms des comptes et les exercices sont les mêmes pour toute la classe.
4. Effectuer les vérifications DNS/WinRM de l'étape 01 et le contrôle syntaxique de [VALIDATION.md](VALIDATION.md).
5. Ouvrir **Windows PowerShell 5.1**. Pour utiliser le corrigé complet après ces vérifications :

```powershell
# ADMIN : placer la console à la racine du dépôt, pour les chemins relatifs .\scripts.
Set-Location C:\TP-PowerShell

# Demander le compte administratif ; Get-Credential renvoie un objet PSCredential.
# Utiliser le vrai nom NetBIOS du domaine ou un UPN. Le nom du compte intégré dépend de la langue
# du DC : Administrator@learn-it.local sur un serveur anglais, administrateur@... sur un serveur français.
$admin = Get-Credential -Message 'Compte autorisé sur le DC et le serveur de fichiers du TP'

# Lire les informations des deux serveurs et produire resultats\inventaire.csv.
.\scripts\01-Get-Inventory.ps1 -Credential $admin

# Vérifier les données et connexions ; WhatIf ne copie rien et ne crée aucun objet du TP.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -WhatIf

# Saisir un secret conforme à la stratégie du domaine ; ne pas l'écrire en clair.
$password = Read-Host 'Secret temporaire des comptes fictifs du TP' -AsSecureString

# Exécuter réellement : AD d'abord, puis dossiers/partages, puis rapports locaux.
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password
```

Ce bloc est un raccourci vers la correction complète ; pour suivre le TP, découvrez d'abord l'inventaire, puis AD, puis les partages dans les étapes 02 à 04. Vous retrouverez ce déploiement global à l'étape 05. Si vous l'avez déjà exécuté, les exercices suivants retrouveront des objets existants : ne les supprimez pas pour forcer une nouvelle création.

Une réponse State=OK confirme les opérations administratives ; démontrez aussi les accès avec les comptes métiers et la relance. Le secret est saisi, jamais enregistré dans le dépôt. Les comptes fictifs sont directement utilisables pour les tests SMB ; ce choix pédagogique et le secret temporaire commun ne constituent pas un onboarding de production.

## Un seul TP pour toute la classe

Vous travaillez seul ou à deux sur **une copie isolée de la même maquette** : DC01, SRV01 et ADMIN dans `learn-it.local`. Vous utilisez `tp.alice`, `tp.chloe`, les groupes `GG_TP_IT`/`GG_TP_RH` et `DL_TP_IT_M`/`DL_TP_RH_M`, et les partages `TP_IT$`/`TP_RH$`. Il n'y a aucun identifiant de binôme à configurer.

Vérifiez que le réseau virtuel de votre copie est isolé des autres : des VM portant les mêmes noms et IP ne doivent pas partager le même LAN. Avant les premières créations, assurez-vous de disposer de l'état initial des trois VM pour pouvoir reprendre une séance à zéro. Les étapes, l'ajout final de `tp.gabriel` et la grille d'évaluation sont identiques pour toute la classe.

## Livraison et validation

Le dépôt contient les sources Markdown/Mermaid, scripts et jeux de données. Les essais Windows doivent être répétés sur la maquette réelle ; [VALIDATION.md](VALIDATION.md) distingue les contrôles effectués et les vérifications à exécuter. Le TP utilise le domaine existant : il ne le reconstruit pas et ne demande aucun rôle web ni service supplémentaire.

Auteur : Maxime ROLLAND · Pulse myIT. Version 2.3 — 7 octobre 2026. [Documentation officielle](Sources.md) · [Licence MIT](LICENSE).
