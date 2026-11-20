/* stddef.h: build-anywhere libc. */
#ifndef _BA_STDDEF_H
#define _BA_STDDEF_H
typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#ifndef __cplusplus
typedef __WCHAR_TYPE__ wchar_t;
#endif
#ifndef NULL
#define NULL ((void *)0)
#endif
#define offsetof(type, member) ((size_t)&((type *)0)->member)
#endif
