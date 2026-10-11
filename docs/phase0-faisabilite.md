# Phase 0 — Compte rendu de faisabilité

Date : 2026-10-09

## Environnement constaté

- Mac : Apple Silicon (arm64), macOS. Version exacte de macOS et d'Xcode : **non relevées**.
- Dossier du projet : vide au départ, aucun dépôt git existant.
- Le code de ce premier jet a été écrit depuis un environnement Linux sans chaîne Swift
  (téléchargement de la chaîne refusé par le réseau). **Rien n'a été compilé ni exécuté.**

## Ce qui est livré

- Paquet `PingouinKit` : calcul IPv4 et IPv6 et tests unitaires.
- Application SwiftUI : navigation et module Calculateur IP.
- Projet `Pingouin.xcodeproj` créé dans Xcode 26.3, puis ajusté (voir ADR 0001), script `Scripts/bootstrap.sh`.

## Résultats à reporter après le premier lancement

| Vérification | Commande | Résultat |
| --- | --- | --- |
| Version d'Xcode | `xcodebuild -version` | à relever |
| Version de Swift | `swift --version` | à relever |
| Tests du paquet | `swift test --package-path Packages/PingouinKit` | non exécuté |
| Résolution du paquet local dans Xcode | ouverture de `Pingouin.xcodeproj` | échec initial (« Unable to resolve module dependency: 'PingouinCore' ») : le projet créé dans Xcode ne référençait pas le paquet ; référence ajoutée, à revérifier |
| Build Debug arm64 | `xcodebuild … build` | non exécuté |

## Points d'attention du code non compilé

- `UInt128` (IPv6) exige macOS 15 : cohérent avec la cible, à confirmer à la compilation.
- L'analyse IPv6 repose sur `inet_pton` ; les tests couvrent les formes refusées attendues.
- Mode Swift 6 : des erreurs d'isolation d'acteur sont possibles dans les vues et le modèle.
- Tests paramétrés Swift Testing avec des tuples en arguments.

## Risques prioritaires : état

Ces deux risques sont **ouverts**. Les éléments ci-dessous sont des hypothèses de travail,
pas des résultats ; chacun demande un prototype sur le Mac.

### Bibliothèque SSH

- SwiftNIO SSH fournit le protocole (transport, authentification, canaux) mais pas un client
  complet : ni SFTP, ni émulation de terminal, ni gestion des `known_hosts`.
- Pistes à évaluer : Citadel (surcouche de SwiftNIO SSH avec client SFTP) et SwiftTerm pour le
  terminal ; ou une liaison à libssh2. Maturité, maintenance et algorithmes pris en charge
  (types de clés notamment) restent à vérifier.
- Critères du prototype : compilation en Swift 6, connexion, clé d'hôte inconnue puis modifiée,
  authentification par clé et par mot de passe, exécution d'une commande, puis terminal et SFTP.

### Capacités réseau sans privilèges sur macOS 15

- Ping : macOS accepte en principe un socket ICMP non privilégié (`SOCK_DGRAM`). À prototyper en
  IPv4 et IPv6, avec mesure du temps et gestion du délai.
- Traceroute : l'outil système est privilégié. La faisabilité sans privilèges (TTL croissant et
  lecture des réponses ICMP) n'est pas établie ; c'est le point le plus incertain.
- DNS : le résolveur système ne permet pas de choisir le serveur pour tous les types
  d'enregistrement. Un client DNS sur UDP et TCP sera probablement nécessaire.
- TCP, HTTP, TLS : le framework Network et URLSession couvrent le besoin a priori ; l'inspection
  de la chaîne de certificats est à valider.
- Découverte LAN : la permission « Réseau local » sera demandée. La lecture des adresses MAC
  (table ARP) hors sandbox est à vérifier.

### Signature et notarisation

Non vérifiées : disponibilité d'un compte Apple Developer, d'un certificat Developer ID Application
et d'un profil `notarytool`. Le projet signe pour l'instant en local uniquement.
