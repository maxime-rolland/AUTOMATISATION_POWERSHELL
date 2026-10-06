# Évaluation simple — 20 points

[Accueil](README.md) · [Déroulé de démonstration](docs/05-Pilotage-et-demonstration.md) · [Grille CSV](evaluation.csv)

**IA et corrigés autorisés.** La note dépend du résultat démontré et de la compréhension. Chaque critère vaut de 0 à 4 points. Les preuves se font sur la maquette, avec le fichier de configuration du binôme et ses vrais objets.

| Critère | Points | Pour obtenir 4 points |
|---|---|---|
| 1. Automatisation fonctionnelle | /4 | Une commande lit le CSV, crée/conserve les comptes et groupes, configure les deux partages et rend un rapport utilisable |
| 2. Relance maîtrisée | /4 | Rejouer sans doublons ni remise à zéro des mots de passe ; les comptes, groupes, partages et accès restent corrects |
| 3. Droits réellement testés | /4 | Alice IT oui/RH non ; Chloé RH oui/IT non ; tests effectués avec les bonnes identités réseau et serveur joignable |
| 4. Erreurs et adaptation | /4 | CSV invalide refusé sans ajout, cible inaccessible signalée, reprise correcte et petite adaptation utile montrée |
| 5. Compréhension individuelle | /4 | Chaque étudiant explique le lieu d'exécution, une condition/boucle, le traitement d'erreur et une limite, puis sait modifier un élément demandé |
| **Total** | **/20** | **Les quatre premiers critères portent sur le binôme ; le cinquième est individuel** |

## Barème applicable à chaque critère

| Score | Observation |
|---|---|
| 0 | Non montré ou aucun résultat exploitable |
| 1 | Début de résultat, blocage majeur ou correction manuelle systématique |
| 2 | Résultat partiel ; une partie fonctionne mais des preuves importantes manquent |
| 3 | Résultat correct avec une petite lacune ou une aide ponctuelle |
| 4 | Résultat complet, vérifié et expliqué avec autonomie |

Pour les droits, une démonstration uniquement sous administrateur ne prouve pas l'isolation métier. Pour la relance, lire EXISTANT dans le rapport ne remplace pas la vérification des objets. Pour les erreurs, un refus réseau dû à un serveur éteint n'est pas une preuve d'ACL.

L'IA peut écrire ou corriger le code ; cela ne retire pas de point. Un étudiant qui ne peut pas expliquer le code qu'il exécute perd les points correspondant à sa compréhension. Les extensions COM, outils supplémentaires ou présentations longues ne sont pas nécessaires pour obtenir 20/20.

## Fiche de passage

Binôme : … · LabId : … · Étudiant : … · Date : …

| Fonctionnement /4 | Relance /4 | Droits /4 | Erreurs/adaptation /4 | Compréhension /4 | Total /20 |
|---|---|---|---|---|---|
| | | | | | |

Observation utile : …
