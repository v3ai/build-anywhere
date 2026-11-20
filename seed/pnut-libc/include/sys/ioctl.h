/* sys/ioctl.h: build-anywhere shell tier (pnut-sh). Only TIOCGWINSZ, the
 * terminal size, is supported (with stty size, see term.c). */
#ifndef _BA_SH_SYS_IOCTL_H
#define _BA_SH_SYS_IOCTL_H
struct winsize {
    int ws_row;
    int ws_col;
    int ws_xpixel;
    int ws_ypixel;
};
#define TIOCGWINSZ 21523
int ioctl(int fd, int request, void *arg);
#endif
