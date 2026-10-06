#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$ReleasePath,[pscredential]$Credential)
# TODO: valider manifest et SHA256 local; -WhatIf; PSSession directe;
# copier avec -ToSession; valider SHA256 distant; memoriser physicalPath;
# basculer IIS; verifier HTTP + contenu; remettre ancien chemin en cas d'echec.
# TODO: finally pour fermer session; ne jamais supprimer les versions precedentes.
throw 'Squelette a completer dans le TP7.'
