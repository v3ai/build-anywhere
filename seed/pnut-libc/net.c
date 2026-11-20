/*
 * net.c: TCP sockets for the build-anywhere shell tier, IPv4 only.
 *
 * POSIX sh cannot open a socket, so the shell functions in net.sh borrow
 * one: bash and ksh93 connect with their /dev/tcp files, other shells (and
 * servers in every shell) run nc(1) through named pipes. What differs from
 * C:
 *  - data is read a line at a time, so recv returns at the end of a line
 *    (or when the buffer is full) and cannot return NUL bytes: protocols
 *    must be text based;
 *  - with nc, connect cannot tell that the connection failed: the first
 *    recv then reports end of file;
 *  - nc -l takes one client at a time: listen starts one and accept
 *    starts the next, so one client can wait, and accept returns before
 *    the client connects; listen needs nc;
 *  - sin_addr is the address itself (no nested structs in pnut) and byte
 *    order is the host's.
 * Part of build-anywhere.
 */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include "net.sh"

int ba_sh_socket(void);
int ba_sh_connect(int fd, int addr, int port);
int ba_sh_listen(int fd, int port);
int ba_sh_accept(int fd, int port);
int ba_sh_shutdown(int fd);
int ba_sh_resolve(char *name);

int ba_net_port[10] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
char *ba_net_buf;

int socket(int domain, int type, int protocol)
{
    int fd;
    if (domain != AF_INET || type != SOCK_STREAM) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    fd = ba_sh_socket();
    if (fd < 0) {
        errno = EMFILE;
        return -1;
    }
    ba_net_port[fd] = 0;
    return fd;
}

int connect(int fd, struct sockaddr *addr, socklen_t len)
{
    struct sockaddr_in *sa = (struct sockaddr_in *)addr;
    if (ba_sh_connect(fd, sa->sin_addr, sa->sin_port) != 0) {
        errno = ECONNREFUSED;
        return -1;
    }
    return 0;
}

int bind(int fd, struct sockaddr *addr, socklen_t len)
{
    struct sockaddr_in *sa = (struct sockaddr_in *)addr;
    ba_net_port[fd] = sa->sin_port;
    return 0;
}

int listen(int fd, int backlog)
{
    if (ba_net_port[fd] == 0) {
        errno = EINVAL;
        return -1;
    }
    if (ba_sh_listen(fd, ba_net_port[fd]) != 0) {
        errno = EADDRINUSE;
        return -1;
    }
    return 0;
}

int accept(int fd, struct sockaddr *addr, socklen_t *len)
{
    struct sockaddr_in *sa;
    int c = ba_sh_accept(fd, ba_net_port[fd]);
    if (c < 0) {
        errno = EMFILE;
        return -1;
    }
    if (addr) {
        sa = (struct sockaddr_in *)addr;
        sa->sin_family = AF_INET;
        sa->sin_port = 0;
        sa->sin_addr = 0;
    }
    return c;
}

int send(int fd, void *buf, int n, int flags)
{
    return write(fd, buf, n);
}

/* Up to n bytes, stopping after a newline: 0 at end of file */
int recv(int fd, void *buf, int n, int flags)
{
    char *p = buf;
    int i = 0;
    int c;
    while (i < n) {
        c = fgetc((FILE *)fd);
        if (c < 0) break;
        p[i] = c;
        i = i + 1;
        if (c == '\n') break;
    }
    return i;
}

int shutdown(int fd, int how)
{
    if (how != SHUT_RD) ba_sh_shutdown(fd);
    return 0;
}

int setsockopt(int fd, int level, int name, void *val, socklen_t len) { return 0; }

/* a.b.c.d, or -1 */
in_addr_t inet_addr(char *s)
{
    int a = 0;
    int part = 0;
    int n = 0;
    int digits = 0;
    while (1) {
        if (*s >= '0' && *s <= '9') {
            n = n * 10 + *s - '0';
            digits = digits + 1;
            if (n > 255 || digits > 3) return -1;
        } else if ((*s == '.' || *s == 0) && digits > 0) {
            a = a * 256 + n;
            part = part + 1;
            n = 0;
            digits = 0;
            if (*s == 0) break;
            if (part == 4) return -1;
        } else {
            return -1;
        }
        s = s + 1;
    }
    if (part != 4) return -1;
    return a;
}

int inet_pton(int af, char *s, void *dst)
{
    int *d = dst;
    int a;
    if (af != AF_INET) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    if (strcmp(s, "255.255.255.255") == 0) {
        *d = -1;
        return 1;
    }
    a = inet_addr(s);
    if (a == -1) return 0;
    *d = a;
    return 1;
}

char *inet_ntop(int af, void *src, char *dst, socklen_t size)
{
    int a = *((int *)src);
    int i;
    int k = 0;
    int part;
    for (i = 3; i >= 0; i--) {
        part = (a >> (i * 8)) & 255;
        if (part >= 100) {
            dst[k] = '0' + part / 100;
            k = k + 1;
        }
        if (part >= 10) {
            dst[k] = '0' + part / 10 % 10;
            k = k + 1;
        }
        dst[k] = '0' + part % 10;
        k = k + 1;
        if (i > 0) {
            dst[k] = '.';
            k = k + 1;
        }
    }
    dst[k] = 0;
    return dst;
}

char *inet_ntoa(in_addr_t a)
{
    int *p = malloc(sizeof(int));
    if (ba_net_buf == 0) ba_net_buf = malloc(INET_ADDRSTRLEN);
    *p = a;
    inet_ntop(AF_INET, p, ba_net_buf, INET_ADDRSTRLEN);
    free(p);
    return ba_net_buf;
}

/* Numeric addresses directly; names are resolved by nc or /dev/tcp when
 * connecting, so this always succeeds for them. */
struct hostent *gethostbyname(char *name)
{
    struct hostent *h = malloc(sizeof(struct hostent));
    int *a = malloc(sizeof(int));
    *a = inet_addr(name);
    if (strcmp(name, "localhost") == 0) *a = INADDR_LOOPBACK;
    if (*a == -1) *a = ba_sh_resolve(name);
    h->h_name = strdup(name);
    h->h_aliases = malloc(sizeof(char *));
    h->h_aliases[0] = 0;
    h->h_addrtype = AF_INET;
    h->h_length = sizeof(in_addr_t);
    h->h_addr_list = malloc(2 * sizeof(char *));
    h->h_addr_list[0] = (char *)a;
    h->h_addr_list[1] = 0;
    return h;
}
