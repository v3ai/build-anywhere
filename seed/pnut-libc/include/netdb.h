/* netdb.h: build-anywhere shell tier (pnut-sh). h_length is
 * sizeof(in_addr_t) and h_addr points to one in_addr_t, so
 * memcpy(&sa->sin_addr, h->h_addr, h->h_length) works as in C. */
#ifndef _BA_SH_NETDB_H
#define _BA_SH_NETDB_H
#include <netinet/in.h>
struct hostent {
    char *h_name;
    char **h_aliases;
    int h_addrtype;
    int h_length;
    char **h_addr_list;
};
#define h_addr h_addr_list[0]
struct hostent *gethostbyname(char *name);
#endif
