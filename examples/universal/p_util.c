/* file: p_util.c  (universal C helpers: implementation) */
#include <stdlib.h>
#include <string.h>
#include "p_util.h"

/* Overflow-checked int addition. Returns P_FALSE (and leaves *out alone) on overflow. */
p_bool p_add_int(int a, int b, int *out)
{
    if ((b > 0 && a > INT_MAX - b) || (b < 0 && a < INT_MIN - b))
        return P_FALSE;
    *out = a + b;
    return P_TRUE;
}

/* Overflow-checked int multiplication. Quotients with a negative result use div(),
   which truncates toward zero in every standard; plain `/` may round toward -inf
   in C89, which would let some overflowing products through. */
p_bool p_mul_int(int a, int b, int *out)
{
    if (a > 0) {
        if (b > 0) { if (a > INT_MAX / b) return P_FALSE; }
        else       { if (b < div(INT_MIN, a).quot) return P_FALSE; }
    } else if (a < 0) {
        if (b > 0) { if (a < div(INT_MIN, b).quot) return P_FALSE; }
        else       { if (b != 0 && a < div(INT_MAX, b).quot) return P_FALSE; }
    }
    *out = a * b;
    return P_TRUE;
}

/* Overflow-checked size_t multiplication, e.g. before malloc(n * size). */
p_bool p_mul_size(size_t a, size_t b, size_t *out)
{
    if (a != 0 && b > P_SIZE_MAX / a)
        return P_FALSE;
    *out = a * b;
    return P_TRUE;
}

/* Bounded string copy (C89 has no strlcpy/snprintf). Always NUL-terminates when
   size > 0. Returns strlen(src); truncation happened if result >= size. */
size_t p_strlcpy(char *dst, const char *src, size_t size)
{
    size_t len = strlen(src);
    if (size > 0) {
        size_t n = (len < size - 1) ? len : size - 1;
        memcpy(dst, src, n);
        dst[n] = '\0';
    }
    return len;
}

/* Endian-independent serialization. Cast each byte to p_u32 BEFORE shifting:
   (p[3] << 24) would shift an int into the sign bit, which is undefined. */
void p_store_u32le(unsigned char *p, p_u32 v)
{
    p[0] = (unsigned char)(v & 0xFFu);
    p[1] = (unsigned char)((v >> 8) & 0xFFu);
    p[2] = (unsigned char)((v >> 16) & 0xFFu);
    p[3] = (unsigned char)((v >> 24) & 0xFFu);
}

p_u32 p_load_u32le(const unsigned char *p)
{
    return (p_u32)p[0]
         | ((p_u32)p[1] << 8)
         | ((p_u32)p[2] << 16)
         | ((p_u32)p[3] << 24);
}

void p_store_u32be(unsigned char *p, p_u32 v)
{
    p[0] = (unsigned char)((v >> 24) & 0xFFu);
    p[1] = (unsigned char)((v >> 16) & 0xFFu);
    p[2] = (unsigned char)((v >> 8) & 0xFFu);
    p[3] = (unsigned char)(v & 0xFFu);
}

p_u32 p_load_u32be(const unsigned char *p)
{
    return ((p_u32)p[0] << 24)
         | ((p_u32)p[1] << 16)
         | ((p_u32)p[2] << 8)
         | (p_u32)p[3];
}

/* Rotate left; n is masked so the shift count is always < 32. */
p_u32 p_rotl32(p_u32 x, unsigned n)
{
    n &= 31u;
    return (p_u32)(((x << n) | (x >> ((32u - n) & 31u))) & 0xFFFFFFFFUL);
}

#if P_HAS_64
/* Decimal formatting for 64-bit values (C89 printf cannot print them).
   buf must hold at least 21 bytes. Returns buf. */
char *p_u64_to_dec(char *buf, p_u64 v)
{
    char tmp[21];
    int i = 0, j = 0;
    do {
        tmp[i++] = (char)('0' + (int)(v % 10u));
        v /= 10u;
    } while (v != 0);
    while (i > 0)
        buf[j++] = tmp[--i];
    buf[j] = '\0';
    return buf;
}
#endif
