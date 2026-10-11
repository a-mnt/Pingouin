# ADR 0008 — Consommation par appareil : relevée auprès de la box

Date : 2026-10-10 · Statut : accepté pour la Freebox, ouvert pour les autres sources

## Contexte

Un Mac ne voit passer que son propre trafic. Pour connaître la consommation de chaque appareil du
réseau, il faut interroger un équipement qui voit tout passer : la box, ou un switch administrable.
Chaque fabricant a sa propre interface, et toutes ne donnent pas un chiffre par appareil.

## Décision

- La fenêtre « Consommation » et les calculs (écarts entre relevés, cumul par jour, débit) sont
  communs à toutes les sources et vivent dans `PingouinCore` (`UsageTracker`, `UsageLedger`).
- Une source fournit des relevés (`UsageReading`) : une clé stable, une description, deux compteurs
  cumulés vus depuis l'appareil. Ajouter une box, c'est écrire un client qui produit ces relevés.
- Première source : la Freebox, par son API locale documentée. Wi-Fi par appareil
  (`wifi/ap/{id}/stations/`), Ethernet par port (`switch/status/` et `switch/port/{id}/stats`).
- Une source n'est proposée dans l'interface qu'une fois écrite ; les autres sont listées comme
  « pas encore prises en charge », sans bouton.

## Conséquences

- Les compteurs de la box sont cumulés et repartent de zéro à chaque reconnexion : Pingouin compte
  les écarts entre deux relevés. Le premier relevé après le lancement sert de point de départ ;
  ce qui a été consommé pendant que Pingouin était fermé n'est pas compté.
- Un port Ethernet derrière lequel se trouvent plusieurs appareils est mesuré en bloc.
- Un répéteur ou un switch branché sur la box peut faire compter deux fois le même trafic dans le total.
- L'accès repose sur un jeton accordé depuis l'écran de la box, gardé dans le Trousseau.
- Échanges en HTTPS depuis le 2026-10-11 : les autorités de certification de Free sont embarquées
  (`FreeboxAuthorities`) et ajoutées à celles du système pour ces seuls échanges, sans rien retirer
  à la validation TLS. Le HTTP simple reste disponible par un réglage, pour une box dont le
  certificat ne passerait pas la validation de macOS.
- Livebox et Bbox n'ont pas d'interface documentée par leur opérateur pour ces volumes ; rien n'a pu
  être confirmé sans équipement. SNMP donnerait un chiffre par port, pour tout matériel administrable.
