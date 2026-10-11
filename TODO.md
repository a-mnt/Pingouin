# Tâches restantes

## Phase 0 — à faire sur le Mac
- [ ] Compiler dans Xcode et lancer `sh Scripts/bootstrap.sh` ; corriger les erreurs de compilation et de test éventuelles.
- [ ] Supprimer le dossier `_to_delete/` (ancien `project.yml` et sauvegarde du projet d'origine).
- [ ] Trancher arm64 seul ou binaire par défaut pour la publication.
- [ ] Reporter les versions d'Xcode et de Swift et les résultats dans `docs/phase0-faisabilite.md`.
- [ ] Initialiser le dépôt git (`git init`) et faire le premier commit.
- [ ] Prototype ping : socket ICMP non privilégié (`SOCK_DGRAM`, `IPPROTO_ICMP` et `IPPROTO_ICMPV6`).
- [ ] Prototype traceroute sans privilèges ; sinon documenter la limite et l'alternative.
- [ ] Prototype DNS avec serveur configurable et types MX, TXT, SOA, PTR.
- [ ] Prototype SSH isolé : connexion, vérification de clé d'hôte, authentification, commande, puis terminal et SFTP.
- [ ] Vérifier les prérequis de signature Developer ID et de notarisation (compte, certificat, profil notarytool).

## Interface Liquid Glass
- [ ] Compiler ce lot (cible macOS 26, `DesignSystem/`, Scan de ports, clic droit) et corriger les erreurs.
- [ ] Vérifier à l'écran le rendu du verre sur les tableaux, et le menu du clic droit.

## Tableau de bord, Supervision, SSH, Topologie, Rapports, Automatisation — à vérifier au premier essai
- [ ] Compiler ce lot. Xcode doit d'abord télécharger SwiftTerm (File > Packages > Resolve Package Versions).
- [ ] SSH : ouverture d'une session, saisie du mot de passe, accord sur une clé d'hôte inconnue,
      changement de thème en cours de session, redimensionnement, fin de session détectée.
- [ ] SSH : mot de passe enregistré — est-il bien saisi à la demande, sans s'afficher ? Que se passe-t-il
      s'il est faux (nouvelle demande, saisie au clavier) ? Le Trousseau demande-t-il un accord ?
- [ ] SSH : onglets — passage de l'un à l'autre sans perdre l'écran, fermeture, double-clic.
- [ ] SSH : le terminal reçoit-il bien le clavier dès l'ouverture ? Copier-coller ?
- [ ] Supervision : passage hors ligne après le nombre d'échecs fixé, retour en ligne, notification.
- [ ] Topologie : glisser un nœud dans le plan défilant ; tracé des liens.
- [ ] Rapports : rendu du PDF (une seule page haute : à paginer), ouverture du CSV dans un tableur.
- [ ] Automatisation : exécution planifiée à l'échéance, annulation en cours d'étape.
- [ ] Maquettes : les changements faits hors maquette validée (thèmes et connexions SSH, éditeurs
      de surveillance et de tâche) sont à revoir à l'écran.

## Consommation par appareil — à vérifier au premier essai
- [ ] Freebox : la demande d'accès apparaît-elle sur l'écran de la box, et l'accord est-il bien vu ?
- [ ] Freebox : sens des compteurs (reçu / envoyé) — comparer avec un gros téléchargement sur un appareil.
- [ ] Freebox : les compteurs par port sont marqués « instables » par Free ; vérifier qu'ils avancent.
- [ ] Freebox : la bande Wi-Fi (2,4 / 5 / 6 GHz) est-elle bien lue ? Sinon la liaison affiche « Wi-Fi ».
- [ ] Freebox : appareils connectés à un répéteur — apparaissent-ils, et sont-ils comptés deux fois ?
- [ ] Passer les échanges avec la box en HTTPS (autorité de certification Freebox à embarquer).
- [ ] Autres sources : Livebox, Bbox, SNMP — chacune à essayer sur un vrai équipement avant d'être activée.
- [ ] Ajouter la consommation aux rapports.

## Suites de ce lot
- [ ] SSH : commande unique sans terminal ; navigateur SFTP graphique ; onglets à réordonner.
- [ ] SSH : bibliothèque SSH en Swift à la place d'OpenSSH, si le Keychain doit porter les secrets (ADR 0007).
- [ ] Supervision : modification d'une surveillance existante ; contrôle TLS ; graphique d'historique.
- [ ] Topologie : liens constatés automatiquement (passerelle, traceroute) ; export en image.
- [ ] Rapports : PDF paginé avec en-tête ; modèles de rapport.
- [ ] Automatisation : notification en cas d'échec d'une tâche planifiée ; export d'un rapport en fin de tâche.
- [ ] Migration des fichiers JSON si leur format change.

## Ping, Traceroute, DNS, HTTP, TLS — à vérifier au premier essai
- [ ] Traceroute : macOS livre-t-il bien les messages « durée de vie épuisée » sur un socket ICMP
      non privilégié ? Sinon tous les sauts apparaîtront sans réponse : c'est le point le plus incertain.
- [ ] Ping : valeur du TTL affichée, et comportement quand l'hôte est injoignable.
- [ ] DNS : lecture du serveur du système dans `/etc/resolv.conf` ; serveur en IPv6.
- [ ] HTTP : la décomposition du temps est-elle renseignée, et les redirections listées ?
- [ ] TLS : émetteur, dates et noms couverts sont lus par une API ancienne de macOS dont le format
      de retour n'a pas pu être vérifié ; un champ vide ou « — » signale un décodage à corriger.
- [ ] Ajouter l'IPv6 au ping et au traceroute ; repli sur TCP pour les réponses DNS tronquées.
- [ ] Conserver les historiques entre deux lancements (avec la persistance).

## Scan de ports — suites
- [ ] Premier essai réel : vérifier qu'un port fermé est bien vu « fermé » et non « indéterminé ».
- [ ] Tests d'intégration sur la boucle locale ; export CSV et JSON.

## Découverte LAN — suites
- [ ] Premier essai réel : vérifier les trois points listés à la fin de l'ADR 0003.
- [ ] Lire la table ARP par `sysctl` plutôt que par la commande `arp`.
- [ ] Nom du fabricant à partir de l'adresse MAC, identification de la passerelle, découverte Bonjour.
- [ ] Délai et concurrence réglables dans les préférences ; export CSV et JSON.
- [ ] Tests d'intégration de `PingouinNetwork` (interfaces, balayage sur la boucle locale).

## Phase 1 — socle
- [ ] Design system (composants réutilisables, états vide, chargement, erreur).
- [ ] Types d'erreurs communs et gestion de l'annulation.
- [x] Persistance : fichiers JSON (ADR 0006). À reconsidérer si les volumes grossissent.
- [x] Préférences (délais, concurrence, valeurs par défaut) — écrit, à essayer.
- [ ] String Catalog pour préparer l'anglais.
- [x] Icône de l'application (dessinée par script ; à refaire par un graphiste pour une publication).
- [ ] Intégration continue.

## Phase 2 — outils réseau
- [ ] DNS, test TCP et scan de ports, HTTP et TLS, ping, traceroute.

## Phase 3 — administration
- [x] SSH : profils, clés d'hôte (OpenSSH), terminal, SFTP en ligne de commande — écrit, à essayer.
- [x] Supervision locale, notifications, historique — écrit, à essayer.

## Phase 4 — fonctions avancées
- [x] Topologie, rapports, exports PDF, CSV et JSON, automatisation, planification locale — écrit, à essayer.

## Phase 5 — publication
- [ ] Scripts de build Release, signature, notarisation, DMG, procédure documentée.
- [ ] Revue de sécurité, mesures CPU et mémoire, tests de non-régression.
