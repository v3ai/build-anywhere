/* posix.c: POSIX and Linux interfaces that programs built by the bootstrap
   tier get from musl: sockets, select, termios on a pseudo-terminal, threads,
   fork, pipes, directories, shared memory, Linux headers. Prints "posix: ok". */
#define _GNU_SOURCE 1
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <math.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s (errno %d)\n", __LINE__, #c, errno); failed = 1; } } while (0)

static void tcp_loopback(void)
{
    struct sockaddr_in a;
    socklen_t len = sizeof a;
    int srv, cli, con, one = 1;
    char buf[8];
    fd_set rd;
    struct timeval tv;

    srv = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(srv >= 0);
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    CHECK(setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) == 0);
    CHECK(bind(srv, (struct sockaddr *)&a, sizeof a) == 0);
    CHECK(listen(srv, 1) == 0);
    CHECK(getsockname(srv, (struct sockaddr *)&a, &len) == 0);
    cli = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(connect(cli, (struct sockaddr *)&a, sizeof a) == 0);
    CHECK(setsockopt(cli, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one) == 0);
    con = accept(srv, NULL, NULL);
    CHECK(con >= 0);
    CHECK(send(cli, "tcp", 3, 0) == 3);
    FD_ZERO(&rd);
    FD_SET(con, &rd);
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    CHECK(select(con + 1, &rd, NULL, NULL, &tv) == 1);
    CHECK(recv(con, buf, sizeof buf, 0) == 3 && memcmp(buf, "tcp", 3) == 0);
    close(con);
    close(cli);
    close(srv);
}

static void unix_socket(void)
{
    int sv[2];
    char buf[8];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
    CHECK(write(sv[0], "unix", 4) == 4);
    CHECK(read(sv[1], buf, sizeof buf) == 4 && memcmp(buf, "unix", 4) == 0);
    close(sv[0]);
    close(sv[1]);
}

static void terminal(void)
{
    int m, s;
    struct termios t;
    char buf[8];
    if (openpty(&m, &s, NULL, NULL, NULL) != 0) {
        printf("note: no pseudo-terminals here (errno %d)\n", errno);
        return;
    }
    CHECK(isatty(s));
    CHECK(tcgetattr(s, &t) == 0);
    cfmakeraw(&t);
    CHECK(cfsetispeed(&t, B115200) == 0 && cfsetospeed(&t, B115200) == 0);
    CHECK(tcsetattr(s, TCSANOW, &t) == 0);
    CHECK(tcgetattr(s, &t) == 0);
    CHECK(cfgetospeed(&t) == B115200 && !(t.c_lflag & ICANON));
    CHECK(write(m, "pty", 3) == 3);
    CHECK(read(s, buf, sizeof buf) == 3 && memcmp(buf, "pty", 3) == 0);
    close(s);
    close(m);
}

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static long total;

static void *worker(void *arg)
{
    long i, n = (long)arg;
    for (i = 0; i < 20000; i++) {
        pthread_mutex_lock(&mu);
        total += n;
        pthread_mutex_unlock(&mu);
    }
    errno = (int)n;   /* errno is per thread */
    return (void *)(long)(errno == (int)n);
}

static void threads(void)
{
    pthread_t t[4];
    void *r;
    long i, ok = 0;
    errno = 0;
    for (i = 0; i < 4; i++) CHECK(pthread_create(&t[i], NULL, worker, (void *)(i + 1)) == 0);
    for (i = 0; i < 4; i++) {
        CHECK(pthread_join(t[i], &r) == 0);
        ok += (long)r;
    }
    CHECK(total == 200000 && ok == 4 && errno == 0);
}

static void processes(void)
{
    int p[2], st;
    pid_t pid;
    char buf[8];
    CHECK(pipe(p) == 0);
    pid = fork();
    if (pid == 0) {
        write(p[1], "child", 5);
        _exit(7);
    }
    CHECK(pid > 0);
    CHECK(read(p[0], buf, sizeof buf) == 5 && memcmp(buf, "child", 5) == 0);
    CHECK(waitpid(pid, &st, 0) == pid && WIFEXITED(st) && WEXITSTATUS(st) == 7);
    close(p[0]);
    close(p[1]);
}

static void files(void)
{
    DIR *d = opendir(".");
    struct dirent *e;
    struct stat sb;
    int n = 0, id;
    char *mem;
    CHECK(d != NULL);
    while (d && (e = readdir(d)) != NULL) n++;
    if (d) closedir(d);
    CHECK(n >= 2);
    CHECK(stat(".", &sb) == 0 && S_ISDIR(sb.st_mode));
    id = shmget(IPC_PRIVATE, 4096, IPC_CREAT | 0600);
    if (id >= 0) {
        mem = shmat(id, NULL, 0);
        CHECK(mem != (char *)-1);
        if (mem != (char *)-1) {
            strcpy(mem, "shm");
            CHECK(strcmp(mem, "shm") == 0);
            shmdt(mem);
        }
        shmctl(id, IPC_RMID, NULL);
    }
}

int main(void)
{
    char buf[64];
    struct in_addr ia;
    CHECK(sizeof(struct usbdevfs_ctrltransfer) > 0);
    CHECK(inet_pton(AF_INET, "192.168.1.20", &ia) == 1 && strcmp(inet_ntoa(ia), "192.168.1.20") == 0);
    snprintf(buf, sizeof buf, "%.6f %g %e", atan2(1.0, 1.0) * 4.0, sqrt(2.0), 1e300);
    CHECK(strcmp(buf, "3.141593 1.41421 1.000000e+300") == 0);
    tcp_loopback();
    unix_socket();
    terminal();
    threads();
    processes();
    files();
    signal(SIGPIPE, SIG_IGN);
    if (!failed) printf("posix: ok\n");
    return failed;
}
