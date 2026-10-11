#include "CPingouinSystem.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <resolv.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int pingouin_dns_servers(char *output, size_t size) {
    if (output == NULL || size == 0) {
        return 0;
    }
    output[0] = '\0';

    res_state state = calloc(1, sizeof(*state));
    if (state == NULL) {
        return 0;
    }
    if (res_ninit(state) != 0) {
        free(state);
        return 0;
    }

    union res_sockaddr_union servers[MAXNS];
    memset(servers, 0, sizeof(servers));
    int found = res_getservers(state, servers, MAXNS);

    int written = 0;
    size_t used = 0;
    for (int index = 0; index < found; index++) {
        char text[INET6_ADDRSTRLEN];
        const char *result = NULL;
        if (servers[index].sin.sin_family == AF_INET) {
            result = inet_ntop(AF_INET, &servers[index].sin.sin_addr, text, sizeof(text));
        } else if (servers[index].sin6.sin6_family == AF_INET6) {
            const uint8_t *bytes = servers[index].sin6.sin6_addr.s6_addr;
            if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
                continue;
            }
            result = inet_ntop(AF_INET6, &servers[index].sin6.sin6_addr, text, sizeof(text));
        }
        if (result == NULL) {
            continue;
        }
        size_t length = strlen(text);
        if (used + length + 2 > size) {
            break;
        }
        memcpy(output + used, text, length);
        used += length;
        output[used++] = '\n';
        output[used] = '\0';
        written++;
    }

    res_ndestroy(state);
    free(state);
    return written;
}

// L'en-tête <net/route.h> n'existe pas dans le SDK d'iOS : la structure des messages de routage
// de Darwin est donc reprise ici. Elle est identique sur macOS et sur iOS.
struct pingouin_rt_metrics {
    uint32_t rmx_locks;
    uint32_t rmx_mtu;
    uint32_t rmx_hopcount;
    int32_t rmx_expire;
    uint32_t rmx_recvpipe;
    uint32_t rmx_sendpipe;
    uint32_t rmx_ssthresh;
    uint32_t rmx_rtt;
    uint32_t rmx_rttvar;
    uint32_t rmx_pksent;
    uint32_t rmx_state;
    uint32_t rmx_filler[3];
};

struct pingouin_rt_msghdr {
    unsigned short rtm_msglen;
    unsigned char rtm_version;
    unsigned char rtm_type;
    unsigned short rtm_index;
    int rtm_flags;
    int rtm_addrs;
    pid_t rtm_pid;
    int rtm_seq;
    int rtm_errno;
    int rtm_use;
    uint32_t rtm_inits;
    struct pingouin_rt_metrics rtm_rmx;
};

#define PINGOUIN_RTF_GATEWAY 0x2
#define PINGOUIN_RTF_IFSCOPE 0x1000000
#define PINGOUIN_RTA_DST 0x1
#define PINGOUIN_RTA_GATEWAY 0x2
#define PINGOUIN_RTAX_MAX 8
#define PINGOUIN_NET_RT_FLAGS 2

/// Les adresses qui suivent l'en-tête sont alignées sur quatre octets.
static size_t pingouin_rounded(size_t length) {
    return length == 0 ? sizeof(uint32_t) : (length + sizeof(uint32_t) - 1) & ~(sizeof(uint32_t) - 1);
}

/// Écrit la passerelle et le nom de l'interface. Renvoie 1 si l'adresse a pu être écrite.
static int pingouin_describe(const struct sockaddr_in *via, unsigned short index, char *gateway, size_t gateway_size, char *interface_name) {
    if (inet_ntop(AF_INET, &via->sin_addr, gateway, (socklen_t)gateway_size) == NULL) {
        gateway[0] = '\0';
        return 0;
    }
    if (if_indextoname(index, interface_name) == NULL) {
        interface_name[0] = '\0';
    }
    return 1;
}

int pingouin_default_gateway(char *gateway, size_t gateway_size, char *interface_name, size_t interface_size) {
    if (gateway == NULL || gateway_size < INET_ADDRSTRLEN || interface_name == NULL || interface_size < IF_NAMESIZE) {
        return 0;
    }
    gateway[0] = '\0';
    interface_name[0] = '\0';

    int mib[6] = {CTL_NET, PF_ROUTE, 0, AF_INET, PINGOUIN_NET_RT_FLAGS, PINGOUIN_RTF_GATEWAY};
    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) != 0 || needed == 0) {
        return 0;
    }
    // La table peut grandir entre les deux appels : on prévoit de la marge.
    needed += 4096;
    char *buffer = malloc(needed);
    if (buffer == NULL) {
        return 0;
    }
    if (sysctl(mib, 6, buffer, &needed, NULL, 0) != 0) {
        free(buffer);
        return 0;
    }

    int found = 0;
    int has_fallback = 0;
    unsigned short fallback_index = 0;
    struct sockaddr_in fallback;
    memset(&fallback, 0, sizeof(fallback));
    char *cursor = buffer;
    char *end = buffer + needed;
    while (!found && cursor + sizeof(struct pingouin_rt_msghdr) <= end) {
        struct pingouin_rt_msghdr header;
        memcpy(&header, cursor, sizeof(header));
        if (header.rtm_msglen < sizeof(header) || cursor + header.rtm_msglen > end) {
            break;
        }
        char *address = cursor + sizeof(header);
        char *message_end = cursor + header.rtm_msglen;
        struct sockaddr_in destination;
        struct sockaddr_in via;
        int has_destination = 0;
        int has_gateway = 0;

        for (int index = 0; index < PINGOUIN_RTAX_MAX && address + 2 <= message_end; index++) {
            if ((header.rtm_addrs & (1 << index)) == 0) {
                continue;
            }
            unsigned char length = (unsigned char)address[0];
            unsigned char family = (unsigned char)address[1];
            if (family == AF_INET && length >= sizeof(struct sockaddr_in) && address + sizeof(struct sockaddr_in) <= message_end) {
                if ((1 << index) == PINGOUIN_RTA_DST) {
                    memcpy(&destination, address, sizeof(destination));
                    has_destination = 1;
                } else if ((1 << index) == PINGOUIN_RTA_GATEWAY) {
                    memcpy(&via, address, sizeof(via));
                    has_gateway = 1;
                }
            }
            address += pingouin_rounded(length);
        }

        // Route par défaut : destination 0.0.0.0, avec une passerelle IPv4. Avec plusieurs interfaces
        // raccordées, la route principale est celle qui n'est pas liée à une interface ; les autres
        // ne servent que de repli.
        if (has_destination && has_gateway && destination.sin_addr.s_addr == 0 && via.sin_addr.s_addr != 0) {
            int is_scoped = (header.rtm_flags & PINGOUIN_RTF_IFSCOPE) != 0;
            if (!is_scoped) {
                found = pingouin_describe(&via, header.rtm_index, gateway, gateway_size, interface_name);
            } else if (!has_fallback) {
                fallback = via;
                fallback_index = header.rtm_index;
                has_fallback = 1;
            }
        }
        cursor += header.rtm_msglen;
    }
    if (!found && has_fallback) {
        found = pingouin_describe(&fallback, fallback_index, gateway, gateway_size, interface_name);
    }

    free(buffer);
    return found;
}
