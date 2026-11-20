/* stdint.h: build-anywhere libc (C99; TinyCC's own sources need it). */
#ifndef _BA_STDINT_H
#define _BA_STDINT_H
#include <stddef.h>
typedef signed char int8_t;
typedef short int16_t;
typedef int int32_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
#ifdef __LP64__
typedef long int64_t;
typedef unsigned long uint64_t;
#else
typedef long long int64_t;
typedef unsigned long long uint64_t;
#endif
typedef __PTRDIFF_TYPE__ intptr_t;
typedef __SIZE_TYPE__ uintptr_t;
typedef signed char int_least8_t;
typedef short int_least16_t;
typedef int int_least32_t;
typedef long long int_least64_t;
typedef unsigned char uint_least8_t;
typedef unsigned short uint_least16_t;
typedef unsigned int uint_least32_t;
typedef unsigned long long uint_least64_t;
typedef long long intmax_t;
typedef unsigned long long uintmax_t;
#define INT8_MIN (-128)
#define INT8_MAX 127
#define UINT8_MAX 255
#define INT16_MIN (-32768)
#define INT16_MAX 32767
#define UINT16_MAX 65535
#define INT32_MIN (-2147483647 - 1)
#define INT32_MAX 2147483647
#define UINT32_MAX 4294967295U
#define INT64_MIN (-9223372036854775807LL - 1)
#define INT64_MAX 9223372036854775807LL
#define UINT64_MAX 18446744073709551615ULL
#define INT64_C(c) c ## LL
#define UINT64_C(c) c ## ULL
#define INTMAX_MAX INT64_MAX
#define UINTMAX_MAX UINT64_MAX
#ifdef __LP64__
#define SIZE_MAX 18446744073709551615UL
#define INTPTR_MAX 9223372036854775807L
#define UINTPTR_MAX 18446744073709551615UL
#else
#define SIZE_MAX 4294967295U
#define INTPTR_MAX 2147483647
#define UINTPTR_MAX 4294967295U
#endif
#endif
