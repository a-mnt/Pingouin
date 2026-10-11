# ADR 0005 — Deux exceptions de sécurité assumées : HTTP simple et lecture de certificats invalides

Date : 2026-10-10 · Statut : accepté

## Contexte

Deux outils de diagnostic butent sur des protections par défaut de macOS :

- **HTTP** : App Transport Security interdit aux applications les requêtes en `http://` simple.
  Or tester un serveur HTTP non chiffré, ou suivre une redirection de `http://` vers `https://`,
  est précisément l'objet de l'outil.
- **TLS** : pour expliquer pourquoi un certificat est refusé (expiré, mauvais nom, chaîne incomplète),
  il faut le recevoir, donc aller au bout de la négociation même quand il est invalide.

## Décision

1. `NSAllowsArbitraryLoads` est activé (`Config/Info.plist`). L'application n'utilise le réseau que
   pour les requêtes explicitement lancées par l'utilisateur ; elle ne charge elle-même aucun contenu
   distant. La validation TLS de l'outil HTTP reste celle du système : une connexion `https://` vers
   un certificat invalide **échoue** et l'erreur est affichée.
2. L'outil TLS accepte la négociation quel que soit le certificat, **uniquement** pour le lire.
   Aucune donnée applicative n'est envoyée ni reçue, la connexion est fermée aussitôt, et le verdict
   affiché vient de l'évaluation de confiance normale du système (`SecTrustEvaluateWithError`),
   refaite sur le certificat reçu.

## Conséquences

- Aucune de ces deux exceptions ne permet de faire transiter des données de l'utilisateur sur une
  connexion non vérifiée.
- Si une future fonction charge du contenu distant pour son propre compte, elle devra passer par
  une session qui n'hérite pas de cette tolérance.
