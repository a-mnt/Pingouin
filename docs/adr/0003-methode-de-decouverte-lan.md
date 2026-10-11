# ADR 0003 — Méthode de découverte LAN

Date : 2026-10-09 · Statut : proposé, à valider par un essai réel sur le Mac

## Contexte

La découverte doit fonctionner sans privilèges administrateur et sans outil auxiliaire privilégié
(ADR 0002). Une requête ARP brute est donc exclue : elle exigerait un accès BPF.

## Décision

La découverte enchaîne trois étapes :

1. **Balayage ICMP Echo** par un socket non privilégié (`SOCK_DGRAM`, `IPPROTO_ICMP`). Deux passes,
   la seconde limitée aux hôtes muets. Il donne les temps de réponse, et oblige surtout le système
   à résoudre l'adresse MAC de chaque cible.
2. **Lecture de la table ARP** par `/usr/sbin/arp -an`. Elle fournit les adresses MAC et révèle les
   hôtes qui ignorent le ping mais répondent en ARP.
3. **Recherche inverse des noms** par le résolveur du système (`getnameinfo`), désactivable.

Garde-fous : jusqu'à 254 adresses (un /24) la découverte part directement ; au-delà une confirmation
explicite est demandée ; au-delà de 4094 adresses (un /20) elle est refusée. Les envois sont étalés
par paquets de huit.

## Choix écartés

- **Lecture de la table de routage par `sysctl`** au lieu de la commande `arp` : même information
  sans sous-processus, mais décodage de structures C binaires difficile à écrire sans compilateur.
  À reconsidérer : c'est la cible à terme.
- **Requêtes ARP directes** : nécessitent des privilèges.

## Conséquences et limites

- L'application lance un sous-processus système (chemin et arguments fixes, aucune saisie utilisateur).
- macOS demande l'autorisation « Réseau local » au premier envoi ; tant qu'elle n'est pas accordée,
  les envois échouent et la découverte le signale.
- IPv4 uniquement. Seul le sous-réseau directement raccordé est visible.
- Pas de nom de fabricant à partir de l'adresse MAC (demande une base OUI, non embarquée).
- La passerelle n'est pas identifiée comme telle.

## Points à vérifier au premier essai

- Le socket ICMP non privilégié s'ouvre bien et les réponses arrivent avec leur en-tête IP.
- Le code d'erreur réellement renvoyé quand l'accès au réseau local est refusé.
- Le format de sortie d'`arp -an` sur la version de macOS utilisée.

## Ajout du 2026-10-11 : IPv6

- Ping et traceroute : même socket ICMP non privilégié, en `AF_INET6` / `IPPROTO_ICMPV6`. Un choix
  « Automatique / IPv4 / IPv6 » décide du protocole ; en automatique, l'adresse saisie décide et,
  pour un nom, l'IPv4 est essayé d'abord. Une adresse de liaison locale se saisit avec sa zone
  (`fe80::1%en0`). Limite : la durée de vie de la réponse n'est pas affichée en IPv6, le système
  ne la livrant pas avec le message.
- Découverte LAN : un réseau /64 ne se balaie pas. Sur demande, Pingouin envoie un ping à l'adresse
  « tous les nœuds » (`ff02::1`) de l'interface, puis lit la table des voisins (`/usr/sbin/ndp -an`,
  chemin et arguments fixes). Les adresses IPv6 sont rattachées aux hôtes IPv4 par leur adresse
  MAC ; les appareils sans adresse IPv4 sur la plage sont listés à part. Un appareil qui ne répond
  pas à ce ping et que le Mac n'a jamais contacté en IPv6 reste invisible.
