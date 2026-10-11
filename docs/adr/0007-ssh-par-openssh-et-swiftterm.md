# ADR 0007 — SSH par l'OpenSSH du système, dans un terminal SwiftTerm

Date : 2026-10-10 · Statut : accepté, à réévaluer après les premiers essais

## Contexte

Le cahier des charges prévoyait une bibliothèque SSH en Swift, avec profils, secrets dans le Keychain,
vérification des clés d'hôte, exécution de commandes, terminal et SFTP, précédés d'un prototype isolé.
Ce prototype n'a pas pu être mené : le code est écrit sans compilateur Swift. Une pile SSH complète
(négociation, authentification, canaux, émulation de terminal) écrite à l'aveugle aurait eu peu de
chances de fonctionner, sur le module où une erreur coûte le plus cher en sécurité.

## Décision

Pingouin lance `/usr/bin/ssh` et `/usr/bin/sftp`, fournis par macOS, dans un pseudo-terminal affiché
par la bibliothèque SwiftTerm (licence MIT), fixée à la série 1.10 (`upToNextMinorVersion` depuis
1.10.1). Cette série a été retenue parce qu'elle ne contient pas de module d'extension de compilation
(constaté dans les versions 1.13 à 1.20, où Xcode demande de l'approuver) et qu'elle n'a qu'une
dépendance. L'interface utilisée a été relue dans le code source de cette version.

Pingouin n'enregistre que le profil : nom, hôte, port, utilisateur, chemin du fichier de clé, thème.

## Conséquences

- Chiffrement, authentification et clés d'hôte sont ceux d'OpenSSH, tenus à jour par macOS.
  `~/.ssh/config`, `~/.ssh/known_hosts`, l'agent SSH et les clés gardées dans le Trousseau par
  `ssh-add --apple-use-keychain` fonctionnent sans code supplémentaire.
- `StrictHostKeyChecking=ask` est imposé : une clé inconnue demande l'accord de l'utilisateur dans le
  terminal, une clé modifiée bloque la connexion.
- Mot de passe (ajout du 2026-10-10) : il peut être enregistré dans le Trousseau, par connexion.
  OpenSSH ne lisant pas le Trousseau, Pingouin surveille l'affichage du terminal et saisit le mot de
  passe quand la demande d'OpenSSH apparaît, une seule fois par session. L'autre voie, un programme
  auxiliaire désigné par `SSH_ASKPASS`, est plus propre mais demande un exécutable supplémentaire
  dans l'application ; à étudier si la reconnaissance par le texte se montre fragile.
- Pas d'exécution de commande avec récupération du résultat.
- Un seul onglet par machine (12 au plus), que sa session soit ouverte ou terminée : il porte le
  terminal et le navigateur de fichiers. Une session terminée est relancée dans le même onglet.
- Navigateur de fichiers (ajout du 2026-10-11) : chaque action lance `/usr/bin/sftp` en mode
  commandes (`-b -`), qui emprunte la connexion du terminal de l'onglet par le partage de connexion
  d'OpenSSH (`ControlMaster`, point de rendez-vous dans le dossier temporaire, sans persistance).
  Le navigateur ne s'authentifie donc jamais lui-même : mot de passe et clé d'hôte ne passent que
  par le terminal, et aucun programme auxiliaire n'est nécessaire.
  - La liste est lue avec `ls -lan`, dont le format est composé par le client `sftp` lui-même.
  - `sftp` interprète les guillemets, « \ », « * », « ? » et « [ » dans un chemin : un nom qui en
    contient est affiché, mais aucune commande n'est construite avec lui.
  - Un transfert à la fois (un serveur limite les canaux d'une connexion, 10 par défaut).
    Un téléchargement arrive dans un fichier provisoire, renommé à la fin ; rien n'est remplacé
    sur le Mac. Un envoi qui remplacerait un élément distant demande un accord.
  - Limites connues : l'avancement n'est mesuré que pour le téléchargement d'un fichier (`sftp`
    n'en donne pas en mode commandes) ; seuls les dossiers vides peuvent être supprimés ; les
    messages d'erreur de `sftp` sont en anglais.
- Première dépendance tierce du projet ; Xcode doit la télécharger au premier lancement.
- L'application n'étant pas dans le bac à sable (ADR 0002), lancer un processus système est permis.

## À réévaluer

Si l'exécution de commandes en lot (automatisation) devient nécessaire, ou si le navigateur de
fichiers bute sur les limites de la commande `sftp` (noms à caractères spéciaux, avancement des
envois), prototyper une bibliothèque SSH en Swift sur le Mac, puis décider.
