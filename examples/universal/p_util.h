/* file: p_util.h  (universal C helpers: declarations) */
#ifndef P_UTIL_H
#define P_UTIL_H

#include "port.h"

P_BEGIN_DECLS

p_bool p_add_int(int a, int b, int *out);
p_bool p_mul_int(int a, int b, int *out);
p_bool p_mul_size(size_t a, size_t b, size_t *out);
size_t p_strlcpy(char *dst, const char *src, size_t size);
void   p_store_u32le(unsigned char *p, p_u32 v);
p_u32  p_load_u32le(const unsigned char *p);
void   p_store_u32be(unsigned char *p, p_u32 v);
p_u32  p_load_u32be(const unsigned char *p);
p_u32  p_rotl32(p_u32 x, unsigned n);
#if P_HAS_64
char  *p_u64_to_dec(char *buf, p_u64 v);
#endif

/* Safe worst-case buffer size for sprintf("%d") of an int. Use sprintf ONLY
   when the buffer size is provably sufficient. Copy strings with p_strlcpy. */
#define P_INT_DEC_BUF (sizeof(int) * CHAR_BIT / 3 + 3)

P_END_DECLS

#endif /* P_UTIL_H */
