# Utiliser l'IA pendant le TP

[Accueil](README.md) · [Évaluation](EVALUATION.md)

L'IA est autorisée pour expliquer une commande, proposer un algorithme, commenter votre code, diagnostiquer une erreur ou écrire une fonction. Les corrections du dépôt sont également accessibles. Vous êtes évalué sur ce que votre maquette fait et sur ce que vous comprenez.

## Une méthode en cinq actions

1. Donner à l'IA votre objectif, le moteur **Windows PowerShell 5.1**, le domaine `learn-it.local` et le lieu d'exécution. Dire que le domaine existe déjà.
2. Demander une explication de l'algorithme et des mutations avant d'exécuter le code.
3. Vérifier les cmdlets et paramètres avec Get-Help/Get-Command ou la documentation Microsoft.
4. Tester sur les données fictives : cas normal, entrée invalide, relance et bonne/mauvaise identité réseau.
5. Corriger puis expliquer le résultat avec vos mots. Une proposition qui semble plausible mais ne passe pas vos tests doit être adaptée ou rejetée.

Ne transmettre aucun mot de passe ni donnée réelle à l'IA. Vous pouvez partager les identifiants fictifs et messages d'erreur du TP après avoir retiré les éléments sensibles.

## Prompts utiles

```text
Explique ce bloc PowerShell 5.1 instruction par instruction. Pour chaque commande,
précise sur quelle machine elle s'exécute, ce qu'elle lit, ce qu'elle modifie et
quel test me permet de vérifier son résultat. Ne change pas le périmètre du TP.
```

```text
Je veux valider toutes les lignes d'un CSV avant de créer quoi que ce soit dans
AD. Le domaine learn-it.local existe déjà. Propose un algorithme qui détecte
les doublons et les services inconnus, puis explique comment le tester.
```

```text
Voici l'erreur réelle de mon script et le résultat attendu. Propose deux
hypothèses et une commande de diagnostic pour chacune. Ne désactive pas
globalement le pare-feu et ne remplace pas l'identité de test par Domain Admin.
```

## Vérifier votre compréhension

Avant votre démonstration, entraînez-vous à répondre à ces questions en retrouvant le bloc de code concerné :

- Quelle machine crée le compte ?
- Pourquoi notre script doit-il résoudre le nom du DL avant de construire son ACE ?
- Que fait finally ?
- Pourquoi whoami reste-t-il inchangé avec /netonly ?
- Quel contrôle refuse un compte sans le préfixe tp. ?
- Que se passe-t-il si AD crée un compte désactivé ?

La bonne réponse n'est pas la récitation de tout le script. Il faut pouvoir repérer le bloc concerné, expliquer sa décision et montrer le test correspondant.

Dans le bilan, garder seulement un exemple de proposition IA utile et un exemple de suggestion vérifiée/corrigée. Aucun historique exhaustif de prompts n'est demandé.
