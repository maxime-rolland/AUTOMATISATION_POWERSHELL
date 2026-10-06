#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$CsvPath,[securestring]$InitialPassword)
$ErrorActionPreference='Stop'
# TODO 1: importer et valider TOUTES les lignes, avant toute mutation.
# TODO 2: refuser un domaine autre que campus.test.
# TODO 3: creer les OU et groupes uniquement s'ils n'existent pas.
# TODO 4: creer les utilisateurs absents; jamais reinitialiser les existants.
# TODO 5: traiter -WhatIf sans demander de mot de passe ni modifier AD.
# TODO 6: retourner des objets SamAccountName/Department/Etat.
throw 'Squelette a completer dans le TP5.'
