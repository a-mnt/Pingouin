# ADR 0001 — Structure du projet : projet Xcode et paquet local

Date : 2026-10-09 · Statut : accepté (révisé le jour même)

## Contexte

Le projet doit être modulaire, testable sans interface et reproductible.

Une première version de cette décision prévoyait de générer le projet avec XcodeGen. Elle a été
abandonnée : le projet a finalement été créé directement dans Xcode 26.3, et garder deux
descriptions du même projet aurait créé deux sources de vérité.

## Décision

- `Pingouin.xcodeproj` est un projet Xcode classique, versionné dans le dépôt.
- Les dossiers `App`, `Features` et `Resources` sont des groupes synchronisés avec le système de
  fichiers : pas de liste de fichiers à maintenir dans `project.pbxproj`.
- La logique sans interface vit dans un paquet Swift local, `Packages/PingouinKit`, référencé par
  le projet. Elle se compile et se teste avec `swift test`, sans application hôte.
- Seuls ces trois dossiers appartiennent à la cible : le paquet, la documentation et les scripts
  n'y sont pas inclus, sinon les sources du paquet seraient compilées deux fois.
- Les tests utilisent Swift Testing. Mode de langage Swift 6.
- Cible macOS uniquement (le modèle multiplateforme d'Xcode a été restreint à macOS 15, arm64 et x86_64
  restant ceux par défaut tant que la publication n'impose pas arm64 seul).

## Conséquences

- Aucun outil tiers n'est nécessaire pour ouvrir et compiler le projet.
- Tout nouveau dossier de sources de l'application (par exemple `DesignSystem`) doit être ajouté
  au projet comme groupe synchronisé.
- Les réglages de l'isolation par défaut sur l'acteur principal proposés par le modèle Xcode ont
  été retirés : l'isolation est déclarée explicitement dans le code.
