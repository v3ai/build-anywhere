/* sys/types.h: build-anywhere libc (POSIX subset). */
#ifndef _BA_SYS_TYPES_H
#define _BA_SYS_TYPES_H
#include <stddef.h>
typedef __PTRDIFF_TYPE__ ssize_t;
typedef long off_t;
typedef int pid_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
#endif
