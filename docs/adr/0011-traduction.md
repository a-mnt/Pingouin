# ADR 0011 — Traduction de l'interface

- Date : 2026-10-11
- Statut : accepté

## Contexte

Pingouin était écrit en français, avec ses textes directement dans le code : dans les vues, mais
aussi dans les modèles de présentation (messages d'état et d'erreur), les rapports et quelques
types du paquet. L'application doit s'afficher aussi en anglais, en espagnol, en allemand et en
italien.

Le mécanisme habituel de SwiftUI ne traduit que les textes passés directement à une vue, et
compose la clé d'un texte à valeurs insérées d'après le type de chaque valeur (`%lld`, `%@`,
`%lf`…). Les textes fabriqués ailleurs demandent `String(localized:)`, avec la même dépendance aux
types. Sans compilateur sous la main au moment d'écrire le catalogue, ces clés ne pouvaient pas
être établies avec certitude.

## Décision

Un seul point de passage, la fonction `L("…")` de `PingouinCore` :

- le texte du code reste le français, et sert de clé ;
- chaque valeur insérée donne « %@ » dans la clé, quel que soit son type, et « % » est doublé ;
  la clé se déduit donc du seul texte du code ;
- la traduction est lue dans `Resources/Localizable.xcstrings` (String Catalog, langue source
  `fr`), dans le lot de l'application ; sans traduction, le texte français est rendu ;
- les valeurs sont insérées par un petit analyseur maison (`%@` dans l'ordre, `%1$@` par
  position), pas par `String(format:)` : une traduction mal formée ne peut rien faire lire qui
  n'existe pas ;
- l'accord en nombre passe par `L(count:one:other:)`. En français, zéro s'accorde au singulier ;
  dans les autres langues, au pluriel.

Les vues reçoivent donc des `String` déjà traduites (`Text(L("…"))`, `Button(L("…"))`).

`Scripts/traductions.py` relit le code et le catalogue : il signale les clés absentes, celles qui
ne servent plus et les traductions dont le nombre d'insertions diffère, et peut ajouter les clés
manquantes. Les entrées du catalogue sont marquées « manual » pour que Xcode ne les juge pas
périmées, puisqu'il ne reconnaît pas `L(…)` à l'extraction.

## Conséquences

- Tout texte nouveau s'écrit `L("…")`, puis `python3 Scripts/traductions.py ajouter`, puis se
  traduit dans Xcode. Un texte oublié reste simplement en français.
- La langue suit celle du système (ou le réglage de langue par application de macOS). Elle est
  lue au lancement.
- Restent en français, volontairement : le journal (Réglages > Journal), le diagnostic copié de
  la Consommation, les messages d'erreur renvoyés tels quels par `sftp` ou par le système (ces
  derniers suivent déjà la langue du système).
- Les textes enregistrés (événements de supervision, notes de topologie, exécutions) gardent la
  langue dans laquelle ils ont été écrits.
- Un nombre inséré dans un texte n'est plus mis en forme par SwiftUI (pas de séparateur de
  milliers automatique) ; là où il compte, le code appelle `.formatted()`.
- Les unités de volume suivent la langue : « Ko, Mo » en français, « kB, MB » ailleurs.
- Les traductions ont été écrites sans relecture par des locuteurs natifs : elles sont à relire.
- Les essais des modèles de présentation comparent des textes français ; ils supposent une
  session macOS en français.
