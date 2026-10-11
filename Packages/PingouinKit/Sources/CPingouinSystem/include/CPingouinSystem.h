#ifndef CPINGOUIN_SYSTEM_H
#define CPINGOUIN_SYSTEM_H

#include <stddef.h>

/// Serveurs DNS du système, lus par le résolveur (libresolv).
/// Écrit une adresse par ligne dans `output` (terminé par un zéro) et renvoie leur nombre.
/// Les adresses IPv6 de liaison locale sont écartées : elles ne servent à rien sans leur interface.
int pingouin_dns_servers(char *output, size_t size);

/// Passerelle IPv4 de la route par défaut, lue dans la table de routage du noyau (sysctl).
/// Écrit l'adresse dans `gateway` et le nom de l'interface dans `interface_name`.
/// Renvoie 1 si une passerelle a été trouvée, 0 sinon. Rien n'est envoyé sur le réseau.
int pingouin_default_gateway(char *gateway, size_t gateway_size, char *interface_name, size_t interface_size);

#endif
