/* The shell tier's sockets: tests/run.sh runs this server with net-client.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc, char **argv)
{
    struct sockaddr_in *sa = malloc(sizeof(struct sockaddr_in));
    char *buf = malloc(256);
    char *reply = malloc(300);
    int s, c, n, i;
    s = socket(AF_INET, SOCK_STREAM, 0);
    memset(sa, 0, sizeof(struct sockaddr_in));
    sa->sin_family = AF_INET;
    sa->sin_port = htons(atoi(argv[1]));
    sa->sin_addr = htonl(INADDR_ANY);
    if (bind(s, (struct sockaddr *)sa, sizeof(struct sockaddr_in)) < 0 || listen(s, 1) < 0) {
        printf("server: bind failed\n");
        return 1;
    }
    for (i = 0; i < 2; i++) {
        c = accept(s, 0, 0);
        if (c < 0) { printf("server: accept failed\n"); return 1; }
        n = recv(c, buf, 255, 0);
        buf[n] = 0;
        strcpy(reply, "echo: ");
        strcat(reply, buf);
        send(c, reply, strlen(reply), 0);
        close(c);
        printf("server: served %d bytes\n", n);
    }
    close(s);
    return 0;
}
