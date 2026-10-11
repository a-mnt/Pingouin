# ADR 0002 — Distribution directe, sans App Sandbox

Date : 2026-10-09 · Statut : accepté

## Contexte

Pingouin est distribué directement (Developer ID et notarisation), pas sur le Mac App Store.
Plusieurs fonctions prévues (découverte LAN par table ARP, traceroute, capture éventuelle,
lecture de clés SSH choisies par l'utilisateur) sont limitées ou impossibles sous App Sandbox.

## Décision

- App Sandbox non activée.
- Hardened Runtime activé, sans exception tant qu'aucun besoin n'est démontré.
- Aucune élévation de privilèges : pas d'outil auxiliaire privilégié à ce stade. Une fonction qui
  exigerait les droits administrateur sera d'abord documentée comme limite.

## Conséquences

- La notarisation reste obligatoire et le Hardened Runtime en est un prérequis.
- Chaque exception au Hardened Runtime ou chaque nouvelle permission fera l'objet d'un ADR.
- L'absence de sandbox augmente l'exigence sur la validation des entrées et le traitement des secrets.
