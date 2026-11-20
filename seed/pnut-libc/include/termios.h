/* termios.h: build-anywhere shell tier (pnut-sh). Terminal attributes are
 * read and set with stty(1), see term.c.
 *
 * Differences from C: pnut cannot take the address of a variable or hold an
 * array in a struct, so allocate the struct (malloc(sizeof(struct termios)))
 * and note that c_cc is a pointer that tcgetattr fills in. tcsetattr applies
 * the flags below and VMIN/VTIME; the other control characters and the
 * speeds are reported but not changed. */
#ifndef _BA_SH_TERMIOS_H
#define _BA_SH_TERMIOS_H

typedef int tcflag_t;
typedef int cc_t;
typedef int speed_t;

struct termios {
    tcflag_t c_iflag;
    tcflag_t c_oflag;
    tcflag_t c_cflag;
    tcflag_t c_lflag;
    cc_t *c_cc;
    speed_t c_ispeed;
    speed_t c_ospeed;
};

#define NCCS 20
#define VINTR 0
#define VQUIT 1
#define VERASE 2
#define VKILL 3
#define VEOF 4
#define VTIME 5
#define VMIN 6
#define VSTART 8
#define VSTOP 9
#define VSUSP 10
#define VEOL 11

/* c_lflag */
#define ICANON 1
#define ECHO 2
#define ECHOE 4
#define ECHOK 8
#define ECHONL 16
#define ISIG 32
#define IEXTEN 64
#define NOFLSH 128
#define TOSTOP 256
/* c_iflag */
#define ICRNL 512
#define INLCR 1024
#define IGNCR 2048
#define IXON 4096
#define IXOFF 8192
#define BRKINT 16384
#define INPCK 32768
#define ISTRIP 65536
#define IGNBRK 131072
#define PARMRK 262144
#define IXANY 524288
#define IGNPAR 0
/* c_oflag */
#define OPOST 1048576
#define ONLCR 2097152
/* c_cflag */
#define PARENB 4194304
#define PARODD 8388608
#define CSTOPB 16777216
#define CREAD 33554432
#define CLOCAL 67108864
#define HUPCL 134217728
#define CSIZE 805306368
#define CS5 0
#define CS6 268435456
#define CS7 536870912
#define CS8 805306368

#define TCSANOW 0
#define TCSADRAIN 1
#define TCSAFLUSH 2
#define TCIFLUSH 0
#define TCOFLUSH 1
#define TCIOFLUSH 2

#define B0 0
#define B50 50
#define B75 75
#define B110 110
#define B134 134
#define B150 150
#define B200 200
#define B300 300
#define B600 600
#define B1200 1200
#define B1800 1800
#define B2400 2400
#define B4800 4800
#define B9600 9600
#define B19200 19200
#define B38400 38400
#define B57600 57600
#define B115200 115200
#define B230400 230400

int tcgetattr(int fd, struct termios *t);
int tcsetattr(int fd, int when, struct termios *t);
void cfmakeraw(struct termios *t);
speed_t cfgetispeed(struct termios *t);
speed_t cfgetospeed(struct termios *t);
int cfsetispeed(struct termios *t, speed_t s);
int cfsetospeed(struct termios *t, speed_t s);
int cfsetspeed(struct termios *t, speed_t s);
int tcflush(int fd, int which);
int tcdrain(int fd);
int tcsendbreak(int fd, int duration);
#endif
