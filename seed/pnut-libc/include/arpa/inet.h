/* arpa/inet.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_ARPA_INET_H
#define _BA_SH_ARPA_INET_H
#include <netinet/in.h>
in_addr_t inet_addr(char *s);
int inet_pton(int af, char *s, void *dst);
char *inet_ntoa(in_addr_t a);
char *inet_ntop(int af, void *src, char *dst, socklen_t size);
#endif
