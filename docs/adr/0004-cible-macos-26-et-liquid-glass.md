# ADR 0004 — Cible macOS 26 et interface Liquid Glass

Date : 2026-10-10 · Statut : accepté

## Contexte

L'interface retenue est de style Liquid Glass : barre latérale flottante, barre d'outils sans fond,
panneaux translucides, contrôles en capsule. Les matériaux de verre de SwiftUI n'existent qu'à partir
de macOS 26. Garder macOS 15 comme cible aurait imposé un second rendu de repli à écrire et à vérifier.

## Décision

- La cible de déploiement de l'application passe de macOS 15 à **macOS 26**.
- Le paquet `PingouinKit` (logique sans interface) garde macOS 15 comme minimum : il n'utilise aucune
  API récente, et un minimum plus bas reste compatible avec l'application.
- Les maquettes de chaque fenêtre sont validées avant tout développement de la fenêtre correspondante.

## Conséquences

- L'application ne se lance plus sur macOS 15.
- Un seul rendu à maintenir ; les contrôles standard adoptent le style du système sans code dédié.
- Les deux écrans déjà codés (Calculateur IP, Découverte LAN) restent à aligner sur les maquettes validées.
