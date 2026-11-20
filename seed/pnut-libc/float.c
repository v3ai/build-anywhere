/*
 * float.c: floating point for the build-anywhere shell tier.
 *
 * Shell arithmetic has only integers, so pnut-sh keeps a double as its
 * IEEE-754 binary64 bit pattern in a 64-bit shell integer and turns every
 * floating-point operation into a call to the functions below (see
 * seed/pnut/sh-float.c). They implement IEEE-754 arithmetic with
 * round-to-nearest-even on those integers: + - * / and sqrt are correctly
 * rounded, comparisons follow IEEE (NaN is unordered), printf's %f %e %g
 * and strtod convert exactly, like glibc and musl. The <math.h> functions
 * use the fdlibm algorithms and are within 2 ulp of glibc's.
 *
 * cc-pnut.sh compiles this file with programs that use float or double.
 * Like libc.c it is written in the C subset that pnut-sh supports. It
 * needs a shell with 64-bit arithmetic, which it checks when it starts.
 * Part of build-anywhere (MIT).
 */
#ifndef BA_NATIVE
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#endif

#ifdef BA_NATIVE
/* Native test build: the integer half compiled by a normal C compiler. */
typedef long long ba_i64;
#else
typedef int ba_i64;
#include "float-check.sh"
#endif

/* Bit patterns. */
ba_i64 ba_f_hid = (ba_i64)1 << 52;                                   /* 2^52, the implicit bit */
ba_i64 ba_f_mant = ((ba_i64)1 << 52) - 1;                            /* fraction field */
ba_i64 ba_f_inf = (ba_i64)2047 << 52;                                /* +inf */
ba_i64 ba_f_absm = ((ba_i64)1 << 62) - 1 + ((ba_i64)1 << 62);        /* all but the sign */
ba_i64 ba_f_sign = -((ba_i64)1 << 62) - ((ba_i64)1 << 62);           /* the sign bit */
ba_i64 ba_f_qbit = (ba_i64)1 << 51;                                  /* quiet NaN bit */
ba_i64 ba_f_dnan = -((ba_i64)1 << 62) - ((ba_i64)1 << 62) + ((ba_i64)4095 << 51); /* x86's default NaN */
ba_i64 ba_f_one = (ba_i64)1023 << 52;                                /* 1.0 */

/* -0.0 is the bit pattern -2^63, a number dash cannot read back when it is
 * written in an arithmetic expansion, as pnut does with every function
 * argument. So -0.0 is represented by a signaling NaN pattern instead,
 * 0xFFF0000000000001, and no value is ever -2^63. */
ba_i64 ba_f_nz = -(((ba_i64)1 << 52) - 1);

/* |x| as bits */
ba_i64 ba_f_abs(ba_i64 x)
{
    if (x == ba_f_nz) return 0;
    return x & ba_f_absm;
}

/* The double with sign s (0 or 1) and magnitude bits a */
ba_i64 ba_f_mk(int s, ba_i64 a)
{
    if (a == 0) {
        if (s) return ba_f_nz;
        return 0;
    }
    if (s) return a | ba_f_sign;
    return a;
}

/* ------------------------------------------------------------------ */
/* Packing and unpacking                                               */

int ba_f_bitlen(ba_i64 m)
{
    int n = 0;
    if (m >= ((ba_i64)1 << 32)) { n = n + 32; m = m >> 32; }
    if (m >= 65536) { n = n + 16; m = m >> 16; }
    if (m >= 256) { n = n + 8; m = m >> 8; }
    if (m >= 16) { n = n + 4; m = m >> 4; }
    if (m >= 4) { n = n + 2; m = m >> 2; }
    if (m >= 2) { n = n + 1; m = m >> 1; }
    return n + (int)m;
}

/* The double nearest to m * 2^e (0 <= m < 2^63), with sign s (0 or 1);
 * sticky says that nonzero bits below m were dropped. */
ba_i64 ba_f_pack(int s, ba_i64 m, int e, int sticky)
{
    int len, biased, drop, rnd;
    ba_i64 sign = 0;
    if (s) sign = ba_f_sign;
    if (m == 0) return ba_f_mk(s, 0);
    len = ba_f_bitlen(m);
    biased = len - 1 + e + 1023;
    if (biased >= 1) drop = len - 53;
    else drop = -(e + 1074);
    if (drop > 0) {
        if (drop > 63) {
            return ba_f_mk(s, 0);
        } else {
            rnd = (int)((m >> (drop - 1)) & 1);
            if ((m & ((((ba_i64)1) << (drop - 1)) - 1)) != 0) sticky = 1;
            m = m >> drop;
            if (rnd && (sticky || (m & 1))) m = m + 1;
        }
    } else if (drop < 0) {
        m = m << -drop;
    }
    if (biased < 1) {
        /* subnormal; rounding up to 2^52 gives the smallest normal number,
           whose bit pattern is the same integer */
        return ba_f_mk(s, m);
    }
    if (m >= ((ba_i64)1 << 53)) {
        m = m >> 1;
        biased = biased + 1;
    }
    if (biased >= 2047) return sign | ba_f_inf;
    return sign | ((ba_i64)biased << 52) | (m - ba_f_hid);
}

/* Unpack a finite nonzero |x| (sign removed) into a mantissa in
 * [2^52, 2^53) and an exponent: |x| = ba_f_m * 2^ba_f_e. */
ba_i64 ba_f_m;
int ba_f_e;

void ba_f_unpack(ba_i64 ax)
{
    int e = (int)(ax >> 52);
    ba_i64 m = ax & ba_f_mant;
    int sh;
    if (e == 0) {
        sh = 53 - ba_f_bitlen(m);
        m = m << sh;
        e = 1 - sh;
    } else {
        m = m | ba_f_hid;
    }
    ba_f_m = m;
    ba_f_e = e - 1075;
}

int ba_f_isnan(ba_i64 x) { return x != ba_f_nz && (x & ba_f_absm) > ba_f_inf; }

/* ------------------------------------------------------------------ */
/* Arithmetic                                                          */

ba_i64 ba_dneg(ba_i64 x)
{
    if (x == 0) return ba_f_nz;
    if (x == ba_f_nz) return 0;
    return x ^ ba_f_sign;
}

/* c ? a : b, for ?: expressions whose branches compute with doubles */
ba_i64 ba_sel(int c, ba_i64 a, ba_i64 b)
{
    if (c) return a;
    return b;
}

ba_i64 ba_dadd(ba_i64 a, ba_i64 b)
{
    ba_i64 aa = ba_f_abs(a), ab = ba_f_abs(b), t, ma, mb, m;
    int ea, eb, d, sa, sb, sticky = 0;
    if (aa > ba_f_inf) return a | ba_f_qbit;
    if (ab > ba_f_inf) return b | ba_f_qbit;
    if (aa == ba_f_inf) {
        if (ab == ba_f_inf && (a ^ b) < 0) return ba_f_dnan;
        return a;
    }
    if (ab == ba_f_inf) return b;
    if (aa == 0) {
        if (ab == 0) {
            if (a < 0 && b < 0) return ba_f_nz;
            return 0;
        }
        return b;
    }
    if (ab == 0) return a;
    if (aa < ab) { /* make |a| >= |b| */
        t = a; a = b; b = t;
        t = aa; aa = ab; ab = t;
    }
    sa = a < 0;
    sb = b < 0;
    ea = (int)(aa >> 52);
    ma = aa & ba_f_mant;
    if (ea == 0) ea = 1; else ma = ma | ba_f_hid;
    eb = (int)(ab >> 52);
    mb = ab & ba_f_mant;
    if (eb == 0) eb = 1; else mb = mb | ba_f_hid;
    ma = ma << 3;
    mb = mb << 3;
    d = ea - eb;
    if (d > 0) {
        if (d > 58) {
            sticky = mb != 0;
            mb = 0;
        } else {
            if ((mb & ((((ba_i64)1) << d) - 1)) != 0) sticky = 1;
            mb = mb >> d;
        }
    }
    if (sa == sb) {
        m = ma + mb;
    } else {
        m = ma - mb;
        if (sticky) m = m - 1;
        if (m == 0 && !sticky) return 0;
    }
    return ba_f_pack(sa, m, ea - 1078, sticky);
}

ba_i64 ba_dsub(ba_i64 a, ba_i64 b)
{
    if (ba_f_isnan(b)) return ba_dadd(a, b);
    return ba_dadd(a, ba_dneg(b));
}

ba_i64 ba_dmul(ba_i64 a, ba_i64 b)
{
    ba_i64 aa = ba_f_abs(a), ab = ba_f_abs(b), sign = (a ^ b) & ba_f_sign;
    ba_i64 ma, mb, ah, al, bh, bl, p1, lo, hi, m26 = ((ba_i64)1 << 26) - 1;
    int ea, eb;
    if (aa > ba_f_inf) return a | ba_f_qbit;
    if (ab > ba_f_inf) return b | ba_f_qbit;
    if (aa == ba_f_inf || ab == ba_f_inf) {
        if (aa == 0 || ab == 0) return ba_f_dnan;
        return sign | ba_f_inf;
    }
    if (aa == 0 || ab == 0) return ba_f_mk(sign != 0, 0);
    ba_f_unpack(aa); ma = ba_f_m; ea = ba_f_e;
    ba_f_unpack(ab); mb = ba_f_m; eb = ba_f_e;
    /* 53 x 53 bits in 26-bit halves: P = hi * 2^52 + lo */
    ah = ma >> 26; al = ma & m26;
    bh = mb >> 26; bl = mb & m26;
    p1 = ah * bl + al * bh;
    lo = al * bl + ((p1 & m26) << 26);
    hi = ah * bh + (p1 >> 26) + (lo >> 52);
    lo = lo & ba_f_mant;
    /* keep 8 more bits for rounding */
    return ba_f_pack(sign != 0, (hi << 8) | (lo >> 44), ea + eb + 44,
                     (lo & ((((ba_i64)1) << 44) - 1)) != 0);
}

ba_i64 ba_ddiv(ba_i64 a, ba_i64 b)
{
    ba_i64 aa = ba_f_abs(a), ab = ba_f_abs(b), sign = (a ^ b) & ba_f_sign;
    ba_i64 ma, mb, q, r;
    int ea, eb, i;
    if (aa > ba_f_inf) return a | ba_f_qbit;
    if (ab > ba_f_inf) return b | ba_f_qbit;
    if (aa == ba_f_inf) {
        if (ab == ba_f_inf) return ba_f_dnan;
        return sign | ba_f_inf;
    }
    if (ab == ba_f_inf) return ba_f_mk(sign != 0, 0);
    if (ab == 0) {
        if (aa == 0) return ba_f_dnan;
        return sign | ba_f_inf;
    }
    if (aa == 0) return ba_f_mk(sign != 0, 0);
    ba_f_unpack(aa); ma = ba_f_m; ea = ba_f_e;
    ba_f_unpack(ab); mb = ba_f_m; eb = ba_f_e;
    /* long division, 9 bits at a time: q = ma * 2^54 / mb */
    q = ma / mb;
    r = ma % mb;
    i = 0;
    while (i < 6) {
        r = r << 9;
        q = (q << 9) | (r / mb);
        r = r % mb;
        i = i + 1;
    }
    return ba_f_pack(sign != 0, q, ea - eb - 54, r != 0);
}

ba_i64 ba_dsqrt(ba_i64 x)
{
    ba_i64 m, rem, root, trial, pair;
    int e, i, b;
    if (x == 0 || x == ba_f_nz) return x;            /* +-0 */
    if (x < 0) {
        if ((x & ba_f_absm) > ba_f_inf) return x | ba_f_qbit;
        return ba_f_dnan;
    }
    if (x >= ba_f_inf) return x | (x > ba_f_inf ? ba_f_qbit : 0);
    ba_f_unpack(x);
    m = ba_f_m;
    e = ba_f_e;
    if (e & 1) { m = m << 1; e = e - 1; }
    /* root = floor(sqrt(m * 2^54)), two bits of the radicand at a time */
    rem = 0;
    root = 0;
    i = 53;
    while (i >= 0) {
        b = 2 * i - 54;
        pair = 0;
        if (b >= 0) pair = (m >> b) & 3;
        rem = (rem << 2) | pair;
        trial = (root << 2) | 1;
        root = root << 1;
        if (rem >= trial) {
            rem = rem - trial;
            root = root | 1;
        }
        i = i - 1;
    }
    return ba_f_pack(0, root, (e - 54) / 2, rem != 0);
}

/* ------------------------------------------------------------------ */
/* Comparisons and conversions                                         */

ba_i64 ba_f_key(ba_i64 x)
{
    if (x == ba_f_nz) return 0;
    if (x >= 0) return x;
    return -(x & ba_f_absm);
}

int ba_dlt(ba_i64 a, ba_i64 b)
{
    if (ba_f_isnan(a) || ba_f_isnan(b)) return 0;
    return ba_f_key(a) < ba_f_key(b);
}

int ba_dle(ba_i64 a, ba_i64 b)
{
    if (ba_f_isnan(a) || ba_f_isnan(b)) return 0;
    return ba_f_key(a) <= ba_f_key(b);
}

int ba_deq(ba_i64 a, ba_i64 b)
{
    if (ba_f_isnan(a) || ba_f_isnan(b)) return 0;
    return ba_f_key(a) == ba_f_key(b);
}

int ba_dtrue(ba_i64 x) { return x != 0 && x != ba_f_nz; }

ba_i64 ba_itod(ba_i64 i)
{
    if (i >= 0) return ba_f_pack(0, i, 0, 0);
    if (i == ba_f_sign) return ba_f_pack(1, (ba_i64)1 << 62, 1, 0);
    return ba_f_pack(1, -i, 0, 0);
}

/* Truncate toward zero. Out of range and NaN give -(2^63 - 1) (x86 gives
 * -2^63, which dash cannot pass around). */
ba_i64 ba_dtoi(ba_i64 x)
{
    ba_i64 ax = ba_f_abs(x), m;
    int e = (int)(ax >> 52);
    if (e < 1023) return 0;
    if (e >= 1023 + 63) return ba_f_sign + 1;
    m = (ax & ba_f_mant) | ba_f_hid;
    if (e >= 1075) m = m << (e - 1075);
    else m = m >> (1075 - e);
    if (x < 0) return -m;
    return m;
}

/* Round to an integral value toward zero (as a double). */
ba_i64 ba_dtrunc(ba_i64 x)
{
    int e = (int)(ba_f_abs(x) >> 52);
    if (e >= 1075) return x;                     /* integral, inf or NaN */
    if (e < 1023) return ba_f_mk(x < 0, 0);      /* +-0 */
    return x & ~((((ba_i64)1) << (1075 - e)) - 1);
}

/* x - y * trunc(x / y), exactly (C's fmod). */
ba_i64 ba_dfmod(ba_i64 x, ba_i64 y)
{
    ba_i64 ax = ba_f_abs(x), ay = ba_f_abs(y), mx, my;
    int ex, ey, k;
    if (ax > ba_f_inf || ay > ba_f_inf) return ba_dadd(x, y);
    if (ax == ba_f_inf || ay == 0) return ba_f_dnan;
    if (ax < ay) return x;
    ba_f_unpack(ax); mx = ba_f_m; ex = ba_f_e;
    ba_f_unpack(ay); my = ba_f_m; ey = ba_f_e;
    mx = mx % my;
    while (ex > ey && mx != 0) {
        k = ex - ey;
        if (k > 9) k = 9;
        mx = (mx << k) % my;
        ex = ex - k;
    }
    if (mx == 0) return ba_f_mk(x < 0, 0);
    return ba_f_pack(x < 0, mx, ey, 0);
}

/* x * 2^n */
ba_i64 ba_dscale(ba_i64 x, int n)
{
    ba_i64 ax = ba_f_abs(x);
    if (ax == 0 || ax >= ba_f_inf) return x;
    if (n > 3000) n = 3000;
    if (n < -3000) n = -3000;
    ba_f_unpack(ax);
    return ba_f_pack(x < 0, ba_f_m, ba_f_e + n, 0);
}

/* ------------------------------------------------------------------ */
/* Big integers (16-bit limbs) for exact decimal conversions           */

#define BA_BN 320

int ba_bn_a[BA_BN];
int ba_bn_b[BA_BN];
int ba_bn_q[BA_BN];

int ba_bn_muladd(int *x, int len, int mul, int add)
{
    int i = 0, carry = add, t;
    while (i < len) {
        t = x[i] * mul + carry;
        x[i] = t & 65535;
        carry = t >> 16;
        i = i + 1;
    }
    while (carry != 0 && len < BA_BN) {
        x[len] = carry & 65535;
        carry = carry >> 16;
        len = len + 1;
    }
    return len;
}

/* x = x / div (div < 32768); returns the remainder. */
int ba_bn_divsmall(int *x, int len, int div)
{
    int i = len - 1, r = 0, cur;
    while (i >= 0) {
        cur = r * 65536 + x[i];
        x[i] = cur / div;
        r = cur % div;
        i = i - 1;
    }
    return r;
}

int ba_bn_bitlen(int *x, int len)
{
    int b, v;
    while (len > 0 && x[len - 1] == 0) len = len - 1;
    if (len == 0) return 0;
    v = x[len - 1];
    b = (len - 1) * 16;
    while (v != 0) { b = b + 1; v = v >> 1; }
    return b;
}

int ba_bn_shl(int *x, int len, int s)
{
    int limbs = s / 16, bits = s % 16, i, nlen, hi, lo;
    if (len == 0) return 0;
    nlen = len + limbs + 1;
    if (nlen > BA_BN) nlen = BA_BN;
    i = nlen - 1;
    while (i >= 0) {
        hi = 0;
        lo = 0;
        if (i - limbs >= 0 && i - limbs < len) hi = x[i - limbs];
        if (i - limbs - 1 >= 0 && i - limbs - 1 < len) lo = x[i - limbs - 1];
        if (bits == 0) x[i] = hi;
        else x[i] = ((hi << bits) | (lo >> (16 - bits))) & 65535;
        i = i - 1;
    }
    while (nlen > 0 && x[nlen - 1] == 0) nlen = nlen - 1;
    return nlen;
}

int ba_bn_shr(int *x, int len, int s)
{
    int limbs = s / 16, bits = s % 16, i = 0, lo, hi;
    while (i < len) {
        lo = 0;
        hi = 0;
        if (i + limbs < len) lo = x[i + limbs];
        if (i + limbs + 1 < len) hi = x[i + limbs + 1];
        x[i] = ((lo >> bits) | (hi << (16 - bits))) & 65535;
        i = i + 1;
    }
    while (len > 0 && x[len - 1] == 0) len = len - 1;
    return len;
}

int ba_bn_ge(int *a, int alen, int *b, int blen)
{
    int i;
    while (alen > 0 && a[alen - 1] == 0) alen = alen - 1;
    while (blen > 0 && b[blen - 1] == 0) blen = blen - 1;
    if (alen != blen) return alen > blen;
    i = alen - 1;
    while (i >= 0) {
        if (a[i] != b[i]) return a[i] > b[i];
        i = i - 1;
    }
    return 1;
}

void ba_bn_sub(int *a, int alen, int *b, int blen)
{
    int i = 0, borrow = 0, t;
    while (i < alen) {
        t = a[i] - borrow;
        if (i < blen) t = t - b[i];
        if (t < 0) { t = t + 65536; borrow = 1; } else borrow = 0;
        a[i] = t;
        i = i + 1;
    }
}

/* The low 63 bits of x as an integer, and whether bits below `drop`
 * are set: used to round a big integer to a double. */
ba_i64 ba_bn_round(int *x, int len, int e, int sticky, int neg)
{
    int bl = ba_bn_bitlen(x, len), drop, i;
    ba_i64 m = 0;
    if (bl == 0) return ba_f_pack(neg, 0, 0, 0);
    drop = bl - 62;
    if (drop > 0) {
        i = 0;
        while (i < len && i < drop / 16) {
            if (x[i] != 0) sticky = 1;
            i = i + 1;
        }
        if (drop % 16 != 0 && i < len && (x[i] & ((1 << (drop % 16)) - 1)) != 0) sticky = 1;
        len = ba_bn_shr(x, len, drop);
        e = e + drop;
    }
    i = len - 1;
    while (i >= 0) {
        m = (m << 16) | x[i];
        i = i - 1;
    }
    return ba_f_pack(neg, m, e, sticky);
}

/* digits[0..nd) (values 0-9) * 10^exp10, correctly rounded; sticky:
 * nonzero digits were dropped after the given ones. */
ba_i64 ba_f_decimal(char *digits, int nd, int exp10, int sticky, int neg)
{
    int nlen = 0, mlen, qlen, i, k, bl, s;
    while (nd > 0 && digits[0] == 0) { digits = digits + 1; nd = nd - 1; }
    while (nd > 0 && digits[nd - 1] == 0) { nd = nd - 1; exp10 = exp10 + 1; }
    if (nd == 0) return ba_f_pack(neg, 0, 0, 0);
    if (nd + exp10 > 310) return ba_f_pack(neg, 1, 5000, 0);   /* infinity */
    if (nd + exp10 < -324) return ba_f_pack(neg, 0, 0, 0);
    i = 0;
    while (i < nd) {
        nlen = ba_bn_muladd(ba_bn_a, nlen, 10, digits[i]);
        i = i + 1;
    }
    if (sticky) {
        nlen = ba_bn_muladd(ba_bn_a, nlen, 10, 1);
        exp10 = exp10 - 1;
    }
    if (exp10 >= 0) {
        i = 0;
        while (i < exp10) {
            nlen = ba_bn_muladd(ba_bn_a, nlen, 10, 0);
            i = i + 1;
        }
        return ba_bn_round(ba_bn_a, nlen, 0, 0, neg);
    }
    ba_bn_b[0] = 1;
    mlen = 1;
    i = 0;
    while (i < -exp10) {
        mlen = ba_bn_muladd(ba_bn_b, mlen, 10, 0);
        i = i + 1;
    }
    k = ba_bn_bitlen(ba_bn_b, mlen) + 57 - ba_bn_bitlen(ba_bn_a, nlen);
    if (k < 0) k = 0;
    nlen = ba_bn_shl(ba_bn_a, nlen, k);
    bl = ba_bn_bitlen(ba_bn_a, nlen) - ba_bn_bitlen(ba_bn_b, mlen);
    if (bl < 0) bl = 0;
    mlen = ba_bn_shl(ba_bn_b, mlen, bl);
    qlen = bl / 16 + 1;
    i = 0;
    while (i < qlen) { ba_bn_q[i] = 0; i = i + 1; }
    s = bl;
    while (s >= 0) {
        if (ba_bn_ge(ba_bn_a, nlen, ba_bn_b, mlen)) {
            ba_bn_sub(ba_bn_a, nlen, ba_bn_b, mlen);
            ba_bn_q[s / 16] = ba_bn_q[s / 16] | (1 << (s % 16));
        }
        mlen = ba_bn_shr(ba_bn_b, mlen, 1);
        s = s - 1;
    }
    return ba_bn_round(ba_bn_q, qlen, -k, ba_bn_bitlen(ba_bn_a, nlen) != 0, neg);
}

/* ------------------------------------------------------------------ */
/* strtod                                                              */

#define BA_MAXDIG 780
char ba_f_dig[BA_MAXDIG];

int ba_f_lower(int c)
{
    if (c >= 'A' && c <= 'Z') return c + 32;
    return c;
}

int ba_f_hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c = ba_f_lower(c);
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

int ba_f_match(char *s, char *word)
{
    int i = 0;
    while (word[i] != 0) {
        if (ba_f_lower(s[i]) != word[i]) return 0;
        i = i + 1;
    }
    return 1;
}

/* A hexadecimal floating-point number: 0x1.8p3 */
ba_i64 ba_strtod_hex(char *p, char **end, int neg)
{
    char *q = p + 2, *start;
    ba_i64 m = 0, lim = (ba_i64)1 << 58;
    int e2 = 0, any = 0, sticky = 0, v, e = 0, esign = 1;
    v = ba_f_hexval(*q);
    while (v >= 0) {
        any = 1;
        if (m < lim) m = m * 16 + v;
        else { e2 = e2 + 4; if (v) sticky = 1; }
        q = q + 1;
        v = ba_f_hexval(*q);
    }
    if (*q == '.') {
        q = q + 1;
        v = ba_f_hexval(*q);
        while (v >= 0) {
            any = 1;
            if (m < lim) { m = m * 16 + v; e2 = e2 - 4; }
            else if (v) sticky = 1;
            q = q + 1;
            v = ba_f_hexval(*q);
        }
    }
    if (!any) {   /* just "0" */
        if (end) *end = p + 1;
        return ba_f_pack(neg, 0, 0, 0);
    }
    if (*q == 'p' || *q == 'P') {
        start = q;
        q = q + 1;
        if (*q == '-') { esign = -1; q = q + 1; }
        else if (*q == '+') q = q + 1;
        if (*q >= '0' && *q <= '9') {
            while (*q >= '0' && *q <= '9') {
                if (e < 100000) e = e * 10 + *q - '0';
                q = q + 1;
            }
        } else {
            q = start;
        }
    }
    if (end) *end = q;
    if (m != 0 && sticky) m = m | 1;    /* keep rounding right: m has 59+ bits */
    return ba_f_pack(neg, m, e2 + esign * e, 0);
}

/* Bits of the double that s starts with; *end gets the first character
 * after it (s itself when there is no number). */
ba_i64 ba_strtod_bits(char *s, char **end)
{
    char *p = s, *start;
    int neg = 0, nd = 0, exp10 = 0, sticky = 0, any = 0, e = 0, esign = 1;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == '\f' || *p == '\v')
        p = p + 1;
    if (*p == '-') { neg = 1; p = p + 1; }
    else if (*p == '+') p = p + 1;
    if (ba_f_match(p, "inf")) {
        p = p + 3;
        if (ba_f_match(p, "inity")) p = p + 5;
        if (end) *end = p;
        return ba_f_pack(neg, 1, 5000, 0);
    }
    if (ba_f_match(p, "nan")) {
        p = p + 3;
        if (*p == '(') {
            start = p + 1;
            while (*start == '_' || (*start >= '0' && *start <= '9') ||
                   (ba_f_lower(*start) >= 'a' && ba_f_lower(*start) <= 'z'))
                start = start + 1;
            if (*start == ')') p = start + 1;
        }
        if (end) *end = p;
        if (neg) return ba_f_inf | ba_f_qbit | ba_f_sign;
        return ba_f_inf | ba_f_qbit;
    }
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X'))
        return ba_strtod_hex(p, end, neg);
    while (*p >= '0' && *p <= '9') {
        any = 1;
        if (nd < BA_MAXDIG) {
            if (nd > 0 || *p != '0') {
                ba_f_dig[nd] = *p - '0';
                nd = nd + 1;
            }
        } else {
            exp10 = exp10 + 1;
            if (*p != '0') sticky = 1;
        }
        p = p + 1;
    }
    if (*p == '.') {
        p = p + 1;
        while (*p >= '0' && *p <= '9') {
            any = 1;
            if (nd == 0 && *p == '0') {
                exp10 = exp10 - 1;
            } else if (nd < BA_MAXDIG) {
                ba_f_dig[nd] = *p - '0';
                nd = nd + 1;
                exp10 = exp10 - 1;
            } else if (*p != '0') {
                sticky = 1;
            }
            p = p + 1;
        }
    }
    if (!any) {
        if (end) *end = s;
        return 0;
    }
    if (*p == 'e' || *p == 'E') {
        start = p;
        p = p + 1;
        if (*p == '-') { esign = -1; p = p + 1; }
        else if (*p == '+') p = p + 1;
        if (*p >= '0' && *p <= '9') {
            while (*p >= '0' && *p <= '9') {
                if (e < 100000) e = e * 10 + *p - '0';
                p = p + 1;
            }
        } else {
            p = start;
        }
    }
    if (end) *end = p;
    return ba_f_decimal(ba_f_dig, nd, exp10 + esign * e, sticky, neg);
}

/* ------------------------------------------------------------------ */
/* printf formatting: %f %e %g with flags, width and precision         */

/* The decimal expansion of a finite |x|: integer digits in ba_fd_int
 * (most significant first, none if the integer part is 0), then fraction
 * digits one at a time from ba_fd_next(). */
#define BA_FDIG 1200
char ba_fd_int[BA_FDIG];
int ba_fd_nint;
int ba_fd_frac[BA_BN];     /* fraction numerator; the fraction is it / 2^ba_fd_fb */
int ba_fd_flen;
int ba_fd_fb;

void ba_fd_start(ba_i64 ax)
{
    ba_i64 m, ip, fp;
    int e, n, i, r, d;
    ba_f_unpack(ax);
    m = ba_f_m;
    e = ba_f_e;
    ba_fd_nint = 0;
    ba_fd_flen = 0;
    ba_fd_fb = 0;
    /* integer part into ba_bn_a, fraction into ba_fd_frac */
    n = 0;
    if (e >= 0) {
        while (m != 0) { ba_bn_a[n] = (int)(m & 65535); m = m >> 16; n = n + 1; }
        n = ba_bn_shl(ba_bn_a, n, e);
    } else {
        ba_fd_fb = -e;
        if (-e < 63) {
            /* m >> -e is the integer part, the low bits the fraction */
            ip = m >> -e;
            fp = m - (ip << -e);
            while (ip != 0) { ba_bn_a[n] = (int)(ip & 65535); ip = ip >> 16; n = n + 1; }
            while (fp != 0) { ba_fd_frac[ba_fd_flen] = (int)(fp & 65535); fp = fp >> 16; ba_fd_flen = ba_fd_flen + 1; }
        } else {
            while (m != 0) { ba_fd_frac[ba_fd_flen] = (int)(m & 65535); m = m >> 16; ba_fd_flen = ba_fd_flen + 1; }
        }
    }
    /* integer digits, 4 at a time from the bottom */
    i = 0;
    while (n > 0) {
        r = ba_bn_divsmall(ba_bn_a, n, 10000);
        while (n > 0 && ba_bn_a[n - 1] == 0) n = n - 1;
        d = 0;
        while (d < 4 && (n > 0 || r != 0)) {
            ba_fd_int[i] = r % 10;
            r = r / 10;
            i = i + 1;
            d = d + 1;
        }
    }
    ba_fd_nint = i;
    /* reverse */
    r = 0;
    while (r < i / 2) {
        d = ba_fd_int[r];
        ba_fd_int[r] = ba_fd_int[i - 1 - r];
        ba_fd_int[i - 1 - r] = d;
        r = r + 1;
    }
}

/* The next fraction digit. */
int ba_fd_next(void)
{
    int d, limb, bit;
    if (ba_fd_flen == 0) return 0;
    ba_fd_flen = ba_bn_muladd(ba_fd_frac, ba_fd_flen, 10, 0);
    limb = ba_fd_fb / 16;
    bit = ba_fd_fb % 16;
    d = 0;
    if (limb < ba_fd_flen) d = ba_fd_frac[limb] >> bit;
    if (limb + 1 < ba_fd_flen) d = d | (ba_fd_frac[limb + 1] << (16 - bit));
    d = d & 15;
    /* clear the digit's bits */
    if (limb < ba_fd_flen) ba_fd_frac[limb] = ba_fd_frac[limb] & ((1 << bit) - 1);
    if (limb + 1 < ba_fd_flen) ba_fd_frac[limb + 1] = 0;
    if (limb + 2 < ba_fd_flen) ba_fd_frac[limb + 2] = 0;
    while (ba_fd_flen > 0 && ba_fd_frac[ba_fd_flen - 1] == 0) ba_fd_flen = ba_fd_flen - 1;
    return d;
}

/* The digits to print, in ba_fd_out[0..ba_fd_n), and the decimal exponent
 * of the first one. */
char ba_fd_out[BA_FDIG + 1200];
int ba_fd_n;
int ba_fd_exp;

/* Round the digits to ba_fd_n, given the next digit and whether anything
 * nonzero follows; returns 1 if a carry added a leading digit. */
int ba_fd_round(int next, int rest)
{
    int i;
    if (next < 5) return 0;
    if (next == 5 && !rest && (ba_fd_n == 0 || ba_fd_out[ba_fd_n - 1] % 2 == 0)) return 0;
    i = ba_fd_n - 1;
    while (i >= 0) {
        if (ba_fd_out[i] < 9) {
            ba_fd_out[i] = ba_fd_out[i] + 1;
            return 0;
        }
        ba_fd_out[i] = 0;
        i = i - 1;
    }
    /* all nines: 1 followed by zeros */
    i = ba_fd_n;
    while (i > 0) { ba_fd_out[i] = ba_fd_out[i - 1]; i = i - 1; }
    ba_fd_out[0] = 1;
    ba_fd_n = ba_fd_n + 1;
    return 1;
}

/* %f: the integer digits and prec fraction digits of |x|. */
void ba_fd_fixed(ba_i64 ax, int prec)
{
    int i = 0, next;
    ba_fd_start(ax);
    ba_fd_n = 0;
    if (ba_fd_nint == 0) {
        ba_fd_out[0] = 0;
        ba_fd_n = 1;
    } else {
        while (i < ba_fd_nint) { ba_fd_out[ba_fd_n] = ba_fd_int[i]; ba_fd_n = ba_fd_n + 1; i = i + 1; }
    }
    i = 0;
    while (i < prec) {
        ba_fd_out[ba_fd_n] = ba_fd_next();
        ba_fd_n = ba_fd_n + 1;
        i = i + 1;
    }
    next = ba_fd_next();
    ba_fd_round(next, ba_fd_flen != 0);
    ba_fd_exp = ba_fd_n - prec - 1;   /* number of integer digits - 1 */
}

/* %e: ndig significant digits of |x| (nonzero) and the exponent. */
void ba_fd_sci(ba_i64 ax, int ndig)
{
    int i = 0, next, rest = 0, d;
    ba_fd_start(ax);
    ba_fd_n = 0;
    if (ba_fd_nint > 0) {
        ba_fd_exp = ba_fd_nint - 1;
        while (i < ba_fd_nint && ba_fd_n < ndig) {
            ba_fd_out[ba_fd_n] = ba_fd_int[i];
            ba_fd_n = ba_fd_n + 1;
            i = i + 1;
        }
        if (i < ba_fd_nint) {
            next = ba_fd_int[i];
            i = i + 1;
            while (i < ba_fd_nint) {
                if (ba_fd_int[i] != 0) rest = 1;
                i = i + 1;
            }
            if (ba_fd_flen != 0) rest = 1;
            if (ba_fd_round(next, rest)) { ba_fd_exp = ba_fd_exp + 1; ba_fd_n = ba_fd_n - 1; }
            return;
        }
    } else {
        ba_fd_exp = -1;
        d = ba_fd_next();
        while (d == 0) {
            ba_fd_exp = ba_fd_exp - 1;
            d = ba_fd_next();
        }
        ba_fd_out[0] = d;
        ba_fd_n = 1;
    }
    while (ba_fd_n < ndig) {
        ba_fd_out[ba_fd_n] = ba_fd_next();
        ba_fd_n = ba_fd_n + 1;
    }
    next = ba_fd_next();
    if (ba_fd_round(next, ba_fd_flen != 0)) { ba_fd_exp = ba_fd_exp + 1; ba_fd_n = ba_fd_n - 1; }
}

/* Output buffers: printf may format several numbers before printing. */
#define BA_FBUFS 8
/* pnut does not zero global arrays, so these are initialized explicitly */
char *ba_fbuf[BA_FBUFS] = { 0, 0, 0, 0, 0, 0, 0, 0 };
int ba_fbuf_size[BA_FBUFS] = { 0, 0, 0, 0, 0, 0, 0, 0 };
int ba_fbuf_next;
char *ba_fo;            /* buffer being written */
int ba_fo_n;
char ba_fo_tmp[2600];   /* the number before padding */

void ba_fo_put(int c)
{
    ba_fo_tmp[ba_fo_n] = c;
    ba_fo_n = ba_fo_n + 1;
}

void ba_fo_digits(int from, int to)   /* ba_fd_out[from..to), 0 past the end */
{
    while (from < to) {
        if (from < ba_fd_n && from >= 0) ba_fo_put('0' + ba_fd_out[from]);
        else ba_fo_put('0');
        from = from + 1;
    }
}

void ba_fo_exp(int e, int upper)
{
    ba_fo_put(upper ? 'E' : 'e');
    if (e < 0) { ba_fo_put('-'); e = -e; } else ba_fo_put('+');
    if (e >= 100) ba_fo_put('0' + e / 100);
    ba_fo_put('0' + (e / 10) % 10);
    ba_fo_put('0' + e % 10);
}

/* Format x (bits) like printf's %<flags><width>.<prec><conv>.
 * flags: 1 '-', 2 '+', 4 ' ', 8 '#', 16 '0'. width and prec are -1 when
 * not given. Returns a string that stays valid for the next 7 calls. */
char *ba_dfmt(ba_i64 x, int conv, int flags, int width, int prec)
{
    ba_i64 ax = ba_f_abs(x);
    int upper = conv == 'F' || conv == 'E' || conv == 'G';
    int lconv = conv;
    int strip = 0, i, pad, signc = 0, body, need, P, X;
    char *out;
    if (lconv == 'F' || lconv == 'E' || lconv == 'G') lconv = lconv + 32;
    if (width < 0) {
        if (width != -1) flags = flags | 1;   /* negative * width: left-justify */
        width = -width;
        if (width == 1) width = 0;
    }
    if (prec < 0) prec = 6;
    if (prec > 1100) prec = 1100;
    ba_fo_n = 0;
    if (x < 0) signc = '-';
    else if (flags & 2) signc = '+';
    else if (flags & 4) signc = ' ';
    if (ax >= ba_f_inf) {
        flags = flags & ~16;
        if (ax == ba_f_inf) {
            if (upper) { ba_fo_put('I'); ba_fo_put('N'); ba_fo_put('F'); }
            else { ba_fo_put('i'); ba_fo_put('n'); ba_fo_put('f'); }
        } else {
            if (upper) { ba_fo_put('N'); ba_fo_put('A'); ba_fo_put('N'); }
            else { ba_fo_put('n'); ba_fo_put('a'); ba_fo_put('n'); }
        }
    } else if (lconv == 'f') {
        if (ax == 0) {
            ba_fd_n = 0;
            ba_fd_exp = 0;
        } else {
            ba_fd_fixed(ax, prec);
        }
        ba_fo_digits(0, ba_fd_exp + 1);
        if (prec > 0 || (flags & 8)) ba_fo_put('.');
        ba_fo_digits(ba_fd_exp + 1, ba_fd_exp + 1 + prec);
    } else if (lconv == 'e') {
        if (ax == 0) { ba_fd_n = 0; ba_fd_exp = 0; }
        else ba_fd_sci(ax, prec + 1);
        ba_fo_digits(0, 1);
        if (prec > 0 || (flags & 8)) ba_fo_put('.');
        ba_fo_digits(1, prec + 1);
        ba_fo_exp(ba_fd_exp, upper);
    } else { /* g */
        P = prec;
        if (P == 0) P = 1;
        if (ax == 0) X = 0;
        else { ba_fd_sci(ax, P); X = ba_fd_exp; }
        strip = !(flags & 8);
        if (P > X && X >= -4) {
            prec = P - 1 - X;
            if (ax == 0) { ba_fd_n = 0; ba_fd_exp = 0; }
            else ba_fd_fixed(ax, prec);
            ba_fo_digits(0, ba_fd_exp + 1);
            if (prec > 0 || (flags & 8)) ba_fo_put('.');
            ba_fo_digits(ba_fd_exp + 1, ba_fd_exp + 1 + prec);
            if (strip && prec > 0) {
                while (ba_fo_tmp[ba_fo_n - 1] == '0') ba_fo_n = ba_fo_n - 1;
                if (ba_fo_tmp[ba_fo_n - 1] == '.') ba_fo_n = ba_fo_n - 1;
            }
        } else {
            prec = P - 1;
            ba_fo_digits(0, 1);
            if (prec > 0 || (flags & 8)) ba_fo_put('.');
            ba_fo_digits(1, prec + 1);
            if (strip && prec > 0) {
                while (ba_fo_tmp[ba_fo_n - 1] == '0') ba_fo_n = ba_fo_n - 1;
                if (ba_fo_tmp[ba_fo_n - 1] == '.') ba_fo_n = ba_fo_n - 1;
            }
            ba_fo_exp(X, upper);
        }
    }
    body = ba_fo_n;
    if (signc) body = body + 1;
    need = body;
    if (width > need) need = width;
    i = ba_fbuf_next;
    ba_fbuf_next = (ba_fbuf_next + 1) % BA_FBUFS;
    if (ba_fbuf_size[i] < need + 1) {
        if (ba_fbuf[i]) free(ba_fbuf[i]);
        ba_fbuf_size[i] = need + 64;
        ba_fbuf[i] = malloc(ba_fbuf_size[i]);
    }
    out = ba_fbuf[i];
    ba_fo = out;
    pad = need - body;
    i = 0;
    if (!(flags & 1) && !(flags & 16)) while (pad > 0) { out[i] = ' '; i = i + 1; pad = pad - 1; }
    if (signc) { out[i] = signc; i = i + 1; }
    if (!(flags & 1) && (flags & 16)) while (pad > 0) { out[i] = '0'; i = i + 1; pad = pad - 1; }
    body = 0;
    while (body < ba_fo_n) { out[i] = ba_fo_tmp[body]; i = i + 1; body = body + 1; }
    while (pad > 0) { out[i] = ' '; i = i + 1; pad = pad - 1; }
    out[i] = 0;
    return out;
}

/* ------------------------------------------------------------------ */
/* The double API: <stdlib.h> conversions and <math.h>                 */
/*
 * The transcendental functions below are translations of fdlibm, through
 * musl's versions of them:
 *
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 */

#ifdef BA_NATIVE
/* the shell representation: -0.0 is ba_f_nz */
ba_i64 ba_bits(double d) { ba_i64 b; memcpy(&b, &d, 8); if (b == ba_f_sign) b = ba_f_nz; return b; }
double ba_from_bits(ba_i64 b) { double d; if (b == ba_f_nz) b = ba_f_sign; memcpy(&d, &b, 8); return d; }
#endif

ba_i64 ba_f_m32 = ((ba_i64)1 << 32) - 1;

/* The high 32 bits of x without the sign, and with it. */
int ba_ix(double x) { return (int)((ba_f_abs(ba_bits(x)) >> 32) & 2147483647); }
int ba_sgn(double x) { return ba_bits(x) < 0; }
double ba_clear_lo(double x) { return ba_from_bits(ba_f_mk(ba_bits(x) < 0, ba_f_abs(ba_bits(x)) & ~ba_f_m32)); }
double ba_with_hi(double x, ba_i64 hi) { return ba_from_bits((hi << 32) | (ba_bits(x) & ba_f_m32)); }

double strtod(char *s, char **end) { return ba_from_bits(ba_strtod_bits(s, end)); }
double atof(char *s) { return ba_from_bits(ba_strtod_bits(s, 0)); }

double ba_nan(void) { return ba_from_bits(ba_f_inf | ba_f_qbit); }
double nan(char *tag) { return ba_from_bits(ba_f_inf | ba_f_qbit); }
int ba_isnan(double x) { return ba_f_isnan(ba_bits(x)); }
int ba_isinf(double x) { return ba_f_abs(ba_bits(x)) == ba_f_inf; }
int ba_isfinite(double x) { return ba_f_abs(ba_bits(x)) < ba_f_inf; }
int ba_signbit(double x) { return ba_bits(x) < 0; }
int ba_fpclassify(double x)
{
    ba_i64 a = ba_f_abs(ba_bits(x));
    if (a == 0) return 2;
    if (a > ba_f_inf) return 0;
    if (a == ba_f_inf) return 1;
    if (a < ba_f_hid) return 3;
    return 4;
}

double fabs(double x) { return ba_from_bits(ba_f_abs(ba_bits(x))); }
double copysign(double x, double y) { return ba_from_bits(ba_f_mk(ba_bits(y) < 0, ba_f_abs(ba_bits(x)))); }
double sqrt(double x) { return ba_from_bits(ba_dsqrt(ba_bits(x))); }
double fmod(double x, double y) { return ba_from_bits(ba_dfmod(ba_bits(x), ba_bits(y))); }
double trunc(double x) { return ba_from_bits(ba_dtrunc(ba_bits(x))); }
double ldexp(double x, int n) { return ba_from_bits(ba_dscale(ba_bits(x), n)); }
double scalbn(double x, int n) { return ba_from_bits(ba_dscale(ba_bits(x), n)); }

double floor(double x)
{
    double t = trunc(x);
    if (t > x) t = t - 1.0;
    return t;
}

double ceil(double x)
{
    double t = trunc(x);
    if (t < x) t = t + 1.0;
    return t;
}

double round(double x)
{
    double t = trunc(x);
    if (fabs(x - t) >= 0.5) {
        if (x > 0) t = t + 1.0;
        else t = t - 1.0;
    }
    return t;
}

double rint(double x)
{
    double t;
    if (!(fabs(x) < 4503599627370496.0)) return x;   /* integral, inf, NaN */
    if (x >= 0) t = (x + 4503599627370496.0) - 4503599627370496.0;
    else t = (x - 4503599627370496.0) + 4503599627370496.0;
    if (t == 0) return copysign(0.0, x);
    return t;
}

double nearbyint(double x) { return rint(x); }
long lround(double x) { return (long)round(x); }

double modf(double x, double *ip)
{
    double t = trunc(x);
    *ip = t;
    if (ba_isinf(x)) return copysign(0.0, x);
    if (x - t == 0) return copysign(0.0, x);
    return x - t;
}

double frexp(double x, int *e)
{
    ba_i64 b = ba_bits(x), a = ba_f_abs(b);
    if (a == 0 || a >= ba_f_inf) {
        *e = 0;
        return x;
    }
    ba_f_unpack(a);
    *e = ba_f_e + 53;
    return ba_from_bits(ba_f_pack(b < 0, ba_f_m, -53, 0));
}

int ilogb(double x)
{
    ba_i64 a = ba_f_abs(ba_bits(x));
    if (a == 0) return -2147483647 - 1;
    if (a >= ba_f_inf) return 2147483647;
    ba_f_unpack(a);
    return ba_f_e + 52;
}

double logb(double x)
{
    if (x == 0) return -1.0 / 0.0;
    if (!ba_isfinite(x)) return x * x;
    return (double)ilogb(x);
}

double fmin(double x, double y)
{
    if (ba_isnan(x)) return y;
    if (ba_isnan(y)) return x;
    if (x == y && ba_sgn(x) != ba_sgn(y)) { if (ba_sgn(x)) return x; return y; }
    if (x < y) return x;
    return y;
}

double fmax(double x, double y)
{
    if (ba_isnan(x)) return y;
    if (ba_isnan(y)) return x;
    if (x == y && ba_sgn(x) != ba_sgn(y)) { if (ba_sgn(x)) return y; return x; }
    if (x > y) return x;
    return y;
}

double fdim(double x, double y)
{
    if (ba_isnan(x) || ba_isnan(y)) return x + y;
    if (x > y) return x - y;
    return 0.0;
}

double fma(double x, double y, double z) { return x * y + z; }

double remainder(double x, double y)
{
    double p = fabs(y), a, r;
    if (ba_isnan(x) || ba_isnan(y)) return x + y;
    if (ba_isinf(x) || p == 0) return 0.0 / 0.0;
    if (p < 8.98846567431157953865e307) r = fmod(x, p + p);
    else r = x;
    a = fabs(r);
    if (a + a > p) {
        a = a - p;
        if (a + a >= p) a = a - p;
    }
    if (a == 0) return copysign(0.0, x);
    if (ba_sgn(x)) return -a;
    return a;
}

double hypot(double x, double y)
{
    double t, r;
    x = fabs(x);
    y = fabs(y);
    if (ba_isinf(x) || ba_isinf(y)) return 1.0 / 0.0;
    if (ba_isnan(x) || ba_isnan(y)) return x + y;
    if (x < y) { t = x; x = y; y = t; }
    if (x == 0) return 0.0;
    r = y / x;
    return x * sqrt(1.0 + r * r);
}

/* ---- exp, log ---- */

double ba_ln2_hi = 6.93147180369123816490e-01;
double ba_ln2_lo = 1.90821492927058770002e-10;
double ba_invln2 = 1.44269504088896338700e+00;
double ba_P1 = 1.66666666666666019037e-01;
double ba_P2 = -2.77777777770155933842e-03;
double ba_P3 = 6.61375632143793436117e-05;
double ba_P4 = -1.65339022054652515390e-06;
double ba_P5 = 4.13813679705723846039e-08;

/* exp(x + xl) for finite x within the thresholds of exp; xl is a small
 * correction (pow passes the low part of y*log(x)). */
double ba_exp_core(double x, double xl)
{
    double hi, lo, c, t, y;
    int k, ix = ba_ix(x), sign = ba_sgn(x);
    if (ix > 1071001154) {                 /* |x| > 0.5 ln2 (0x3fd62e42) */
        if (ix < 1072734898) {             /* |x| < 1.5 ln2 (0x3FF0A2B2) */
            if (sign) { hi = x + ba_ln2_hi; lo = -ba_ln2_lo; k = -1; }
            else { hi = x - ba_ln2_hi; lo = ba_ln2_lo; k = 1; }
        } else {
            if (sign) k = (int)(ba_invln2 * x - 0.5);
            else k = (int)(ba_invln2 * x + 0.5);
            t = (double)k;
            hi = x - t * ba_ln2_hi;
            lo = t * ba_ln2_lo;
        }
        lo = lo - xl;
        x = hi - lo;
    } else if (ix < 1043333120) {          /* |x| < 2^-28 (0x3e300000) */
        return 1.0 + (x + xl);
    } else {
        k = 0;
        x = x + xl;
        hi = x;
        lo = 0.0;
    }
    t = x * x;
    c = x - t * (ba_P1 + t * (ba_P2 + t * (ba_P3 + t * (ba_P4 + t * ba_P5))));
    if (k == 0) return 1.0 - ((x * c) / (c - 2.0) - x);
    y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi);
    return scalbn(y, k);
}

double exp(double x)
{
    if (ba_isnan(x)) return x + x;
    if (x > 7.09782712893383973096e+02) return 1.0 / 0.0;
    if (x < -7.45133219101941108420e+02) return 0.0;
    return ba_exp_core(x, 0.0);
}

double ba_Lg1 = 6.666666666666735130e-01;
double ba_Lg2 = 3.999999999940941908e-01;
double ba_Lg3 = 2.857142874366239149e-01;
double ba_Lg4 = 2.222219843214978396e-01;
double ba_Lg5 = 1.818357216161805012e-01;
double ba_Lg6 = 1.531383769920937332e-01;
double ba_Lg7 = 1.479819860511658591e-01;

/* log of x (positive, finite, normal) as an exponent k and hi + lo with
 * hi's low word zero: log(x) = k*ln2 + ba_lg_hi + ba_lg_lo. */
int ba_lg_k;
double ba_lg_hi;
double ba_lg_lo;

void ba_log_parts(double x)
{
    double f, hfsq, s, z, w, t1, t2, R, hi;
    ba_i64 hx = ba_ix(x);
    int k = 0;
    if (hx < 1048576) {                     /* subnormal */
        k = -54;
        x = x * 18014398509481984.0;        /* 2^54 */
        hx = ba_ix(x);
    }
    hx = hx + 1072693248 - 1072064670;      /* 0x3ff00000 - 0x3fe6a09e */
    k = k + (int)(hx >> 20) - 1023;
    hx = (hx & 1048575) + 1072064670;
    x = ba_with_hi(x, hx);
    f = x - 1.0;
    hfsq = 0.5 * f * f;
    s = f / (2.0 + f);
    z = s * s;
    w = z * z;
    t1 = w * (ba_Lg2 + w * (ba_Lg4 + w * ba_Lg6));
    t2 = z * (ba_Lg1 + w * (ba_Lg3 + w * (ba_Lg5 + w * ba_Lg7)));
    R = t2 + t1;
    hi = ba_clear_lo(f - hfsq);
    ba_lg_k = k;
    ba_lg_hi = hi;
    ba_lg_lo = f - hi - hfsq + s * (hfsq + R);
}

double log(double x)
{
    double f, hfsq, s, z, w, t1, t2, R, dk;
    ba_i64 hx;
    int k = 0, i, j;
    if (ba_isnan(x)) return x + x;
    if (x == 0) return -1.0 / 0.0;
    if (x < 0) return 0.0 / 0.0;
    if (ba_isinf(x)) return x;
    hx = ba_ix(x);
    if (hx < 1048576) {
        k = -54;
        x = x * 18014398509481984.0;
        hx = ba_ix(x);
    }
    k = k + (int)(hx >> 20) - 1023;
    hx = hx & 1048575;
    i = (int)((hx + 614244) & 1048576);     /* 0x95f64, 0x100000 */
    x = ba_with_hi(x, hx | (i ^ 1072693248));
    k = k + (i >> 20);
    f = x - 1.0;
    dk = (double)k;
    if ((1048575 & (2 + hx)) < 3) {         /* -2^-20 <= f < 2^-20 */
        if (f == 0) {
            if (k == 0) return 0.0;
            return dk * ba_ln2_hi + dk * ba_ln2_lo;
        }
        R = f * f * (0.5 - 0.33333333333333333 * f);
        if (k == 0) return f - R;
        return dk * ba_ln2_hi - ((R - dk * ba_ln2_lo) - f);
    }
    s = f / (2.0 + f);
    z = s * s;
    i = (int)hx - 398458;                   /* 0x6147a */
    w = z * z;
    j = 440401 - (int)hx;                   /* 0x6b851 */
    t1 = w * (ba_Lg2 + w * (ba_Lg4 + w * ba_Lg6));
    t2 = z * (ba_Lg1 + w * (ba_Lg3 + w * (ba_Lg5 + w * ba_Lg7)));
    i = i | j;
    R = t2 + t1;
    if (i > 0) {
        hfsq = 0.5 * f * f;
        if (k == 0) return f - (hfsq - s * (hfsq + R));
        return dk * ba_ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ba_ln2_lo)) - f);
    }
    if (k == 0) return f - s * (f - R);
    return dk * ba_ln2_hi - ((s * (f - R) - dk * ba_ln2_lo) - f);
}

/* log10 and log2: log(x) = k*ln2 + hi + lo, scaled with extra precision */
double ba_log_scaled(double x, double ivhi, double ivlo, double k_hi, double k_lo)
{
    double hi, lo, val_hi, val_lo, y, w, dk;
    if (ba_isnan(x)) return x + x;
    if (x == 0) return -1.0 / 0.0;
    if (x < 0) return 0.0 / 0.0;
    if (ba_isinf(x)) return x;
    if (x == 1.0) return 0.0;
    ba_log_parts(x);
    hi = ba_lg_hi;
    lo = ba_lg_lo;
    dk = (double)ba_lg_k;
    val_hi = hi * ivhi;
    y = dk * k_hi;
    val_lo = dk * k_lo + (lo + hi) * ivlo + lo * ivhi;
    w = y + val_hi;
    val_lo = val_lo + ((y - w) + val_hi);
    val_hi = w;
    return val_lo + val_hi;
}

double log10(double x)
{
    return ba_log_scaled(x, 4.34294481878168880939e-01, 2.50829467116452752298e-11,
                         3.01029995663611771306e-01, 3.69423907715893078616e-13);
}

double log2(double x)
{
    return ba_log_scaled(x, 1.44269504072144627571e+00, 1.67517131648865118353e-10,
                         1.0, 0.0);
}

double log1p(double x)
{
    double hfsq, f, c, s, z, R, w, t1, t2, dk, u;
    ba_i64 hx = ba_ix(x), hu;
    int sign = ba_sgn(x), k = 1;
    if (ba_isnan(x)) return x + x;
    c = 0.0;
    f = 0.0;
    if (hx < 1071284858 || sign) {          /* x < 0.41422 (0x3fda827a) */
        if (sign && hx >= 1072693248) {     /* x <= -1.0 */
            if (x == -1.0) return -1.0 / 0.0;
            return 0.0 / 0.0;
        }
        if (hx < 1017118720) return x;      /* |x| < 2^-53 (0x3ca00000) */
        if (!sign || hx <= 1070776004) {    /* -0.2929 < x < 0.41422 (0x3fd2bec4) */
            k = 0;
            c = 0.0;
            f = x;
        }
    } else if (hx >= 2146435072) {
        return x;
    }
    if (k) {
        u = 1.0 + x;
        hu = ba_ix(u);
        hu = hu + 1072693248 - 1072064670;
        k = (int)(hu >> 20) - 1023;
        if (k < 54) {
            if (k >= 2) c = 1.0 - (u - x);
            else c = x - (u - 1.0);
            c = c / u;
        } else {
            c = 0.0;
        }
        hu = (hu & 1048575) + 1072064670;
        u = ba_with_hi(u, hu);
        f = u - 1.0;
    }
    hfsq = 0.5 * f * f;
    s = f / (2.0 + f);
    z = s * s;
    w = z * z;
    t1 = w * (ba_Lg2 + w * (ba_Lg4 + w * ba_Lg6));
    t2 = z * (ba_Lg1 + w * (ba_Lg3 + w * (ba_Lg5 + w * ba_Lg7)));
    R = t2 + t1;
    dk = (double)k;
    return s * (hfsq + R) + (dk * ba_ln2_lo + c) - hfsq + f + dk * ba_ln2_hi;
}

double expm1(double x)
{
    double y, hi, lo, c, t, e, hxs, hfx, r1, twopk;
    int hx = ba_ix(x), sign = ba_sgn(x), k;
    c = 0.0;
    lo = 0.0;
    if (hx >= 1078159482) {                 /* |x| >= 56 ln2 (0x4043687A) */
        if (ba_isnan(x)) return x;
        if (sign) return -1.0;
        if (x > 7.09782712893383973096e+02) return 1.0 / 0.0;
    }
    if (hx > 1071001154) {                  /* |x| > 0.5 ln2 */
        if (hx < 1072734898) {              /* |x| < 1.5 ln2 */
            if (!sign) { hi = x - ba_ln2_hi; lo = ba_ln2_lo; k = 1; }
            else { hi = x + ba_ln2_hi; lo = -ba_ln2_lo; k = -1; }
        } else {
            if (sign) k = (int)(ba_invln2 * x - 0.5);
            else k = (int)(ba_invln2 * x + 0.5);
            t = (double)k;
            hi = x - t * ba_ln2_hi;
            lo = t * ba_ln2_lo;
        }
        x = hi - lo;
        c = (hi - x) - lo;
    } else if (hx < 1016070144) {           /* |x| < 2^-54 (0x3c900000) */
        return x;
    } else {
        k = 0;
    }
    hfx = 0.5 * x;
    hxs = x * hfx;
    r1 = 1.0 + hxs * (-3.33333333333331316428e-02 + hxs * (1.58730158725481460165e-03 +
         hxs * (-7.93650757867487942473e-05 + hxs * (4.00821782732936239552e-06 +
         hxs * -2.01099218183624371326e-07))));
    t = 3.0 - r1 * hfx;
    e = hxs * ((r1 - t) / (6.0 - x * t));
    if (k == 0) return x - (x * e - hxs);
    e = x * (e - c) - c;
    e = e - hxs;
    if (k == -1) return 0.5 * (x - e) - 0.5;
    if (k == 1) {
        if (x < -0.25) return -2.0 * (e - (x + 0.5));
        return 1.0 + 2.0 * (x - e);
    }
    twopk = ba_from_bits((ba_i64)(1023 + k) << 52);
    if (k < 0 || k > 56) {
        y = x - e + 1.0;
        if (k == 1024) y = y * 2.0 * 8.98846567431157953865e307;
        else y = y * twopk;
        return y - 1.0;
    }
    if (k < 20) y = (x - e + (1.0 - ba_from_bits((ba_i64)(1023 - k) << 52))) * twopk;
    else y = (x - (e + ba_from_bits((ba_i64)(1023 - k) << 52)) + 1.0) * twopk;
    return y;
}

/* exp(x) / 2 ... for large x: exp(x - kln2) * 2^1021 * 2^1021 */
double ba_expo2(double x)
{
    double scale = ba_from_bits((ba_i64)2044 << 52);
    return exp(x - 1416.0996898839683) * scale * scale;
}

double sinh(double x)
{
    double t, h = 0.5, ax = fabs(x);
    int w = ba_ix(x);
    if (ba_sgn(x)) h = -0.5;
    if (w < 1082535490) {                   /* |x| < log(DBL_MAX) (0x40862e42) */
        t = expm1(ax);
        if (w < 1072693248) {               /* |x| < 1 */
            if (w < 1072693248 - (26 << 20)) return x;
            return h * (2.0 * t - t * t / (t + 1.0));
        }
        return h * (t + t / (t + 1.0));
    }
    return 2.0 * h * ba_expo2(ax);
}

double cosh(double x)
{
    double t;
    int w = ba_ix(x);
    x = fabs(x);
    if (w < 1072049730) {                   /* |x| < log(2) (0x3fe62e42) */
        if (w < 1072693248 - (26 << 20)) return 1.0;
        t = expm1(x);
        return 1.0 + t * t / (2.0 * (1.0 + t));
    }
    if (w < 1082535490) {
        t = exp(x);
        return 0.5 * (t + 1.0 / t);
    }
    return ba_expo2(x);
}

double tanh(double x)
{
    double t;
    int w = ba_ix(x), sign = ba_sgn(x);
    if (ba_isnan(x)) return x;
    x = fabs(x);
    if (w > 1071748074) {                   /* |x| > log(3)/2 (0x3fe193ea) */
        if (w > 1077149696) {               /* |x| > 20 (0x40340000) */
            t = 1.0;
        } else {
            t = expm1(2.0 * x);
            t = 1.0 - 2.0 / (t + 2.0);
        }
    } else if (w > 1070618798) {            /* |x| > log(5/3)/2 (0x3fd058ae) */
        t = expm1(2.0 * x);
        t = t / (t + 2.0);
    } else if (w >= 1048576) {
        t = expm1(-2.0 * x);
        t = -t / (t + 2.0);
    } else {
        t = x;
    }
    if (sign) return -t;
    return t;
}

double asinh(double x)
{
    int e = (ba_ix(x) >> 20) & 2047, s = ba_sgn(x);
    x = fabs(x);
    if (e >= 1023 + 26) x = log(x) + 0.693147180559945309417232121458176568;
    else if (e >= 1023 + 1) x = log(2.0 * x + 1.0 / (sqrt(x * x + 1.0) + x));
    else if (e >= 1023 - 26) x = log1p(x + x * x / (sqrt(x * x + 1.0) + 1.0));
    if (s) return -x;
    return x;
}

double acosh(double x)
{
    int e = (ba_ix(x) >> 20) & 2047;
    if (ba_sgn(x) || x < 1.0) {
        if (ba_isnan(x)) return x + x;
        return 0.0 / 0.0;
    }
    if (e < 1023 + 1) return log1p(x - 1.0 + sqrt((x - 1.0) * (x - 1.0) + 2.0 * (x - 1.0)));
    if (e < 1023 + 26) return log(2.0 * x - 1.0 / (x + sqrt(x * x - 1.0)));
    return log(x) + 0.693147180559945309417232121458176568;
}

double atanh(double x)
{
    int e = (ba_ix(x) >> 20) & 2047, s = ba_sgn(x);
    double y = fabs(x);
    if (e < 1023 - 1) {
        if (e >= 1023 - 32) y = 0.5 * log1p(2.0 * y + 2.0 * y * y / (1.0 - y));
    } else {
        y = 0.5 * log1p(2.0 * (y / (1.0 - y)));
    }
    if (s) return -y;
    return y;
}

/* ---- pow ---- */

/* Exact products and sums (Dekker, Knuth) on doubles. */
double ba_dd_hi;
double ba_dd_lo;

void ba_two_prod(double a, double b)
{
    double ah, al, bh, bl, p, t;
    t = a * 134217729.0;                    /* 2^27 + 1 */
    ah = t - (t - a);
    al = a - ah;
    t = b * 134217729.0;
    bh = t - (t - b);
    bl = b - bh;
    p = a * b;
    ba_dd_hi = p;
    ba_dd_lo = ((ah * bh - p) + ah * bl + al * bh) + al * bl;
}

void ba_two_sum(double a, double b)
{
    double s = a + b, bb = s - a;
    ba_dd_hi = s;
    ba_dd_lo = (a - (s - bb)) + (b - bb);
}

/* log(ax) for a positive finite ax in double-double (ba_dd_hi + ba_dd_lo),
 * accurate to about 2^-64: log(m) = 2 atanh(s), s = (m-1)/(m+1). */
void ba_log_dd(double ax)
{
    double m, f, dh, dl, sh, sl, s2h, s2l, s3h, s3l, th, tl, s2, p, h, l, kh;
    ba_i64 hx = ba_ix(ax);
    int k = 0;
    if (hx < 1048576) {
        k = -54;
        ax = ax * 18014398509481984.0;
        hx = ba_ix(ax);
    }
    hx = hx + 1072693248 - 1072064670;
    k = k + (int)(hx >> 20) - 1023;
    hx = (hx & 1048575) + 1072064670;
    m = ba_with_hi(ax, hx);                 /* in [sqrt(2)/2, sqrt(2)) */
    f = m - 1.0;
    dh = 2.0 + f;
    dl = f - (dh - 2.0);
    sh = f / dh;
    ba_two_prod(sh, dh);
    sl = (((f - ba_dd_hi) - ba_dd_lo) - sh * dl) / dh;
    ba_two_prod(sh, sh);
    s2h = ba_dd_hi;
    s2l = ba_dd_lo + 2.0 * sh * sl;
    ba_two_prod(s2h, sh);
    s3h = ba_dd_hi;
    s3l = ba_dd_lo + s2h * sl + s2l * sh;
    th = s3h / 3.0;
    ba_two_prod(th, 3.0);
    tl = (((s3h - ba_dd_hi) - ba_dd_lo) + s3l) / 3.0;
    s2 = s2h;
    p = s2 * s2 * sh * (0.2 + s2 * (1.0 / 7.0 + s2 * (1.0 / 9.0 + s2 * (1.0 / 11.0 + s2 * (1.0 / 13.0 +
        s2 * (1.0 / 15.0 + s2 * (1.0 / 17.0 + s2 * (1.0 / 19.0 + s2 * (1.0 / 21.0 + s2 * (1.0 / 23.0 +
        s2 * (1.0 / 25.0 + s2 * (1.0 / 27.0))))))))))));
    ba_two_sum(sh, th);
    h = ba_dd_hi;
    l = ba_dd_lo + sl + tl + p;
    ba_two_sum(h, l);
    h = 2.0 * ba_dd_hi;
    l = 2.0 * ba_dd_lo;
    kh = (double)k * ba_ln2_hi;             /* exact */
    if (fabs(kh) > fabs(h)) ba_two_sum(kh, h);
    else ba_two_sum(h, kh);
    h = ba_dd_hi;
    l = ba_dd_lo + l + (double)k * ba_ln2_lo;
    ba_two_sum(h, l);
}

/* |x|^n for a positive integer n, in double-double, rounded once */
double ba_pow_int(double x, int n)
{
    double rh = 1.0, rl = 0.0, bh = x, bl = 0.0, h, l;
    while (n > 0) {
        if (n & 1) {
            ba_two_prod(rh, bh);
            h = ba_dd_hi;
            l = ba_dd_lo + (rh * bl + rl * bh);
            ba_two_sum(h, l);
            rh = ba_dd_hi;
            rl = ba_dd_lo;
        }
        n = n >> 1;
        if (n > 0) {
            ba_two_prod(bh, bh);
            h = ba_dd_hi;
            l = ba_dd_lo + 2.0 * bh * bl;
            ba_two_sum(h, l);
            bh = ba_dd_hi;
            bl = ba_dd_lo;
        }
    }
    return rh + rl;
}

/* Whether y is an integer: 0 no, 1 odd, 2 even. */
int ba_int_kind(double y)
{
    double t;
    if (!ba_isfinite(y)) return 0;
    if (trunc(y) != y) return 0;
    if (fabs(y) >= 9007199254740992.0) return 2;
    t = y * 0.5;
    if (trunc(t) == t) return 2;
    return 1;
}

double pow(double x, double y)
{
    double ax, lh, ll, zh, zl, r, h, l;
    int yk, neg = 0, n;
    if (y == 0) return 1.0;
    if (x == 1.0) return 1.0;
    if (ba_isnan(x) || ba_isnan(y)) return x + y;
    yk = ba_int_kind(y);
    ax = fabs(x);
    if (ba_isinf(y)) {
        if (ax == 1.0) return 1.0;
        if ((ax > 1.0) == (y > 0)) return 1.0 / 0.0;
        return 0.0;
    }
    if (x == 0) {
        if (y < 0) {
            if (yk == 1) return copysign(1.0 / 0.0, x);
            return 1.0 / 0.0;
        }
        if (yk == 1) return x;
        return 0.0;
    }
    if (ba_isinf(x)) {
        if (ba_sgn(x) && yk == 1) {
            if (y < 0) return -0.0;
            return x;
        }
        if (y < 0) return 0.0;
        return 1.0 / 0.0;
    }
    if (y == 0.5 && x > 0) return sqrt(x);      /* correctly rounded */
    if (x < 0) {
        if (yk == 0) return 0.0 / 0.0;
        if (yk == 1) neg = 1;
    }
    if (fabs(y) > 1e300) {                  /* |y log x| is huge */
        if ((ax > 1.0) == (y > 0)) r = 1.0 / 0.0;
        else r = 0.0;
    } else if (yk != 0 && fabs(y) <= 64.0) {
        n = (int)fabs(y);
        r = ba_pow_int(ax, n);
        if (y < 0) r = 1.0 / r;   /* two roundings; fine for small n */
    } else {
        /* exp(y * log(ax)) with log(ax) and the product in double-double */
        ba_log_dd(ax);
        lh = ba_dd_hi;
        ll = ba_dd_lo;
        ba_two_prod(y, lh);
        zh = ba_dd_hi;
        zl = ba_dd_lo + y * ll;
        ba_two_sum(zh, zl);
        zh = ba_dd_hi;
        zl = ba_dd_lo;
        if (zh > 7.09782712893383973096e+02) r = 1.0 / 0.0;
        else if (zh < -7.45133219101941108420e+02) r = 0.0;
        else r = ba_exp_core(zh, zl);
    }
    if (neg) return -r;
    return r;
}

double exp2(double x) { return pow(2.0, x); }

double cbrt(double x)
{
    double r, s, t, w;
    ba_i64 hx = ba_ix(x), b;
    if (hx >= 2146435072) return x + x;
    if (hx < 1048576) {
        t = x * 18014398509481984.0;        /* 2^54 */
        hx = ba_ix(t);
        if (hx == 0) return x;
        hx = hx / 3 + 696219795;
    } else {
        hx = hx / 3 + 715094163;
    }
    t = ba_from_bits((ba_bits(x) & ba_f_sign) | (hx << 32));
    r = (t * t) * (t / x);
    t = t * ((1.87595182427177009643 + r * (-1.88497979543377169875 + r * 1.621429720105354466140)) +
             ((r * r) * r) * (-0.758397934778766047437 + r * 0.145996192886612446982));
    b = (ba_bits(t) + 2147483648) & ~(((ba_i64)1 << 30) - 1);
    t = ba_from_bits(b);
    s = t * t;
    r = x / s;
    w = t + t;
    r = (r - t) / (w + r);
    return t + t * r;
}

/* ---- trigonometry ---- */

double ba_kernel_sin(double x, double y, int iy)
{
    double z = x * x, w, r, v;
    w = z * z;
    r = 8.33333333332248946124e-03 + z * (-1.98412698298579493134e-04 + z * 2.75573137070700676789e-06) +
        z * w * (-2.50507602534068634195e-08 + z * 1.58969099521155010221e-10);
    v = z * x;
    if (iy == 0) return x + v * (-1.66666666666666324348e-01 + z * r);
    return x - ((z * (0.5 * y - v * r) - y) - v * -1.66666666666666324348e-01);
}

double ba_kernel_cos(double x, double y)
{
    double z = x * x, w, r, hz;
    w = z * z;
    r = z * (4.16666666666666019037e-02 + z * (-1.38888888888741095749e-03 + z * 2.48015872894767294178e-05)) +
        w * w * (-2.75573143513906633035e-07 + z * (2.08757232129817482790e-09 + z * -1.13596475577881948265e-11));
    hz = 0.5 * z;
    w = 1.0 - hz;
    return w + (((1.0 - w) - hz) + (z * r - x * y));
}

double ba_T[13] = {
    3.33333333333334091986e-01, 1.33333333333201242699e-01, 5.39682539762260521377e-02,
    2.18694882948595424599e-02, 8.86323982359930005737e-03, 3.59207910759131235356e-03,
    1.45620945432529025516e-03, 5.88041240820264096874e-04, 2.46463134818469906812e-04,
    7.81794442939557092300e-05, 7.14072491382608190305e-05, -1.85586374855275456654e-05,
    2.59073051863633712884e-05 };

double ba_kernel_tan(double x, double y, int odd)
{
    double z, r, v, w, s, a, w0, a0;
    int big = ba_ix(x) >= 1072010280, sign = ba_sgn(x);   /* |x| >= 0.6744 (0x3FE59428) */
    if (big) {
        if (sign) { x = -x; y = -y; }
        x = (7.85398163397448278999e-01 - x) + (3.06161699786838301793e-17 - y);
        y = 0.0;
    }
    z = x * x;
    w = z * z;
    r = ba_T[1] + w * (ba_T[3] + w * (ba_T[5] + w * (ba_T[7] + w * (ba_T[9] + w * ba_T[11]))));
    v = z * (ba_T[2] + w * (ba_T[4] + w * (ba_T[6] + w * (ba_T[8] + w * (ba_T[10] + w * ba_T[12])))));
    s = z * x;
    r = y + z * (s * (r + v) + y) + s * ba_T[0];
    w = x + r;
    if (big) {
        s = (double)(1 - 2 * odd);
        v = s - 2.0 * (x + (r - w * w / (w + s)));
        if (sign) return -v;
        return v;
    }
    if (!odd) return w;
    w0 = ba_clear_lo(w);
    v = r - (w0 - x);
    a = -1.0 / w;
    a0 = ba_clear_lo(a);
    return a0 + a * (1.0 + a0 * w0 + a0 * v);
}

/* Reduce x modulo pi/2: x = n*pi/2 + ba_rp_y0 + ba_rp_y1, returns n. */
double ba_rp_y0;
double ba_rp_y1;

/* 2/pi in 24-bit pieces (fdlibm's ipio2) */
int ba_ipio2[66] = {
    10680707, 7228996, 1387004, 2578385, 16069853, 12639074, 9804092, 4427841,
    16666979, 11263675, 12935607, 2387514, 4345298, 14681673, 3074569, 13734428,
    16653803, 1880361, 10960616, 8533493, 3062596, 8710556, 7349940, 6258241,
    3772886, 3769171, 3798172, 8675211, 12450088, 3874808, 9961438, 366607,
    15675153, 9132554, 7151469, 3571407, 2607881, 12013382, 4155038, 6285869,
    7677882, 13102053, 15825725, 473591, 9065106, 15363067, 6271263, 9264392,
    5636912, 4652155, 7056368, 13614112, 10155062, 1944035, 9527646, 15080200,
    6658437, 6231200, 6832269, 16767104, 5075751, 3212806, 1398474, 7579849,
    6349435, 12618859 };

/* pi/2 * 2^125, 16-bit limbs, least significant first */
int ba_pio2_limbs[8] = { 1844, 57399, 39074, 12593, 12429, 34906, 63144, 12867 };

int ba_bn_c[BA_BN];

int ba_rem_pio2_large(double x)
{
    int e, i0, W = 192, i, bit, k, n, S, plen, len, neg = 0, glen, g, rlen, j;
    ba_i64 m, q;
    ba_f_unpack(ba_f_abs(ba_bits(x)));
    m = ba_f_m;
    e = ba_f_e;
    i0 = e - 1;
    if (i0 < 1) i0 = 1;
    /* B: bits i0 .. i0+W-1 of 2/pi into ba_bn_a */
    i = 0;
    while (i < W / 16) { ba_bn_a[i] = 0; i = i + 1; }
    i = 0;
    while (i < W) {
        k = i0 + i;                          /* bit k of 2/pi (k >= 1) */
        bit = (ba_ipio2[(k - 1) / 24] >> (23 - (k - 1) % 24)) & 1;
        if (bit) {
            j = W - 1 - i;
            ba_bn_a[j / 16] = ba_bn_a[j / 16] | (1 << (j % 16));
        }
        i = i + 1;
    }
    /* P = m * B */
    plen = W / 16;
    i = 0;
    while (i < 4) {
        ba_bn_b[i] = (int)((m >> (16 * i)) & 65535);
        i = i + 1;
    }
    i = 0;
    while (i < plen + 5) { ba_bn_c[i] = 0; i = i + 1; }
    i = 0;
    while (i < 4) {
        k = 0;
        q = 0;
        while (k < plen) {
            q = ba_bn_c[i + k] + (ba_i64)ba_bn_b[i] * ba_bn_a[k] + q;
            ba_bn_c[i + k] = (int)(q & 65535);
            q = q >> 16;
            k = k + 1;
        }
        while (q != 0) {
            q = ba_bn_c[i + k] + q;
            ba_bn_c[i + k] = (int)(q & 65535);
            q = q >> 16;
            k = k + 1;
        }
        i = i + 1;
    }
    len = plen + 5;
    /* value = P / 2^S */
    S = i0 + W - 1 - e;
    n = ((ba_bn_c[S / 16] >> (S % 16)) | (ba_bn_c[S / 16 + 1] << (16 - S % 16))) & 3;
    /* fraction: the low S bits */
    len = S / 16 + 1;
    ba_bn_c[S / 16] = ba_bn_c[S / 16] & ((1 << (S % 16)) - 1);
    if ((ba_bn_c[(S - 1) / 16] >> ((S - 1) % 16)) & 1) {   /* >= 1/2: take f - 1 */
        n = n + 1;
        neg = 1;
        /* 2^S - frac */
        i = 0;
        q = 0;
        while (i < len) {
            q = -ba_bn_c[i] - q;
            if (q < 0) { ba_bn_c[i] = (int)(q + 65536); q = 1; } else { ba_bn_c[i] = (int)q; q = 0; }
            i = i + 1;
        }
        ba_bn_c[S / 16] = ba_bn_c[S / 16] & ((1 << (S % 16)) - 1);
    }
    /* r = frac / 2^S * pi/2: multiply by the 128-bit pi/2 */
    glen = len;
    while (glen > 0 && ba_bn_c[glen - 1] == 0) glen = glen - 1;
    i = 0;
    while (i < glen + 9) { ba_bn_q[i] = 0; i = i + 1; }
    i = 0;
    while (i < glen) {
        k = 0;
        q = 0;
        while (k < 8) {
            q = ba_bn_q[i + k] + (ba_i64)ba_bn_c[i] * ba_pio2_limbs[k] + q;
            ba_bn_q[i + k] = (int)(q & 65535);
            q = q >> 16;
            k = k + 1;
        }
        while (q != 0) {
            q = ba_bn_q[i + k] + q;
            ba_bn_q[i + k] = (int)(q & 65535);
            q = q >> 16;
            k = k + 1;
        }
        i = i + 1;
    }
    rlen = glen + 9;
    g = -S - 125;
    /* y0 = round(R * 2^g); y1 = the rest */
    i = 0;
    while (i < rlen) { ba_bn_b[i] = ba_bn_q[i]; i = i + 1; }
    ba_rp_y0 = ba_from_bits(ba_bn_round(ba_bn_b, rlen, g, 0, neg));
    /* R - y0 / 2^g, with y0 = M * 2^E: subtract M << (E - g) */
    ba_f_unpack(ba_f_abs(ba_bits(ba_rp_y0)));
    i = 0;
    while (i < rlen) { ba_bn_b[i] = 0; i = i + 1; }
    k = 0;
    m = ba_f_m;
    while (m != 0) { ba_bn_b[k] = (int)(m & 65535); m = m >> 16; k = k + 1; }
    k = ba_bn_shl(ba_bn_b, k, ba_f_e - g);
    if (ba_bn_ge(ba_bn_q, rlen, ba_bn_b, k)) {
        ba_bn_sub(ba_bn_q, rlen, ba_bn_b, k);
        ba_rp_y1 = ba_from_bits(ba_bn_round(ba_bn_q, rlen, g, 0, neg));
    } else {
        ba_bn_sub(ba_bn_b, rlen, ba_bn_q, rlen);
        ba_rp_y1 = ba_from_bits(ba_bn_round(ba_bn_b, rlen, g, 0, !neg));
    }
    if (ba_sgn(x)) {
        ba_rp_y0 = -ba_rp_y0;
        ba_rp_y1 = -ba_rp_y1;
        return -n;
    }
    return n;
}

int ba_rem_pio2(double x)
{
    double fn, r, w, t;
    int n, ix = ba_ix(x), ex, ey;
    if (ix >= 1094263291) return ba_rem_pio2_large(x);   /* |x| >= 2^20 pi/2 (0x413921fb) */
    fn = x * 6.36619772367581382433e-01 + 6755399441055744.0 - 6755399441055744.0;
    n = (int)fn;
    r = x - fn * 1.57079632673412561417e+00;
    w = fn * 6.07710050650619224932e-11;
    ba_rp_y0 = r - w;
    ey = (ba_ix(ba_rp_y0) >> 20) & 2047;
    ex = ix >> 20;
    if (ex - ey > 16) {
        t = r;
        w = fn * 6.07710050630396597660e-11;
        r = t - w;
        w = fn * 2.02226624879595063154e-21 - ((t - r) - w);
        ba_rp_y0 = r - w;
        ey = (ba_ix(ba_rp_y0) >> 20) & 2047;
        if (ex - ey > 49) {
            t = r;
            w = fn * 2.02226624871116645580e-21;
            r = t - w;
            w = fn * 8.47842766036889956997e-32 - ((t - r) - w);
            ba_rp_y0 = r - w;
        }
    }
    ba_rp_y1 = (r - ba_rp_y0) - w;
    return n;
}

double sin(double x)
{
    int ix = ba_ix(x), n;
    if (ix <= 1072243195) {                 /* |x| <= pi/4 (0x3fe921fb) */
        if (ix < 1045430272) return x;      /* |x| < 2^-26 (0x3e500000) */
        return ba_kernel_sin(x, 0.0, 0);
    }
    if (ix >= 2146435072) return x - x;
    n = ba_rem_pio2(x) & 3;
    if (n == 0) return ba_kernel_sin(ba_rp_y0, ba_rp_y1, 1);
    if (n == 1) return ba_kernel_cos(ba_rp_y0, ba_rp_y1);
    if (n == 2) return -ba_kernel_sin(ba_rp_y0, ba_rp_y1, 1);
    return -ba_kernel_cos(ba_rp_y0, ba_rp_y1);
}

double cos(double x)
{
    int ix = ba_ix(x), n;
    if (ix <= 1072243195) {
        if (ix < 1044816030) return 1.0;    /* |x| < 2^-27 * sqrt(2) (0x3e46a09e) */
        return ba_kernel_cos(x, 0.0);
    }
    if (ix >= 2146435072) return x - x;
    n = ba_rem_pio2(x) & 3;
    if (n == 0) return ba_kernel_cos(ba_rp_y0, ba_rp_y1);
    if (n == 1) return -ba_kernel_sin(ba_rp_y0, ba_rp_y1, 1);
    if (n == 2) return -ba_kernel_cos(ba_rp_y0, ba_rp_y1);
    return ba_kernel_sin(ba_rp_y0, ba_rp_y1, 1);
}

double tan(double x)
{
    int ix = ba_ix(x), n;
    if (ix <= 1072243195) {
        if (ix < 1044381696) return x;      /* |x| < 2^-27 (0x3e400000) */
        return ba_kernel_tan(x, 0.0, 0);
    }
    if (ix >= 2146435072) return x - x;
    n = ba_rem_pio2(x);
    return ba_kernel_tan(ba_rp_y0, ba_rp_y1, n & 1);
}

double ba_atanhi[4] = { 4.63647609000806093515e-01, 7.85398163397448278999e-01,
                        9.82793723247329054082e-01, 1.57079632679489655800e+00 };
double ba_atanlo[4] = { 2.26987774529616870924e-17, 3.06161699786838301793e-17,
                        1.39033110312309984516e-17, 6.12323399573676603587e-17 };
double ba_aT[11] = {
    3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01,
    -1.11111104054623557880e-01, 9.09088713343650656196e-02, -7.69187620504482999495e-02,
    6.66107313738753120669e-02, -5.83357013379057348645e-02, 4.97687799461593236017e-02,
    -3.65315727442169155270e-02, 1.62858201153657823623e-02 };

double atan(double x)
{
    double w, s1, s2, z;
    int ix = ba_ix(x), sign = ba_sgn(x), id;
    if (ix >= 1141899264) {                 /* |x| >= 2^66 (0x44100000) */
        if (ba_isnan(x)) return x;
        z = ba_atanhi[3] + ba_atanlo[3];
        if (sign) return -z;
        return z;
    }
    if (ix < 1071382528) {                  /* |x| < 0.4375 (0x3fdc0000) */
        if (ix < 1044381696) return x;      /* |x| < 2^-27 */
        id = -1;
    } else {
        x = fabs(x);
        if (ix < 1072889856) {              /* |x| < 1.1875 (0x3ff30000) */
            if (ix < 1072037888) {          /* 7/16 <= |x| < 11/16 (0x3fe60000) */
                id = 0;
                x = (2.0 * x - 1.0) / (2.0 + x);
            } else {
                id = 1;
                x = (x - 1.0) / (x + 1.0);
            }
        } else {
            if (ix < 1073971200) {          /* |x| < 2.4375 (0x40038000) */
                id = 2;
                x = (x - 1.5) / (1.0 + 1.5 * x);
            } else {
                id = 3;
                x = -1.0 / x;
            }
        }
    }
    z = x * x;
    w = z * z;
    s1 = z * (ba_aT[0] + w * (ba_aT[2] + w * (ba_aT[4] + w * (ba_aT[6] + w * (ba_aT[8] + w * ba_aT[10])))));
    s2 = w * (ba_aT[1] + w * (ba_aT[3] + w * (ba_aT[5] + w * (ba_aT[7] + w * ba_aT[9]))));
    if (id < 0) return x - x * (s1 + s2);
    z = ba_atanhi[id] - (x * (s1 + s2) - ba_atanlo[id] - x);
    if (sign) return -z;
    return z;
}

double atan2(double y, double x)
{
    double z, pi = 3.1415926535897931160E+00, pi_lo = 1.2246467991473531772E-16;
    int m, ix, iy;
    if (ba_isnan(x) || ba_isnan(y)) return x + y;
    if (x == 1.0) return atan(y);
    m = ba_sgn(y) | (2 * ba_sgn(x));
    ix = ba_ix(x);
    iy = ba_ix(y);
    if (y == 0) {
        if (m == 0 || m == 1) return y;
        if (m == 2) return pi;
        return -pi;
    }
    if (x == 0) {
        if (m & 1) return -pi / 2.0;
        return pi / 2.0;
    }
    if (ba_isinf(x)) {
        if (ba_isinf(y)) {
            if (m == 0) return pi / 4.0;
            if (m == 1) return -pi / 4.0;
            if (m == 2) return 3.0 * pi / 4.0;
            return -3.0 * pi / 4.0;
        }
        if (m == 0) return 0.0;
        if (m == 1) return -0.0;
        if (m == 2) return pi;
        return -pi;
    }
    if (ix + (64 << 20) < iy || ba_isinf(y)) {
        if (m & 1) return -pi / 2.0;
        return pi / 2.0;
    }
    if ((m & 2) && iy + (64 << 20) < ix) z = 0.0;
    else z = atan(fabs(y / x));
    if (m == 0) return z;
    if (m == 1) return -z;
    if (m == 2) return pi - (z - pi_lo);
    return (z - pi_lo) - pi;
}

double ba_asin_R(double z)
{
    double p, q;
    p = z * (1.66666666666666657415e-01 + z * (-3.25565818622400915405e-01 + z * (2.01212532134862925881e-01 +
        z * (-4.00555345006794114027e-02 + z * (7.91534994289814532176e-04 + z * 3.47933107596021167570e-05)))));
    q = 1.0 + z * (-2.40339491173441421878e+00 + z * (2.02094576023350569471e+00 +
        z * (-6.88283971605453293030e-01 + z * 7.70381505559019352791e-02)));
    return p / q;
}

double asin(double x)
{
    double z, r, s, f, c, pio2_hi = 1.57079632679489655800e+00, pio2_lo = 6.12323399573676603587e-17;
    int ix = ba_ix(x), sign = ba_sgn(x);
    if (ix >= 1072693248) {                 /* |x| >= 1 */
        if (fabs(x) == 1.0) return x * pio2_hi;
        return 0.0 / 0.0;
    }
    if (ix < 1071644672) {                  /* |x| < 0.5 */
        if (ix < 1045430272 && ix >= 1048576) return x;
        return x + x * ba_asin_R(x * x);
    }
    z = (1.0 - fabs(x)) * 0.5;
    s = sqrt(z);
    r = ba_asin_R(z);
    if (ix >= 1072640819) {                 /* |x| > 0.975 (0x3fef3333) */
        x = pio2_hi - (2.0 * (s + s * r) - pio2_lo);
    } else {
        f = ba_clear_lo(s);
        c = (z - f * f) / (s + f);
        x = 0.5 * pio2_hi - (2.0 * s * r - (pio2_lo - 2.0 * c) - (0.5 * pio2_hi - 2.0 * f));
    }
    if (sign) return -x;
    return x;
}

double acos(double x)
{
    double z, w, s, c, df, pio2_hi = 1.57079632679489655800e+00, pio2_lo = 6.12323399573676603587e-17;
    int ix = ba_ix(x), sign = ba_sgn(x);
    if (ix >= 1072693248) {
        if (fabs(x) == 1.0) {
            if (sign) return 2.0 * pio2_hi;
            return 0.0;
        }
        return 0.0 / 0.0;
    }
    if (ix < 1071644672) {
        if (ix <= 1012924416) return pio2_hi;   /* |x| < 2^-57 (0x3c600000) */
        return pio2_hi - (x - (pio2_lo - x * ba_asin_R(x * x)));
    }
    if (sign) {
        z = (1.0 + x) * 0.5;
        s = sqrt(z);
        w = ba_asin_R(z) * s - pio2_lo;
        return 2.0 * (pio2_hi - (s + w));
    }
    z = (1.0 - x) * 0.5;
    s = sqrt(z);
    df = ba_clear_lo(s);
    c = (z - df * df) / (s + df);
    w = ba_asin_R(z) * s + c;
    return 2.0 * (df + w);
}
