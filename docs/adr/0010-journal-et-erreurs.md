# ADR 0010 — Journal commun et fin des échecs silencieux

Date : 2026-10-11 · Statut : accepté, écrit, à essayer

## Contexte

Quand quelque chose échouait sans message (fichier non enregistré, export impossible, relevé refusé),
il ne restait aucune trace. Chaque problème demandait un outil de diagnostic écrit pour l'occasion.

## Décision

- Un journal commun, `AppLog` : chaque ligne part dans le journal unifié de macOS (`os.Logger`,
  sous-système `fr.a-mnt.pingouin`, visible dans Console.app) et reste en mémoire le temps de la
  session (1 000 lignes au plus). Il se lit, se copie et s'exporte depuis Réglages > Journal.
- Jamais de secret dans le journal : ni mot de passe, ni jeton, ni contenu de clé. On y écrit ce
  qui s'est passé (outil, cible, résultat), pas ce qui a été saisi.
- Un échec n'est plus avalé : il est montré dans la fenêtre concernée et journalisé.

## Revue des « try? » de App/ et Features/

| Endroit | Décision |
| --- | --- |
| `Task.sleep` des moteurs (supervision, automatisation, consommation, saisie SSH) | Gardé : la seule erreur possible est l'annulation de la tâche, traitée par la boucle. |
| Autorisation des notifications | Remplacé : une erreur n'est plus confondue avec un refus. |
| Export du schéma de topologie | Remplacé : message dans la fenêtre et ligne au journal. |
| Création du dossier des données (Réglages) | Remplacé : message dans la fenêtre et ligne au journal. |

Dans le paquet, la lecture de la liste des appareils de la Freebox garde un `try?` documenté : son
échec ne doit pas empêcher le relevé des ports.

## Conséquences

- Le journal en mémoire disparaît à la fermeture ; Console.app garde la trace selon les règles de macOS.
- Les noms d'hôtes et adresses du réseau figurent dans le journal : le relire avant de le transmettre.
- Reste à faire : journaliser le lancement des outils de diagnostic, et un type d'erreur commun
  aux modèles de présentation.
