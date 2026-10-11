# ADR 0006 — Données de l'application dans des fichiers JSON

Date : 2026-10-10 · Statut : accepté

## Contexte

Quatre modules doivent conserver des données entre deux lancements : les connexions SSH, les
surveillances et leurs mesures, le schéma de topologie, les tâches d'automatisation et leurs
exécutions. Les volumes sont petits (quelques dizaines d'éléments, quelques milliers de mesures
par surveillance). Le code est écrit sans pouvoir être compilé avant d'arriver sur le Mac du projet.

## Décision

Une valeur `Codable` par fichier, dans `~/Library/Application Support/fr.a-mnt.pingouin/` :
`connexions-ssh.json`, `supervision.json`, `topologie.json`, `automatisation.json`.
`JSONStore` écrit de façon atomique ; un fichier absent ou illisible vaut « pas de données ».

SwiftData et SQLite ont été écartés pour l'instant : ils apportent des schémas, des migrations et,
pour SwiftData, des macros dont le comportement ne peut pas être vérifié sans compiler. Rien dans
les besoins actuels ne demande de requêtes.

## Conséquences

- Les fichiers sont lisibles et modifiables à la main, et faciles à sauvegarder.
- Chaque enregistrement réécrit le fichier entier. La supervision limite donc le nombre de mesures
  gardées (2 880 par surveillance) et n'écrit qu'une fois toutes les 30 secondes au plus.
- Versions et migrations (ajout du 2026-10-11) : chaque fichier est écrit dans une enveloppe
  `{ "format": "pingouin", "version": 1, "data": … }`. Un fichier sans enveloppe est lu comme la
  version 0, de même contenu que la version 1. Quand une structure changera, le numéro de version du
  fichier concerné augmentera et une migration transformera l'ancien contenu (`VersionedFile`).
- Un fichier illisible, endommagé ou écrit par une version plus récente n'est jamais écrasé : il est
  renommé en `<nom>.illisible-<date>.json` et signalé par un bandeau dans la fenêtre. S'il ne peut
  pas être renommé, plus rien n'est écrit à sa place. Un échec d'écriture est signalé de la même façon.
- Aucun secret n'est écrit dans ces fichiers. Le jour où un secret devra être conservé, il ira dans
  le Keychain, pas ici.
- Les historiques des outils de diagnostic (ping, DNS…) restent en mémoire.
