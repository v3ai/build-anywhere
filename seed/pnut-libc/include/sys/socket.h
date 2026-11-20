/* sys/socket.h: build-anywhere shell tier (pnut-sh). TCP over IPv4 only,
 * see net.c for how a shell makes connections and what differs from C. */
#ifndef _BA_SH_SYS_SOCKET_H
#define _BA_SH_SYS_SOCKET_H
typedef int socklen_t;
typedef int sa_family_t;
struct sockaddr {
    sa_family_t sa_family;
    int sa_data0;
    int sa_data1;
    int sa_data2;
};
#define AF_UNSPEC 0
#define AF_INET 2
#define PF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 1
#define SO_REUSEADDR 2
#define SO_KEEPALIVE 9
#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2
#define MSG_NOSIGNAL 0
int socket(int domain, int type, int protocol);
int connect(int fd, struct sockaddr *addr, socklen_t len);
int bind(int fd, struct sockaddr *addr, socklen_t len);
int listen(int fd, int backlog);
int accept(int fd, struct sockaddr *addr, socklen_t *len);
int send(int fd, void *buf, int n, int flags);
int recv(int fd, void *buf, int n, int flags);
int shutdown(int fd, int how);
int setsockopt(int fd, int level, int name, void *val, socklen_t len);
#endif
