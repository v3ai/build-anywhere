/*
 * term.c: terminal control for the build-anywhere shell tier: <termios.h>
 * and the TIOCGWINSZ ioctl, done with stty(1) by the shell functions in
 * term.sh. In non-canonical mode (ICANON off) getchar and read take bytes
 * from the terminal one at a time, with dd(1), instead of whole lines.
 * Part of build-anywhere.
 */
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
#include "term.sh"

int ba_sh_tcget(int fd);
int ba_sh_tcset(int fd, int flags, int vmin, int vtime);
int ba_sh_winsize(int fd);
int ba_tty_min;
int ba_tty_time;
int ba_tty_speed;

#define BA_TC_L 511
#define BA_TC_I 1048064
#define BA_TC_O 3145728
#define BA_TC_C 1069547520

int tcgetattr(int fd, struct termios *t)
{
    int m = ba_sh_tcget(fd);
    int i;
    if (m == -1) {
        errno = ENOTTY;
        return -1;
    }
    t->c_lflag = m & BA_TC_L;
    t->c_iflag = m & BA_TC_I;
    t->c_oflag = m & BA_TC_O;
    t->c_cflag = m & BA_TC_C;
    t->c_cc = malloc(NCCS * sizeof(cc_t));
    for (i = 0; i < NCCS; i++) t->c_cc[i] = 0;
    t->c_cc[VINTR] = 3;
    t->c_cc[VQUIT] = 28;
    t->c_cc[VERASE] = 127;
    t->c_cc[VKILL] = 21;
    t->c_cc[VEOF] = 4;
    t->c_cc[VSTART] = 17;
    t->c_cc[VSTOP] = 19;
    t->c_cc[VSUSP] = 26;
    t->c_cc[VMIN] = ba_tty_min;
    t->c_cc[VTIME] = ba_tty_time;
    t->c_ispeed = ba_tty_speed;
    t->c_ospeed = ba_tty_speed;
    return 0;
}

int tcsetattr(int fd, int when, struct termios *t)
{
    int m = (t->c_lflag & BA_TC_L) | (t->c_iflag & BA_TC_I) | (t->c_oflag & BA_TC_O) | (t->c_cflag & BA_TC_C);
    int vmin = 1;
    int vtime = 0;
    if (when < 0 || when > 2) {
        errno = EINVAL;
        return -1;
    }
    if (t->c_cc) {
        vmin = t->c_cc[VMIN];
        vtime = t->c_cc[VTIME];
    }
    if (ba_sh_tcset(fd, m, vmin, vtime) != 0) {
        errno = ENOTTY;
        return -1;
    }
    return 0;
}

void cfmakeraw(struct termios *t)
{
    t->c_iflag = t->c_iflag & ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    t->c_oflag = t->c_oflag & ~OPOST;
    t->c_lflag = t->c_lflag & ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    t->c_cflag = (t->c_cflag & ~(CSIZE | PARENB)) | CS8;
    if (t->c_cc) {
        t->c_cc[VMIN] = 1;
        t->c_cc[VTIME] = 0;
    }
}

speed_t cfgetispeed(struct termios *t) { return t->c_ispeed; }
speed_t cfgetospeed(struct termios *t) { return t->c_ospeed; }
int cfsetispeed(struct termios *t, speed_t s) { t->c_ispeed = s; return 0; }
int cfsetospeed(struct termios *t, speed_t s) { t->c_ospeed = s; return 0; }
int cfsetspeed(struct termios *t, speed_t s) { t->c_ispeed = s; t->c_ospeed = s; return 0; }
int tcflush(int fd, int which) { return 0; }
int tcdrain(int fd) { return 0; }
int tcsendbreak(int fd, int duration) { return 0; }

int ioctl(int fd, int request, void *arg)
{
    struct winsize *w = arg;
    int s;
    if (request != TIOCGWINSZ) {
        errno = EINVAL;
        return -1;
    }
    s = ba_sh_winsize(fd);
    if (s < 0) {
        errno = ENOTTY;
        return -1;
    }
    w->ws_row = s / 65536;
    w->ws_col = s % 65536;
    w->ws_xpixel = 0;
    w->ws_ypixel = 0;
    return 0;
}
