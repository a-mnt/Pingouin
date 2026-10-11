# ADR 0012 — Application iOS et iPadOS

- Date : 2026-10-11
- Statut : accepté (étapes 1 à 4 écrites ; SSH et SFTP : voir l'ADR 0013)

## Contexte

Pingouin doit exister sur iPhone et iPad (iOS 26, iPadOS 26), dans le même dépôt que la version Mac.
Tout le périmètre est visé à terme, SSH compris, mais iOS n'offre pas tout ce dont la version Mac
se sert : pas de lancement de commandes (`arp`, `ndp`, `route`, `ssh`, `sftp`), pas de travail
en arrière-plan pour une application de ce type, pas de lecture détaillée des certificats.

## Décision

- Une cible `PingouinMobile` dans le projet Xcode existant, même identifiant d'application que le
  Mac (`fr.a-mnt.pingouin`).
- Quatre dossiers lui sont attachés :
  - `PingouinMobile/` : l'application iOS elle-même (vues en une colonne, onglets) ;
  - `Shared/` : les modèles de présentation communs aux deux applications ; un modèle y est
    déplacé depuis `Features/` au moment où son outil arrive sur iOS ;
  - `DesignSystem/` : les composants d'interface, rendus portables (`#if canImport(AppKit)`) ;
  - `Resources/` : le catalogue de traductions et la couleur d'accent.
- Le paquet `PingouinKit` accepte iOS 18 et plus. Ce qu'iOS ne permet pas est isolé par
  `#if os(macOS)` et signalé par une erreur ou une valeur absente, jamais simulé :
  table ARP, table des voisins IPv6.
- La navigation est un `TabView` en style « sidebarAdaptable » : des onglets sur iPhone, une barre
  latérale sur iPad, sans double mise en page à entretenir.
- Un outil n'apparaît dans l'application iOS que lorsqu'il fonctionne : pas d'entrée grisée.

## Ordre de réalisation

1. Socle et ping — fait, essayé sur appareil.
2. Les autres diagnostics (traceroute, DNS, scan de ports, HTTP, TLS, calculateur IP), l'accueil
   et les réglages — écrits.
3. Découverte LAN, supervision, consommation, topologie, automatisation, rapports — écrits.
4. SSH et SFTP, avec Citadel et SwiftTerm — écrits (ADR 0013).

## Ce qu'iOS impose, et comment c'est traité

- **Passerelle.** Pas de commande `route` : la route par défaut est lue dans la table de routage du
  noyau (`sysctl`), par la cible C `CPingouinSystem` du paquet. L'en-tête `net/route.h` n'existe
  pas dans le SDK d'iOS : la structure des messages de routage y est recopiée. En données
  cellulaires seules, il n'y a pas de passerelle : l'accueil le dit, et le test de connexion
  saute ce maillon en le marquant en échec.
- **Serveurs DNS.** `/etc/resolv.conf` n'est pas lisible : la liste est demandée au résolveur
  (libresolv), par la même cible C. Sur le Mac, le fichier reste la première source.
- **Certificats.** `SecCertificateCopyValues` n'existe pas : dates, émetteur et noms couverts sont
  lus dans l'encodage DER par `X509Reader` (PingouinCore, testé). La confiance reste évaluée par
  le système.
- **Découverte LAN.** Pas de table ARP ni de table des voisins IPv6 : seuls les appareils qui
  répondent au ping sont trouvés, sans adresse MAC ; l'option IPv6 n'est pas proposée.
- **Arrière-plan.** iOS suspend l'application dès qu'elle quitte l'écran. La supervision, les
  relevés de consommation et les tâches planifiées ne tournent donc qu'au premier plan ; les
  écrans le disent. Les mesures en attente sont écrites au passage en arrière-plan.
- **Fichiers.** Pas de panneau d'enregistrement : rapports, schéma et journal sont écrits dans le
  dossier temporaire puis remis à la feuille de partage.
- **Textes.** Les messages qui nomment le système prennent son nom en insertion
  (`Platform.systemName`) ; ceux qui parlent « du Mac » ont une variante iOS (`#if os(macOS)`).

## Organisation de l'application iOS

Cinq onglets : Accueil (raccordement, test de connexion, premiers pas), Outils (diagnostics),
Réseau (découverte, supervision, consommation, topologie, automatisation, rapports), SSH, Réglages.
`MobileAppState` détient les modèles de présentation, l'onglet affiché et la pile de navigation
de chaque onglet ; `open(_:target:)` y lance un outil sur une cible depuis n'importe quel écran,
comme le clic droit du Mac. Sur iOS, ce geste est un appui long.

## Conséquences

- Les vues ne sont pas partagées : celles du Mac reposent sur de grands tableaux, celles d'iOS
  sont écrites pour une colonne. Les modèles de présentation, eux, sont tous dans `Shared/`.
- Le paquet contient désormais une cible en C. Elle ne fait que lire le système.
- L'icône iOS est dérivée de l'icône Mac (même dessin, pleine page, sans transparence).
- La langue se choisit dans les Réglages d'iOS, pas dans l'application.
- Les étapes 2 à 4 n'ont été ni compilées ni essayées au moment de leur livraison.
