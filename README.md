# TP — Automatiser l'arrivée d'utilisateurs avec PowerShell

**Bachelor Réseau & Cybersécurité, Bac +3 · 2 jours · Domaine existant : `learn-it.local` · IA autorisée.**

Vous devez rendre une maquette qui fonctionne : un fichier CSV devient des comptes AD, des groupes et des accès à des dossiers partagés. Une seule commande doit piloter les opérations, et une deuxième exécution doit conserver le résultat sans créer de doublons.

Les exercices, explications et corrections sont disponibles ensemble. Lire, réutiliser et faire expliquer le corrigé par une IA est autorisé. La note porte sur le fonctionnement démontré, les tests et votre capacité à expliquer et adapter le script.

## Le résultat à montrer

Avec les données fournies pour B01 : **six comptes, quatre groupes, deux partages**.

- `tp.b01.alice` peut lire et écrire dans le partage IT, mais ne peut pas accéder à RH.
- `tp.b01.chloe` peut lire et écrire dans RH, mais ne peut pas accéder à IT.
- Le pilote déploie à partir du CSV ; les rapports sont lisibles.
- Une relance crée **zéro nouveau compte** et conserve les accès.
- Un CSV invalide est refusé avant les modifications ; une cible inaccessible produit une erreur compréhensible.

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

Les [scripts commentés](scripts/README.md) sont les corrections exécutables. Les [données](donnees/) et la [configuration](config/lab.json) sont communes à tous les participants.

## Organisation des deux jours

14 h de présence : **12 h 40 de travail et 1 h 20 de pauses** ; déjeuner exclu. L'installation des OS et la création du domaine sont des prérequis préparés avant le TP.

| Jour | Heure | Activité |
|---|---|---|
| J1 | 09:00–09:30 | Mission, résultat attendu et accès aux corrigés/IA |
| J1 | 09:30–10:30 | Vérifier la maquette et adapter lab.json |
| J1 | 10:30–10:50 | Pause |
| J1 | 10:50–12:30 | Objets, pipeline, inventaire distant et première erreur gérée |
| J1 | 13:30–15:20 | Valider le CSV et créer les objets AD |
| J1 | 15:20–15:40 | Pause |
| J1 | 15:40–16:40 | WhatIf, CSV invalide et deuxième passage AD |
| J1 | 16:40–17:00 | Contrôle : six comptes, quatre groupes et aucune duplication |
| J2 | 09:00–09:20 | Reprise et vérification des groupes |
| J2 | 09:20–10:30 | Automatiser les dossiers, droits et partages |
| J2 | 10:30–10:50 | Pause |
| J2 | 10:50–12:30 | Tests réels Alice/Chloé et correction des accès |
| J2 | 13:30–15:20 | Pilote, rapports, relance complète et panne contrôlée |
| J2 | 15:20–15:40 | Pause |
| J2 | 15:40–17:00 | Démonstrations, adaptation courte et explication individuelle |

Pendant le dernier créneau, les binômes passent à tour de rôle ; les autres préparent leurs preuves. Prévoir environ 8 à 10 min par binôme et adapter le passage à l'effectif de la classe.

## Démarrage rapide

1. Disposer d'un DC du domaine `learn-it.local`, d'un serveur de fichiers membre et d'un poste d'administration membre. Favoriser **Server Core pour les serveurs**.
2. Copier ou cloner le dépôt dans `C:\TP-PowerShell` sur le poste d'administration.
3. Adapter `config/lab.json` : vrais noms des serveurs, IP du poste de test et identifiant de binôme. Adapter les identifiants du CSV si le binôme n'est pas B01.
4. Ouvrir **Windows PowerShell 5.1**. Pour démarrer avec le corrigé complet :

```powershell
Set-Location C:\TP-PowerShell
$admin = Get-Credential -Message 'Compte autorisé sur le DC et le serveur de fichiers du TP'
.\scripts\01-Get-Inventory.ps1 -Credential $admin
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -WhatIf
$password = Read-Host 'Secret temporaire des comptes fictifs du TP' -AsSecureString
.\scripts\04-Deploy-Lab.ps1 -Credential $admin -InitialPassword $password
```

Lire les explications avant de lancer le déploiement. Une réponse State=OK n'est pas toute la recette : montrer les accès avec les comptes métiers et la relance. Le secret est saisi, jamais enregistré dans le dépôt. Les comptes fictifs sont directement utilisables pour les tests SMB ; ce choix pédagogique et le secret temporaire commun ne constituent pas un onboarding de production.

## Binômes et domaine partagé

`LabId=B01` produit une OU `TP-Automatisation-B01`, des comptes `tp.b01.*`, des groupes `GG_TP_B01_*`/`DL_TP_B01_*` et des partages `TP_B01_*`. B02 utilise son propre identifiant et des comptes `tp.b02.*`.

Un domaine peut être partagé par la classe ; affecter **un LabId unique à chaque binôme** et, de préférence, son propre serveur membre. Si les serveurs de fichiers sont aussi partagés, l'enseignant prépare les règles réseau communes ; les scripts de partages modifient les règles SMB locales du laboratoire. Ne pas lancer B01 depuis plusieurs binômes simultanément.

## Livraison et validation

Le dépôt contient les sources Markdown/Mermaid, scripts et jeux de données. Les essais Windows doivent être répétés sur la maquette réelle ; [VALIDATION.md](VALIDATION.md) distingue les contrôles effectués et les vérifications à exécuter. Le TP utilise le domaine existant : il ne le reconstruit pas et ne demande aucun rôle web ni service supplémentaire.

Auteur : Maxime ROLLAND · Pulse myIT. Version 2.0 — 6 octobre 2026. [Documentation officielle](Sources.md) · [Licence MIT](LICENSE).
