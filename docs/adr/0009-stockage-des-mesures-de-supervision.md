# ADR 0009 — Stockage des mesures de supervision : agrégats par heure

Date : 2026-10-11 · Statut : accepté (option A), écrit, à essayer

## Contexte

Chaque surveillance garde aujourd'hui ses 2 880 dernières mesures (date, réussite, temps de réponse),
soit 24 heures à un contrôle toutes les 30 secondes. Toutes les mesures de toutes les surveillances
sont dans `supervision.json`, réécrit en entier toutes les 30 secondes.

- Environ 200 à 300 Ko par surveillance : avec 20 surveillances, 4 à 6 Mo réécrits toutes les 30 secondes.
- La disponibilité est recalculée en relisant toutes les mesures à chaque rafraîchissement de la vue.
- L'historique s'arrête à 2 880 mesures : 24 heures à 30 secondes, mais 120 jours à une heure.
  La période « 24 heures » ne veut donc pas dire la même chose selon la surveillance.

## Options

### A. Agrégats par heure, toujours en JSON (recommandée)

- **Mesures récentes** : les 120 dernières mesures de chaque surveillance, pour les traits des tuiles
  et la disponibilité sur 1 heure.
- **Agrégats** : une ligne par heure et par surveillance — nombre de contrôles, nombre de réussites,
  temps moyen et temps maximal — conservée 30 jours, soit 720 lignes au plus.
- **Deux fichiers** : `supervision.json` (définitions, état, événements), écrit quand quelque chose
  change ; `supervision-mesures.json` (mesures récentes et agrégats), écrit toutes les 5 minutes
  et à la fermeture de l'application.
- Poids : environ 70 Ko par surveillance pour 30 jours, écrits toutes les 5 minutes au lieu de
  250 Ko toutes les 30 secondes — de l'ordre de 35 fois moins d'écriture.
- La disponibilité se lit dans les agrégats : plus de relecture de milliers de mesures.

### B. SQLite

- Une table des mesures, une ligne ajoutée par contrôle : aucune réécriture, historique complet,
  requêtes par période.
- Demande une couche d'accès à l'API C de SQLite (pas de dépendance tierce) : quelques centaines de
  lignes sensibles (ouverture, schéma, migrations, accès concurrents), à écrire et à essayer.
- Plus robuste à grande échelle, mais disproportionné pour quelques dizaines de surveillances.

## Décision

Option A. Elle règle le coût d'écriture et le calcul répété, donne des périodes de 7 et 30 jours,
et reste dans le stockage déjà en place (ADR 0006), avec ses versions et ses migrations.

## Conséquences

- Au-delà d'une heure, le détail mesure par mesure n'est plus gardé : seulement le résumé par heure.
- Les périodes de disponibilité deviennent : 1 heure, 24 heures, 7 jours, 30 jours. « Tout
  l'historique conservé » disparaît. C'est un changement visible dans la fenêtre Supervision.
- La disponibilité sur 24 heures et plus est calculée par heures entières : l'heure en cours compte,
  les 23 précédentes aussi.
- En cas d'arrêt brutal de l'application, jusqu'à 5 minutes de mesures peuvent être perdues
  (30 secondes aujourd'hui). L'état des surveillances et les événements, eux, restent écrits aussitôt.
- Migration : `supervision.json` passe en version 2. Au premier lancement, les mesures de l'ancien
  fichier sont converties en résumés par heure et écrites dans `supervision-mesures.json` avant que
  l'ancien fichier soit réécrit sans elles. Les 120 plus récentes restent en détail.
- Code : `MonitorHistory` (PingouinCore, testé) ; écriture toutes les 5 minutes, à la suppression
  d'une surveillance et à la fermeture ; un événement est écrit aussitôt.
- À revoir (option B) si le nombre de surveillances dépasse la centaine ou si le détail par mesure
  devient nécessaire.
