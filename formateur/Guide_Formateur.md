# Automatisation Déploiement / PowerShell
## Guide formateur, corrigés et conduite de séance

Bachelor Réseau & Cybersécurité — Bac +3 — 3 jours — 6 octobre 2026.

**Ce dossier contient les corrigés formateur.** Pour distribuer les exercices sans solutions, transmettre uniquement `etudiant/`, `commun/`, `Maquette.md` et `Sources.md`. Les droits du dépôt s’appliquent à tous ses dossiers : cette organisation ne masque pas les corrigés aux personnes pouvant consulter le dépôt. Les scripts corrigés sont des références à expliquer progressivement ; ne pas lancer toute la configuration au début de J1. Le [support étudiant](../etudiant/Support_TP_Etudiant.md), la [maquette Mermaid](../Maquette.md) et ce guide sont complémentaires. Les scripts ont fait l'objet de contrôles de cohérence des sources, mais **aucune exécution de VM Windows ni recette AD/SMB/IIS n'a été réalisée dans l'environnement de production de ce pack**. Effectuer la répétition ci-dessous sur votre hyperviseur avant la séance ; ne pas présenter les scripts comme déjà validés sur votre image.

## 1. Préparation de la salle et répétition obligatoire

### Choix pédagogiques

Le cours travaille sous Windows PowerShell 5.1 pour disposer du moteur livré dans Windows Server Core et des modules Windows utilisés. PowerShell 7 reste une extension préparée à l'avance. Les trois VM sont en Core, y compris ADM01. Un éditeur graphique sur le poste physique reste autorisé ; aucun gestionnaire GUI de rôle serveur n'est nécessaire. AGDLP, les contrôles négatifs et le rollback donnent une dimension cybersécurité concrète au module.

La VM SRV01 regroupe fichiers et IIS pour tenir dans un hôte de 16 Go et dans 3 jours. Expliquer cette économie de laboratoire et la séparation qu'on étudierait en production. Aucun AD CS, DHCP, MDT/WDS, cloud, CI GitHub, SIEM ou DSC imposé ; ils augmenteraient la charge sans servir le cœur des 21 h.

### Avant J1 : check-list opérationnelle

- Prévoir un binôme par hôte, ou des réseaux isolés par binôme sur un hyperviseur central.
- Télécharger l'ISO Windows Server officielle, vérifier les règles d'utilisation et d'activation de l'évaluation, noter langue/édition/build et SHA256 local. Installer les mises à jour avant la séance.
- Valider l'accès console aux trois VM ; installer le Core (sans Desktop Experience) ; vérifier une seule NIC, IPv4 privées, RAM suffisante et espace de checkpoint.
- Distribuer des secrets de laboratoire hors dépôt, réserver un mot de passe DSRM distinct et noter les identités selon la langue de l'image.
- Copier le pack sur les trois VM dans C:\Lab et vérifier le BOM des scripts ; ne distribuer que le contenu étudiant/commun aux apprenants.
- Tester `powershell.exe` 5.1, `Get-CimInstance`, `Install-WindowsFeature` ; ne pas dépendre d'une installation de module en ligne pendant le cours.
- Désactiver les checkpoints automatiques Hyper-V pour un état pédagogique maîtrisé ; conserver des points S0/S1/S2 hors activité.
- Tester le transport des fichiers depuis l'éditeur physique : PowerShell Direct sous Hyper-V ou ISO de données ailleurs.
- Préparer une machine/maquette de secours S1 et S2 **construite et testée par vous**. Aucun disque de secours prêt à démarrer n'est inclus dans ce pack.
- Réserver 60–120 min à l'installation OS avant les 21 h ; au moins 2–3 h supplémentaires pour une répétition complète selon le matériel.

### Acheminer les fichiers hors Hyper-V

Sur un hôte Linux disposant de xorriso, générer un ISO de données (outil à installer/préparer avant la séance) :

```bash
xorriso -as mkisofs -J -r -V PSLABDATA -o PSLABDATA.iso /chemin/pack-etudiant
```

Monter ce fichier comme DVD dans la VM, identifier la lettre avec Get-Volume et copier les données vers C:\Lab. Pour une correction formateur, générer un ISO séparé ; ne pas distribuer les solutions dans l'ISO étudiant. Remonter une nouvelle image de données si l'étudiant rédige son code hors VM et doit l'importer. Sous Proxmox, créer des disques SATA et une NIC E1000 pour ce parcours sans pilotes supplémentaires. Les pilotes VirtIO et un modèle Windows automatisé constituent une extension de préparation, pas un prérequis pédagogique.

Le script New-LabVM crée les enveloppes VM, pas une installation Windows silencieuse. Aucun unattended.xml contenant un mot de passe n'est fourni. Pour industrialiser les installations OS ultérieurement, préparer un modèle généralisé avec Sysprep selon la procédure Microsoft ; ne pas cloner un contrôleur déjà promu. Les checkpoints de domaine doivent être restaurés en **ensemble cohérent**, hors activité, et non DC01 seul avec des membres de dates différentes.

## 2. Carte des fichiers et des dépendances

| Fichier | Lieu et moment d'exécution | Fonction | Prérequis |
|---|---|---|---|
| New-LabVM.ps1 | hôte Hyper-V, avant J1 | créer switch privé et 3 VM vides | module Hyper-V, ISO, admin hôte |
| Copy-LabToVM.ps1 | hôte Hyper-V | copier le pack par PowerShell Direct | VM Windows démarrée, credential local |
| 01-Initialize-Core.ps1 | console de chaque VM, S0 | IP/DNS/nom/WinRM | VM vierge à une NIC |
| 02-New-Forest.ps1 | console DC01, TP3 | forêt campus.test | admin local, DSRM SecureString |
| 03-Join-Domain.ps1 | console ADM01/SRV01, TP3 | joindre campus.test | DNS AD, credential de jointure |
| Lab.Common.psm1 | DC01/import local, TP5 | validation CSV pure | données du pack |
| 04-Sync-Directory.ps1 | DC01, TP5 | OU/groupes/comptes additifs | domaine et module AD |
| 05-Set-Shares.ps1 | SRV01, TP6 | ACL NTFS/SMB et pare-feu | groupes AD créés |
| 06-Get-Inventory.ps1 | ADM01, TP4 | inventaire Kerberos | S1 fonctionnel |
| 07-Initialize-IIS.ps1 | SRV01, TP7 | pool/site/ACL/port 8080 | admin membre |
| 08-Publish-Campus.ps1 | ADM01, TP7 | transfert/hash/bascule/rollback | IIS prêt, credential admin SRV01 |
| 09-Enable-Logging.ps1 | SRV01, TP9 | logging 5.1 et ACL logs | admin, nouvelle session ensuite |
| 10-Write-Health.ps1 | SRV01, sous-processus | rapport santé local et code retour | IIS ; aucune credential réseau |
| 10-Register-HealthTask.ps1 | SRV01, TP8 | tâche SYSTEM locale | script santé disponible |
| 11-Test-Lab.ps1 | ADM01, TP10, sous-processus | assertions automatiques partielles | santé/task initialisée |
| 12-Register-JEA.ps1 | SRV01, extension | endpoint lecture limitée | C:\LabOps/C:\LabLogs et GG_IT |

Tous les scripts Windows sont enregistrés UTF-8 BOM. Les PS1 ne doivent pas être concaténés dans un seul script : promotion, jointure et enregistrement JEA entraînent des changements de contexte et parfois des redémarrages. Lancer étape par étape ; conserver les preuves. Ne pas mélanger chemins relatifs du poste physique et chemins de la VM.

## 3. Runbook de répétition et corrigé exécutable

### Étage S0 : Core installé, noms/IP/DNS corrects

Sur l'hôte, depuis le dossier extrait :

```powershell
.\commun\preparation\New-LabVM.ps1 -IsoPath C:\ISO\WindowsServer.iso -WhatIf
.\commun\preparation\New-LabVM.ps1 -IsoPath C:\ISO\WindowsServer.iso
```

Installer les OS et copier le pack. Dans chaque console : `C:\Lab\commun\preparation\01-Initialize-Core.ps1 -Name <nom>` puis Restart-Computer. Vérifier le nom après redémarrage, aucune passerelle et DNS 10.77.10.10. Si une autre IP existe, le script arrête volontairement : diagnostiquer la carte/le modèle et corriger en console. Les scripts n'effacent pas une configuration réseau étrangère.

Éteindre proprement les trois VM et prendre S0-Core. Conserver un export de config par binôme. L'arrêt coordonné est utilisé pour une reprise pédagogique simple ; ce point n'est ni un backup System State ni une procédure de restauration d'entreprise.

### Étage S1 : forêt et membres

Sur DC01 en console, puis sur les membres séparément :

```powershell
Set-Location C:\Lab\formateur\corriges
$dsrm = Read-Host 'DSRM distinct' -AsSecureString
.\02-New-Forest.ps1 -DsrmPassword $dsrm
# Après redémarrage, se connecter en CAMPUS\<compte administrateur>.
Get-ADDomain
Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV

# Console ADM01 puis SRV01, admin local :
$join = Get-Credential -Message 'Compte de jointure CAMPUS'
& C:\Lab\formateur\corriges\03-Join-Domain.ps1 -Credential $join
Restart-Computer
```

Le script de forêt montre Test-ADDSForestInstallation et ne contourne pas ses précontrôles. Il refuse un DC déjà promu. Après redémarrage des membres, vérifier Test-ComputerSecureChannel et FQDN. Sur ADM01 connecté en admin du labo :

```powershell
$admin = Get-Credential -Message 'Compte administration CAMPUS'
& C:\Lab\formateur\corriges\06-Get-Inventory.ps1 -Credential $admin
& C:\Lab\formateur\corriges\06-Get-Inventory.ps1 -Credential $admin `
  -ComputerName dc01.campus.test,srv01.campus.test,adm01.campus.test,absent.campus.test `
  -OutPath C:\Lab\preuves\inventaire-avec-erreur.csv
```

Résultat attendu : trois OK, puis une ligne ECHEC pour absent. L'erreur ne bloque pas les autres hôtes. Vérifier que Get-PSSession ne conserve aucune session créée par le script. Prendre S1-Domaine après arrêt propre coordonné.

### Étage S2 : CSV, AD et accès

Sur DC01 :

```powershell
Set-Location C:\Lab\formateur\corriges
Import-Module .\Lab.Common.psm1 -Force
Test-LabCsv C:\Lab\commun\data\utilisateurs.csv
# Le prochain appel DOIT lever une erreur détaillée :
Test-LabCsv C:\Lab\commun\data\utilisateurs-invalides.csv
# Reprendre après cette erreur attendue.
.\04-Sync-Directory.ps1 -CsvPath C:\Lab\commun\data\utilisateurs.csv -WhatIf
$p = Read-Host 'Temporaire de la démonstration' -AsSecureString
.\04-Sync-Directory.ps1 -CsvPath C:\Lab\commun\data\utilisateurs.csv -InitialPassword $p |
  Export-Csv C:\Lab\preuves\ad-premier.csv -NoTypeInformation -Delimiter ';' -Encoding UTF8
.\04-Sync-Directory.ps1 -CsvPath C:\Lab\commun\data\utilisateurs.csv -InitialPassword $p |
  Export-Csv C:\Lab\preuves\ad-second.csv -NoTypeInformation -Delimiter ';' -Encoding UTF8
Get-ADUser -Filter * -SearchBase 'OU=Utilisateurs,OU=PSLAB,DC=campus,DC=test' |
  Select-Object SamAccountName
Get-ADGroupMember GG_IT
Get-ADGroupMember DL_IT_M
```

Attendus : six utilisateurs et six groupes sous l'OU du TP, deux personnes dans chaque GG et un GG dans chaque DL. Au second passage, Etat=Existant pour les six comptes ; aucune remise à zéro du mot de passe. Une nouvelle exécution avec le CSV invalide refuse avant toutes mutations. Comparer le nombre et les DN avant/après.

La fonction Test-LabCsv accumule les erreurs et retourne les lignes si tout est valide. La garde de domaine évite une exécution accidentelle dans un autre AD. Les collisions de nom ou changements de Department arrêtent le script ; ils ne sont pas corrigés automatiquement. L'absence de transactions AD est assumée. Les OU ne sont pas filtrées par seul nom, mais par DN.

Préparer Alice et Chloé avec deux mots de passe individuels saisis hors transcript, puis retirer ChangePasswordAtLogon pour ces deux seuls tests comme expliqué dans le support. Sur SRV01 :

```powershell
& C:\Lab\formateur\corriges\05-Set-Shares.ps1 -WhatIf
& C:\Lab\formateur\corriges\05-Set-Shares.ps1
Get-SmbShare -Name 'IT$','RH$','Direction$' | Select-Object Name,Path,EncryptData,FolderEnumerationMode
Get-SmbShareAccess -Name 'IT$'
(Get-Acl C:\LabData\IT).Sddl
Get-NetFirewallRule -Name PSLAB-SMB | Get-NetFirewallAddressFilter
```

Le script remplace les ACL des trois dossiers du TP et converge la liste SMB vers le seul groupe prévu. Il conserve les SID SYSTEM/Administrateurs pour NTFS ; il ne donne pas FullControl SMB aux utilisateurs. Ce remplacement est volontairement réservé aux dossiers neufs C:\LabData. Si un partage homonyme pointe ailleurs, il refuse ; ne pas contourner la garde par suppression automatique.

Le test d'accès se fait depuis ADM01 via consoles runas /netonly séparées, comme dans le support. Réussir IT avec Alice et RH avec Chloé ; refuser tous les autres accès du tableau. Capturer la preuve d'erreur réelle, pas uniquement une lecture d'ACL. Prendre S2-Acces après arrêt propre.

### Étage S3 : IIS, publication et échec

Sur SRV01 :

```powershell
& C:\Lab\formateur\corriges\07-Initialize-IIS.ps1
Invoke-WebRequest http://localhost:8080/index.html -UseBasicParsing
Import-Module WebAdministration
Get-Website -Name Campus
```

Sur ADM01 :

```powershell
$adminSrv = Get-Credential -Message 'Compte administrateur SRV01 du laboratoire'
$publish = 'C:\Lab\formateur\corriges\08-Publish-Campus.ps1'
& $publish -ReleasePath C:\Lab\commun\releases\v1 -Credential $adminSrv -WhatIf
& $publish -ReleasePath C:\Lab\commun\releases\v1 -Credential $adminSrv
& $publish -ReleasePath C:\Lab\commun\releases\v2 -Credential $adminSrv
& $publish -ReleasePath C:\Lab\commun\releases\v2 -Credential $adminSrv
Invoke-WebRequest http://srv01.campus.test:8080/index.html -UseBasicParsing
```

La v2 répétée conserve le même répertoire ; si son contenu diffère, le numéro de version est considéré immuable et refusé. Le manifeste n'accepte que version vN, fichier index.html et hash hexadécimal de 64 caractères. Ne pas utiliser les données pour construire/exécuter une commande arbitraire. Le staging unique évite les collisions de copies. La session est toujours fermée en finally. Les releases précédentes sont conservées.

Test d'altération locale : copier v2 vers C:\Lab\corrompu, ajouter du texte dans index.html, conserver le manifeste et lancer le script. Le refus précède la session de publication. Le site reste v2.

Test de rollback fonctionnel : créer v3 en copiant vbad comme dans le support, changer Version dans son manifeste, conserver le hash du fichier. Le hash passe, le serveur bascule vers v3, HTTP retourne du contenu mais pas le marqueur Campus - v3, la tentative échoue et le chemin revient à v2. Conserver l'erreur du script, le physicalPath et la réponse depuis ADM01. **L'appel direct avec vbad est refusé par la validation vN ; il ne teste pas le rollback.**

Retour manuel : sur SRV01 avec module WebAdministration, mémoriser le chemin, `Set-ItemProperty IIS:\Sites\Campus -Name physicalPath -Value C:\LabWeb\releases\v1`, tester, puis repointer vers v2. Le rollback ne répare pas un service Windows arrêté ni une mauvaise règle réseau.

### Étage S4 : tâche, logs et recette

Sur SRV01 :

```powershell
& C:\Lab\formateur\corriges\10-Register-HealthTask.ps1
# Attendre le premier achèvement, au maximum 30 secondes dans la répétition.
Get-ScheduledTaskInfo -TaskName PSLAB-Health
Get-Content C:\LabReports\health.json -Raw | ConvertFrom-Json
# Si le rapport manque, lire l'erreur de tâche au lieu de créer un faux succès.
```

Pour attendre proprement, boucler toutes les secondes jusqu'à présence d'un rapport nouveau ou timeout 30 s. Lire LastRunTime/LastTaskResult ; LastTaskResult peut être provisoire pendant Running. Le rapport de santé doit être frais (moins de 10 min pour la recette). La tâche a une action locale, un chemin absolu et un exécutable 5.1, sans ExecutionPolicy Bypass ni credential stockée.

Test négatif : arrêter W3SVC en console SRV01 ; Start-ScheduledTask PSLAB-Health ; attendre fin ; constater Healthy=false et LastTaskResult=1 ; relancer W3SVC puis la tâche ; constater Healthy=true et 0. La tâche SYSTEM est limitée à un script et des rapports locaux dont l'ACL interdit la modification ordinaire. Elle n'est pas un modèle universel de moindre privilège.

Activer la journalisation, puis ouvrir une nouvelle session distante :

```powershell
# Sur SRV01 :
& C:\Lab\formateur\corriges\09-Enable-Logging.ps1
# Sur ADM01, nouvelle session :
$s = New-PSSession srv01.campus.test -Authentication Kerberos -Credential $adminSrv
Invoke-Command -Session $s {'TP9-CAMPUS'; Get-Service W3SVC}
Remove-PSSession $s
# Sur SRV01 :
Get-WinEvent -FilterHashtable @{
  LogName='Microsoft-Windows-PowerShell/Operational';Id=4104
  StartTime=(Get-Date).AddMinutes(-15)
} | Where-Object Message -like '*TP9-CAMPUS*' | Select-Object TimeCreated,Id,Message
Get-ChildItem C:\LabLogs -Recurse
```

Lecture et écriture des logs sont ici limitées à administrateurs/SYSTEM. Si l'on étend la transcription aux utilisateurs ordinaires, concevoir des ACL d'écriture/collecte adaptées plutôt qu'ouvrir tout le dossier en lecture. Une GPO de domaine peut modifier ces paramètres locaux : documenter la stratégie effective. Ces paramètres visent Windows PowerShell 5.1 ; ne pas supposer qu'ils configurent tous les moteurs 7.

Sur ADM01, lancer la recette dans un processus séparé, car elle utilise exit :

```powershell
# Le processus enfant demandera la credential. Pas de mot de passe en ligne de commande.
powershell.exe -NoProfile -Command "& 'C:\Lab\formateur\corriges\11-Test-Lab.ps1' -Credential (Get-Credential)"
$LASTEXITCODE
Get-Content C:\Lab\preuves\recette.json -Raw | ConvertFrom-Json
```

Le test automatique attend six comptes, six groupes, Core, domaine, pare-feu actif, WinRM Kerberos, trois partages chiffrés, une tâche saine et HTTP depuis ADM01. Il ne teste pas tout : lire le tableau R01–R14 du support et compléter l'imbrication des groupes, les ACL, les portées des règles, les essais négatifs, le rollback et les logs. Ne pas convertir cette recette partielle en certification cybersécurité.

## 4. Conduite de séance et différenciation

### J1 — Objeter, découvrir, joindre, administrer

Début : faire identifier la machine et l'identité avant chaque action ; beaucoup d'erreurs sont dues au contexte, pas à PowerShell. Diagnostic oral 10 min : IP vs nom, DNS, rôle, service, permission. Démonstration 15 min : Get-Service, Get-Member, Where/Select/Export, erreur de Format-Table. Les étudiants réalisent TP1 avec de courts pipelines puis une fonction.

Pendant TP2, demander une preuve d'état et une explication des règles ; l'utilisation du script de préparation n'est pas évaluée comme du développement. Leur travail est le contrôleur local et le diagnostic. Si S0 n'est pas prêt, fournir la maquette préparée ; ne pas engloutir la journée dans les installations.

TP3 est guidé : forêt et jointure ont des effets structurants. Exiger lecture de préconditions et identification des redémarrages. TP4 est semi-guidé : seules les commandes WinRM de départ sont fournies, les étudiants écrivent leur collecte et leur traitement de cible absente. Valider S1 avant départ.

### J2 — Données, idempotence et sécurité d'accès

Rappel 20 min : différence état désiré/convergence/transaction. Faire passer **d'abord le CSV invalide** ; un groupe qui commence à créer avant d'avoir validé les lignes doit revoir son algorithme. Fournir l'ossature si besoin, jamais un reset global AD comme solution rapide.

Encourager les sorties d'objets : un tableau de résultats est plus contrôlable qu'un Write-Host « terminé ». À l'issue TP5, faire dessiner les appartenances en une phrase : Alice → GG_IT → DL_IT_M → Modify sur IT. Tester le deuxième passage devant le formateur.

TP6 : donner le constructeur ACL si sa syntaxe détourne du sujet ; évaluer la compréhension des droits effectifs. Les étudiants doivent effectuer les tests depuis une identité réseau ordinaire. Si tous les tests sont faits en Domain Admin, aucune preuve d'isolation n'est acquise. Insister sur runas /netonly et son whoami local trompeur.

### J3 — Livraison maîtrisée et exploitation

Démontrer que HTTP 200 n'est pas suffisant : v3 peut renvoyer une page valide mais incorrecte. Le contrôle du marqueur fournit un critère fonctionnel simple. Faire relier l'erreur à la restauration du physicalPath. Ne pas présenter cette bascule de fichier statique comme un déploiement universel de logiciels métier.

TP8 relie privilège du principal et intégrité du code de tâche. TP9 impose une hypothèse testée ; corriger au hasard ou désactiver le pare-feu ne constitue pas une démarche. TP10 exige la recette complète avec tests manuels et un court oral individuel.

### Variante débutants et installation pendant le cours

Si les OS doivent être installés à J1, réserver les 100 min du TP2 à l'installation et initialisation ; donner la fonction d'inventaire de TP4 sous forme guidée, et son exercice d'erreur en devoir. Fournir les constructeurs ACL de TP6 et le squelette de publication plus avancé. Garder les vérifications CSV, accès, hash et rollback. Cette variante réduit l'écriture autonome : annoncer explicitement ce compromis. Elle ne permet pas d'ajouter JEA dans les 21 h.

Pour les avancés, JEA ou tests de validation servent d'extension pendant les périodes d'aide des autres groupes. Ne pas imposer Pester téléchargé en séance ou DSC à tous. Pour la formation continue, on peut découper en trois séquences indépendantes S0→S1, S1→S2 et S2→S4.

## 5. Corrigé conceptuel des questions

| Sujet | Réponse attendue |
|---|---|
| Core vs PowerShell 7 | Core est un mode d'installation Windows ; 5.1 est le moteur natif utilisé. pwsh peut coexister, endpoints distincts. |
| Pipeline | transfère des objets ; Where filtre, Select projette, Sort classe. Format est réservé au rendu final. |
| Get-Member | révèle propriétés/méthodes et type ; évite de deviner la structure à partir de l'affichage. |
| PS1 UTF-8 BOM | 5.1 peut lire UTF-8 sans BOM comme encodage local ; accents corrompus possibles. CSV lu explicitement UTF8. |
| Scope Process | changement de politique pour le processus courant ; GPO prioritaire ; ce n'est pas une protection contre un attaquant. |
| catch | attrape les erreurs terminantes ; ErrorAction Stop rend terminante une erreur de cmdlet non terminante. |
| finally | fermeture des ressources même si erreur ; ne répare pas automatiquement l'état métier. |
| WhatIf | support explicite de ShouldProcess ; tests réels et permissions restent nécessaires. |
| DNS AD | enregistrements SRV nécessaires à la découverte ; le DNS public ne connaît pas campus.test. |
| FQDN pour WinRM | permet Kerberos et vérification d'identité ; l'IP ne fournit pas le même chemin Kerberos ordinaire. |
| HTTP WinRM | chiffrement du message avec Kerberos ; 5986 ajoute TLS. Basic ou AllowUnencrypted ne sont pas requis. |
| Second saut | credential de l'utilisateur non librement déléguée ; Copy-Item -ToSession depuis ADM évite un troisième système. |
| Désérialisation | propriétés souvent conservées, méthodes non utilisables comme l'objet local ; exécuter l'action sur la cible. |
| DSRM | secret de restauration du DC ; distinct, sensible, jamais dans les scripts ni preuves. |
| OU / groupe | OU organise/délègue/applique stratégies ; groupe porte les appartenances et autorisations. |
| CSV validé d'abord | empêche les mutations dues à une entrée mal formée ; n'annule pas les pannes ultérieures. |
| AGDLP | comptes dans GG métier, GG dans DL ressource, DL dans ACL ; simplifie les changements et audits. |
| Deuxième passage | comptes/mots de passe conservés ; n'est pas la preuve d'une convergence intégrale. |
| SMB + NTFS | accès réseau limité par les deux ACL ; permissions locales et réseau ne sont pas identiques. |
| Modify | lecture/écriture/suppression ; FullControl ajoute notamment gestion des droits et propriété. |
| SID | identifie sans dépendre de la traduction du nom intégré Windows. |
| Partage caché | $ réduit la visibilité ; seule l'ACL sécurise l'accès. |
| Erreur 1219 | Windows limite les identités SMB simultanées dans un même contexte ; isoler les consoles réseau. |
| runas /netonly | identité locale inchangée ; réseau avec la credential indiquée ; whoami ne démontre pas l'identité SMB. |
| Hash | détecte l'écart à une référence maîtrisée ; aucune preuve d'auteur si hash et fichier peuvent être remplacés. |
| Rollback | remet ancien physicalPath après échec fonctionnel ; pas de réparation Windows ni de transaction de base de données. |
| Tâche SYSTEM | privilèges élevés, code et paramètres doivent être non modifiables par un utilisateur ordinaire. |
| LASTEXITCODE | code du dernier processus natif ; $? indique succès de la dernière opération PowerShell. |
| Health frais | rapport horodaté récent et nouvelle exécution, sinon vieux succès possible. |
| Logs | traces utiles mais sensibles et incomplètes ; contrôler collecte, accès, conservation et configuration. |
| Incident | hypothèses discriminantes puis correction minimale et même test rejoué. |

## 6. Scénarios d'incident : injection et retour

Choisir un seul incident par binôme ; noter l'heure et l'état initial. N'injecter aucune panne destructive. Les commandes ci-dessous sont exclusivement prévues pour la maquette isolée, en console admin. Garder la console ouverte pendant la correction. Arrêter l'expérience si elle perturbe un autre groupe.

### Incident A — DNS client erroné, ADM01

Avant mutation, sauvegarder la liste des DNS et l'ifIndex dans une variable/compte rendu. Le réseau attend une seule NIC :

```powershell
# Console ADM01 uniquement.
$nic = Get-NetAdapter | Where-Object Status -eq Up
$beforeDns = (Get-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4).ServerAddresses
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses 10.77.10.254
Clear-DnsClientCache
# Pour déclencher une vraie interrogation malgré un cache éventuel :
Resolve-DnsName '_ldap._tcp.dc._msdcs.campus.test' -Type SRV -Server 10.77.10.254 -DnsOnly
# Rétablissement, par étudiant ou formateur :
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $beforeDns
Clear-DnsClientCache
```

Symptôme : IP joignable mais DNS du domaine inaccessible. Le cache peut masquer provisoirement l'incident ; proposer un test contre le serveur DNS configuré plutôt que prétendre que toute résolution échouera immédiatement. Ne pas effacer SYSVOL ou modifier la zone AD.

### Incident B — Service HTTP arrêté, SRV01

```powershell
Stop-Service W3SVC
# Vérifications apprenants : Get-Service, TCP 8080, HTTP et rapport santé.
# Retour :
Start-Service W3SVC
Start-ScheduledTask -TaskName PSLAB-Health
```

Symptôme : WinRM et DNS fonctionnent, intranet indisponible, santé fausse. Un rollback de fichier ne redémarre pas le service. Ne pas arrêter NTDS/DNS pour cet incident court.

### Incident C — Fichier altéré, SRV01

Mémoriser le hash et créer une copie de l'index v2 en dehors du site avant de l'altérer. Ajouter un texte différent ou retirer le marqueur. HTTP peut rester 200 : distinguer disponibilité et conformité de contenu. Rétablir **les octets sauvegardés**, vérifier SHA256 contre le manifeste de confiance sur ADM01 et relancer le contrôle. Ne pas recalculer simplement le manifeste pour « faire passer le test » : cela supprimerait la référence d'intégrité.

### Évaluation de l'incident

Accorder les points sur méthode et preuve : symptôme clair, hypothèses, tests discriminants, correction ciblée, revalidation. Une bonne correction sans explication obtient une partie des points seulement ; un diagnostic prouvé avec aide à la dernière commande peut obtenir la majorité des points.

## 7. Évaluation sur 100 points

| Axe | Points | Preuves |
|---|---|---|
| Core/réseau/domaine | 15 | versions, IP/DNS, jointures, sessions |
| Objets, fonctions et inventaire | 15 | objets exportables, erreur cible, finally |
| Validation et provisioning AD | 20 | CSV invalide, WhatIf, six comptes/groupes, second passage |
| SMB/NTFS et contrôle d'accès | 15 | ACL, AGDLP, six tests réels, pare-feu |
| Déploiement et rollback | 15 | v1/v2, hash, v3 échec, retour v2 |
| Santé, logs et incident | 10 | tâche protégée, codes, rapport récent, cause prouvée |
| Documentation et oral individuel | 10 | runbook sans secrets, limites, explication personnelle |
| Total | 100 | Conversion /20 : diviser par 5 |

Répartir documentation/oral en 5 points binôme et 5 points individuels. Pour personnaliser la note, l'enseignant peut affecter une question individuelle supplémentaire à un axe technique, en conservant le total. Le simple usage de l'IA n'est pas une pénalité ; l'incapacité à expliquer le résultat l'est dans l'oral. Ne pas attribuer les points de sécurité lorsqu'une réussite dépend de la désactivation du pare-feu, de TrustedHosts * ou d'une identité privilégiée pour tous les tests.

Seuils conseillés : 50/100 acquis minimum, 70 autonome, 85 maîtrise et explication des limites. Les extensions ne sont pas nécessaires à 100/100 ; bonus plafonné de 5 points sans dépasser 100, selon politique de l'établissement. Les étudiants doivent connaître les règles avant J1.

Une grille CSV imprimable/éditable se trouve dans ce dossier ; saisir les scores et commentaires. Le modèle ne calcule pas de note automatiquement dans un CSV : utiliser la formule équivalente dans votre tableur, ou additionner les sept axes.

## 8. Extension JEA : mise en place et correction

Préparer sur SRV01, après santé et logs :

```powershell
& C:\Lab\formateur\corriges\12-Register-JEA.ps1
# Le redémarrage de WinRM peut couper les sessions courantes.
# Depuis une NOUVELLE console/session ADM01 :
$alice = Get-Credential -UserName 'CAMPUS\alice.martin' -Message 'Compte IT ordinaire'
$j = New-PSSession -ComputerName srv01.campus.test -Authentication Kerberos `
  -ConfigurationName CampusRead -Credential $alice
Invoke-Command -Session $j {Get-Service -Name W3SVC}
Invoke-Command -Session $j {Restart-Service -Name W3SVC} # REFUS attendu
Invoke-Command -Session $j {Get-ChildItem C:\} # REFUS attendu
Remove-PSSession $j
```

Le rôle n'expose que Get-Service avec Name limité. Le compte virtuel exécute sous privilèges temporaires locaux ; la contrainte de commandes est donc cruciale. Ne pas autoriser des chemins, ScriptBlock ou outils exécutant du code arbitraire. Le transcript s'écrit sous le contexte d'exécution protégé. Alice n'a pas besoin d'être admin locale. L'accès au endpoint JEA ne donne pas un accès général au endpoint Microsoft.PowerShell. Tester aussi que Chloé ne peut pas ouvrir CampusRead.

Cette configuration doit rester sur SRV01 membre. Sur un contrôleur, les comptes virtuels peuvent avoir des privilèges de domaine : ce n'est pas une variation anodine. La validation de fichiers JEA vérifie leur structure, pas leur sûreté complète ; rejouer tous les refus.

Nettoyage extension : `Unregister-PSSessionConfiguration -Name CampusRead -Force` en console SRV01, puis vérifier les sessions. Pour le socle, il est plus simple de conserver le labo jusqu'à la soutenance puis d'arrêter/archiver la maquette.

## 9. Nettoyage et remise à zéro

À la fin, récupérer scripts et preuves expurgés, puis arrêter les VM. Dans une salle individuelle, le formateur restaure les checkpoints cohérents ou recrée les VM. **Aucun script de suppression automatique de la forêt ou des VM n'est fourni** : les opérations destructives restent des choix explicites d'exploitation. Éviter Restore-Checkpoint DC01 seul en activité. Les secrets de séance sont invalidés à la destruction du laboratoire ; ne jamais les réutiliser en entreprise.

Définir une conservation pédagogique courte des logs (par exemple jusqu'à correction puis suppression selon la politique de l'école) ; adapter à la règle de l'établissement. Conserver uniquement les extraits nécessaires au dossier de notation. Une conservation d'exemple ne remplace pas une politique de protection des données.

## 10. État de validation du pack et points à répéter

Contrôles réalisés sur les sources : arborescence et liens Markdown locaux, présence des scripts, BOM PS1/PSM1, colonnes CSV, empreintes de releases et manifeste des fichiers, durée totale, exclusion des formats PDF/Word/image et diagrammes Mermaid. Les commandes ont été revues contre les références officielles disponibles. Voir [CONTROLE.md](../CONTROLE.md).

Contrôles **à réaliser sur Windows avant distribution** : analyse syntaxique 5.1, disponibilité des cmdlets/modules, bootstrap avec la langue retenue, forêt/jointure, pare-feu, tests SMB sous comptes métiers, IIS et rollback v3, déclencheur de tâche/LastTaskResult, journalisation sur nouvelle session, recette et JEA optionnel. Le script de parse seule ci-dessous détecte les erreurs de syntaxe sans exécuter les mutations :

```powershell
# Sur un poste Windows PowerShell 5.1 ; adapter le dossier du pack.
$failed = $false
Get-ChildItem C:\Lab -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
  $tokens = $null; $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) {
    $failed = $true
    Write-Output $_.FullName
    $parseErrors | Select-Object Message,Extent
  }
}
if ($failed) {throw 'Corriger la syntaxe avant la répétition.'}
```

Documenter dans `RECETTE-AVANT-COURS.md` les versions, résultats et corrections de votre répétition. Ne pas confondre un contrôle éditorial local et un test d'intégration exécuté dans un environnement Windows.
