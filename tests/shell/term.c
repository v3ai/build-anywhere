/* The shell tier's terminal control, run by tests/run.sh in a pseudo-terminal. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

void show(char *what, struct termios *t)
{
    printf("%s: icanon=%d echo=%d isig=%d icrnl=%d opost=%d cs8=%d min=%d time=%d\r\n", what,
           (t->c_lflag & ICANON) != 0, (t->c_lflag & ECHO) != 0, (t->c_lflag & ISIG) != 0,
           (t->c_iflag & ICRNL) != 0, (t->c_oflag & OPOST) != 0, (t->c_cflag & CSIZE) == CS8,
           t->c_cc[VMIN], t->c_cc[VTIME]);
}

int main(void)
{
    struct termios *orig = malloc(sizeof(struct termios));
    struct termios *raw = malloc(sizeof(struct termios));
    struct winsize *ws = malloc(sizeof(struct winsize));
    int c, i;
    if (!isatty(STDIN_FILENO)) {
        printf("stdin is not a terminal\n");
        return 1;
    }
    if (tcgetattr(STDIN_FILENO, orig) != 0) {
        printf("tcgetattr failed\n");
        return 1;
    }
    show("cooked", orig);
    if (tcgetattr(STDOUT_FILENO, raw) == 0) show("stdout", raw);
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, ws) == 0) printf("size %d cols x %d rows\r\n", ws->ws_col, ws->ws_row);
    tcgetattr(STDIN_FILENO, raw);
    cfmakeraw(raw);
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, raw) != 0) printf("tcsetattr failed\r\n");
    tcgetattr(STDIN_FILENO, raw);
    show("raw", raw);
    printf("ready\r\n");
    for (i = 0; i < 3; i++) {
        c = getchar();
        printf("key %d\r\n", c);
    }
    raw->c_cc[VMIN] = 0;
    raw->c_cc[VTIME] = 3;
    tcsetattr(STDIN_FILENO, TCSANOW, raw);
    c = getchar();
    printf("timeout -> %d\r\n", c);
    tcsetattr(STDIN_FILENO, TCSANOW, orig);
    tcgetattr(STDIN_FILENO, raw);
    show("restored", raw);
    return 0;
}
