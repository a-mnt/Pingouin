# ADR 0013 — SSH et SFTP sur iOS

- Date : 2026-10-11
- Statut : accepté (écrit, ni compilé ni essayé au moment de sa livraison)

## Contexte

La version Mac lance les commandes `ssh` et `sftp` du système (ADR 0007). iOS n'a pas ces commandes
et ne laisse pas une application en lancer : il faut une bibliothèque qui parle le protocole SSH
elle-même. Ce qu'OpenSSH faisait pour nous sur le Mac revient alors à notre charge : vérifier la
clé du serveur, garder la clé privée, s'authentifier.

## Décision

- **Bibliothèque : Citadel 0.12.1** (orlandos-nl), en version exacte. Elle est écrite en Swift,
  s'appuie sur SwiftNIO SSH, et fournit le terminal interactif (pseudo-terminal, redimensionnement)
  et le client SFTP (lister, lire, écrire, créer un dossier, renommer, supprimer). La version est
  figée parce que le code a été écrit en lisant celle-là, sans compilateur.
- **Terminal : SwiftTerm**, déjà utilisé sur le Mac, dans sa vue UIKit. Sa barre de touches
  (échap, tab, ctrl, flèches) est reprise telle quelle.
- **Citadel reste enfermée dans `SSHLink`.** Ses objets ne sont pas faits pour passer d'un fil
  d'exécution à l'autre ; aucun ne sort de cette classe, qui n'échange avec le reste de
  l'application que des valeurs simples. Les frappes passent par une file unique, pour arriver
  dans l'ordre.
- **Clé du serveur : accord explicite à la première connexion, refus si elle change.**
  `HostKeyProbe` n'accepte que la clé déjà enregistrée pour « hôte:port ». Sinon la connexion
  échoue, et la clé présentée est montrée : inconnue, l'utilisateur voit son empreinte et peut
  l'accepter ; différente de celle connue, la connexion est refusée sans bouton pour passer outre.
  Le seul moyen de l'accepter est de retirer l'hôte dans Réglages › SSH › Hôtes connus. La logique
  est dans `KnownHostsBook` (PingouinCore, testée) ; la liste est dans `hotes-connus.json`, qui
  ne contient que des clés publiques.
- **Authentification : mot de passe, ou clé Ed25519 de l'appareil.** La clé est créée dans
  l'application ; sa partie privée est rangée dans le Trousseau avec l'attribut « appareil
  déverrouillé, cet appareil seulement » : elle n'est ni affichée, ni exportée, ni synchronisée,
  ni restaurée sur un autre appareil. Seule la ligne de clé publique se copie ou se partage.
  Un mot de passe n'est gardé dans le Trousseau que si l'utilisateur le demande, et seulement
  après que le serveur l'a accepté ; une connexion rapide ne garde rien.
- **Connexions propres à l'appareil.** Elles sont dans `connexions-ssh-mobile.json`, distinctes de
  celles du Mac : pas de synchronisation, donc pas de secret qui voyage.

## Ce qui n'est pas fait

- Pas d'import d'une clé privée existante, pas de clé RSA ni ECDSA pour s'authentifier.
- Pas d'agent, pas de rebond par un hôte intermédiaire, pas de redirection de port.
- SFTP : fichiers seulement. Un dossier ne se télécharge ni ne s'envoie d'un bloc, et ne se
  supprime que vide.
- Les transferts vont par blocs de 32 000 octets, l'un après l'autre : c'est plus lent que `sftp`.
- Une photo ou une vidéo choisie dans Photos est d'abord copiée en mémoire, puis dans le dossier
  temporaire, avant d'être envoyée.
- iOS suspend l'application en arrière-plan : la session et les transferts s'arrêtent alors.

## Conséquences

- Le projet Xcode reçoit trois paquets distants pour la cible iOS : Citadel, swift-nio et
  swift-nio-ssh. Ces deux derniers sont déjà des dépendances de Citadel ; ils sont déclarés pour
  que `SSHLink` puisse importer `NIOCore` et `NIOSSH` sans dépendre d'un effet de bord.
- **Citadel ne s'appuie pas sur le dépôt d'Apple pour SwiftNIO SSH, mais sur une copie tenue par
  un tiers (`Wellz26/swift-nio-ssh`).** C'est du code de sécurité qui n'est pas maintenu par
  Apple : à surveiller à chaque mise à jour de Citadel, et à réévaluer si Citadel revient au
  dépôt d'origine.
- Les serveurs qui ne présentent qu'une clé d'hôte RSA peuvent être refusés à la négociation.
- Les thèmes du terminal sont partagés avec le Mac (`Shared/SSH/TerminalTheme`).
