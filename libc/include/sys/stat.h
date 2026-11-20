/* sys/stat.h: build-anywhere libc (POSIX subset). */
#ifndef _BA_SYS_STAT_H
#define _BA_SYS_STAT_H
#include <sys/types.h>
#define S_IRWXU 0700
#define S_IRUSR 0400
#define S_IWUSR 0200
#define S_IXUSR 0100
#define S_IRWXG 070
#define S_IRGRP 040
#define S_IWGRP 020
#define S_IXGRP 010
#define S_IRWXO 07
#define S_IROTH 04
#define S_IWOTH 02
#define S_IXOTH 01
int mkdir(const char *path, mode_t mode);
int chmod(const char *path, mode_t mode);
mode_t umask(mode_t mask);
#endif
