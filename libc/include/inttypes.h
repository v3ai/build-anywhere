/* inttypes.h: build-anywhere libc (C99; TinyCC's own sources need it). */
#ifndef _BA_INTTYPES_H
#define _BA_INTTYPES_H
#include <stdint.h>
#ifdef __LP64__
#define __BA_PRI64 "l"
#else
#define __BA_PRI64 "ll"
#endif
#define PRId32 "d"
#define PRIu32 "u"
#define PRIx32 "x"
#define PRId64 __BA_PRI64 "d"
#define PRIu64 __BA_PRI64 "u"
#define PRIx64 __BA_PRI64 "x"
#define PRIX64 __BA_PRI64 "X"
#endif
