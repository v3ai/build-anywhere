/* netinet/in.h: build-anywhere shell tier (pnut-sh). pnut has no nested
 * structs, so sin_addr is the address itself: write sa->sin_addr where C
 * has sa.sin_addr.s_addr. Byte order is the host's (htons and friends do
 * nothing). */
#ifndef _BA_SH_NETINET_IN_H
#define _BA_SH_NETINET_IN_H
#include <sys/socket.h>
typedef int in_addr_t;
typedef int in_port_t;
struct in_addr {
    in_addr_t s_addr;
};
struct sockaddr_in {
    sa_family_t sin_family;
    in_port_t sin_port;
    in_addr_t sin_addr;
    int sin_zero;
};
#define IPPROTO_TCP 6
#define INADDR_ANY 0
#define INADDR_LOOPBACK 2130706433
#define INADDR_NONE (-1)
#define INET_ADDRSTRLEN 16
#define htons(x) (x)
#define htonl(x) (x)
#define ntohs(x) (x)
#define ntohl(x) (x)
#endif
