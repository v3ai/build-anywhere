/* The shell tier's sockets: a client of net-server.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

int main(int argc, char **argv)
{
    struct sockaddr_in *sa = malloc(sizeof(struct sockaddr_in));
    struct hostent *h;
    char *buf = malloc(256);
    int s, n;
    h = gethostbyname(argv[1]);
    memset(sa, 0, sizeof(struct sockaddr_in));
    sa->sin_family = AF_INET;
    sa->sin_port = htons(atoi(argv[2]));
    memcpy(&sa->sin_addr, h->h_addr, h->h_length);
    s = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(s, (struct sockaddr *)sa, sizeof(struct sockaddr_in)) < 0) {
        printf("client: connect failed\n");
        return 1;
    }
    send(s, argv[3], strlen(argv[3]), 0);
    send(s, "\n", 1, 0);
    n = recv(s, buf, 255, 0);
    buf[n] = 0;
    printf("client got: %s", buf);
    printf("inet_ntoa(inet_addr(10.1.2.3)) = %s\n", inet_ntoa(inet_addr("10.1.2.3")));
    close(s);
    return 0;
}
