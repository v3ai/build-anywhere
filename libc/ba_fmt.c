/*
 * ba_fmt.c: the printf and scanf families, strtod and atof.
 *
 * Part of build-anywhere. Floating-point conversions are exact: printf
 * expands the double to its exact decimal value and rounds that (half to
 * even, like glibc), and strtod rounds the exact decimal input correctly
 * using big-integer arithmetic. So "%.17g" round-trips, and output matches
 * glibc byte for byte for every conversion C89 defines.
 *
 * Written for a libc that already has FILE, fputc/fwrite, getc/ungetc and
 * malloc (such as GNU Mes libc), to replace its formatting code.
 */
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ba_libc.h"

double frexp(double x, int *ep);
double ldexp(double x, int n);
/* IEEE 754 binary64 access. Everything here works on bit patterns, not
   floating-point arithmetic, so a compiler without floating-point support
   (the first TinyCC of the bootstrap) still compiles it correctly. */
#define SIGN_BIT 0x8000000000000000ULL
#define EXP_MASK 0x7FF0000000000000ULL
#define FRAC_MASK 0x000FFFFFFFFFFFFFULL

static unsigned long long dbits(double v)
{
    unsigned long long u;
    memcpy(&u, &v, sizeof u);
    return u;
}

static double from_bits(unsigned long long u)
{
    double v;
    memcpy(&v, &u, sizeof v);
    return v;
}

double __ba_inf(void) { return from_bits(EXP_MASK); }
double __ba_nan(void) { return from_bits(EXP_MASK | 0x0008000000000000ULL); }

/* ===================================================================== */
/* Exact decimal expansion                                               */
/* ===================================================================== */

/* Unsigned big integers in base 10^4, least significant limb first. */
#define DEC_LIMBS 300

struct dec {
    int n;
    unsigned long d[DEC_LIMBS];
};

static void dec_mul(struct dec *b, unsigned long m)     /* m <= 65536 */
{
    unsigned long carry = 0, t;
    int i;
    for (i = 0; i < b->n; i++) {
        t = b->d[i] * m + carry;
        b->d[i] = t % 10000UL;
        carry = t / 10000UL;
    }
    while (carry != 0 && b->n < DEC_LIMBS) {
        b->d[b->n++] = carry % 10000UL;
        carry /= 10000UL;
    }
}

int __ba_exact_digits(double v, char *digs, int *dp)
{
    struct dec b;
    unsigned long long u = dbits(v), m;
    int e2, i, j, n, top;
    char limb[4];

    /* v = m * 2^e2 with m an integer */
    m = u & FRAC_MASK;
    e2 = (int)((u & EXP_MASK) >> 52);
    if (e2 == 0) {
        e2 = -1074;             /* subnormal */
    } else {
        m |= 1ULL << 52;
        e2 -= 1075;
    }
    while (e2 < 0 && m != 0 && (m & 1ULL) == 0) {
        m >>= 1;
        e2++;
    }
    b.n = 0;
    while (m != 0) {
        b.d[b.n++] = (unsigned long)(m % 10000ULL);
        m /= 10000ULL;
    }
    if (e2 >= 0) {
        for (i = e2; i >= 16; i -= 16)
            dec_mul(&b, 65536UL);
        if (i > 0)
            dec_mul(&b, 1UL << i);
    } else {
        for (i = -e2; i >= 6; i -= 6)
            dec_mul(&b, 15625UL);           /* 5^6 */
        for (; i > 0; i--)
            dec_mul(&b, 5UL);
    }

    /* Print the limbs, most significant first, without leading zeros. */
    n = 0;
    for (i = b.n - 1; i >= 0; i--) {
        limb[0] = (char)('0' + (int)(b.d[i] / 1000UL));
        limb[1] = (char)('0' + (int)(b.d[i] / 100UL % 10UL));
        limb[2] = (char)('0' + (int)(b.d[i] / 10UL % 10UL));
        limb[3] = (char)('0' + (int)(b.d[i] % 10UL));
        for (j = 0; j < 4; j++) {
            if (n == 0 && limb[j] == '0')
                continue;
            if (n < BA_MAX_DIGITS)
                digs[n] = limb[j];
            n++;
        }
    }
    top = n;                    /* number of integer digits of b */
    if (n > BA_MAX_DIGITS)
        n = BA_MAX_DIGITS;      /* cannot happen for IEEE doubles */
    while (n > 1 && digs[n - 1] == '0')
        n--;
    *dp = top + (e2 < 0 ? e2 : 0);
    return n;
}

/* Round digs[0..*n) to its first k digits, half to even. */
static void round_digits(char *digs, int *n, int *dp, int k)
{
    int up, i;

    if (k >= *n)
        return;
    if (k < 0) {
        *n = 0;
        return;
    }
    if (digs[k] > '5') {
        up = 1;
    } else if (digs[k] < '5') {
        up = 0;
    } else {
        up = 0;
        for (i = k + 1; i < *n; i++)
            if (digs[i] != '0')
                up = 1;
        if (!up)        /* exact tie: round to even */
            up = k > 0 && ((digs[k - 1] - '0') & 1);
    }
    *n = k;
    if (up) {
        for (i = k - 1; i >= 0; i--) {
            if (digs[i] != '9') {
                digs[i]++;
                break;
            }
            digs[i] = '0';
        }
        if (i < 0) {
            digs[0] = '1';
            *n = 1;
            (*dp)++;
        }
    }
    while (*n > 0 && digs[*n - 1] == '0')
        (*n)--;
}

static int sign_bit(double v)
{
    return (dbits(v) & SIGN_BIT) != 0;
}

/* ===================================================================== */
/* printf                                                                */
/* ===================================================================== */

struct sink {
    FILE *f;
    char *s;
    size_t cap;
    size_t pos;
    int err;
    int blen;
    char buf[256];
};

static void sink_flush(struct sink *k)
{
    if (k->f != NULL && k->blen > 0) {
        if (fwrite(k->buf, 1, (size_t)k->blen, k->f) != (size_t)k->blen)
            k->err = 1;
        k->blen = 0;
    }
}

static void put(struct sink *k, int c)
{
    if (k->f != NULL) {
        k->buf[k->blen++] = (char)c;
        if (k->blen == (int)sizeof k->buf)
            sink_flush(k);
    } else if (k->cap > 0 && k->pos < k->cap - 1) {
        k->s[k->pos] = (char)c;
    }
    k->pos++;
}

static void put_n(struct sink *k, int c, long n)
{
    while (n-- > 0)
        put(k, c);
}

static void put_s(struct sink *k, const char *s, size_t n)
{
    while (n-- > 0)
        put(k, (unsigned char)*s++);
}

#define F_LEFT  1
#define F_PLUS  2
#define F_SPACE 4
#define F_ALT   8
#define F_ZERO  16

/* Emit prefix (sign, 0x) + zeros + body, padded to width. */
static void emit(struct sink *k, int flags, long width, const char *pre,
                 long zeros, const char *body, size_t blen)
{
    long len = (long)strlen(pre) + zeros + (long)blen;
    long pad = width > len ? width - len : 0;

    if (!(flags & F_LEFT) && !(flags & F_ZERO))
        put_n(k, ' ', pad);
    put_s(k, pre, strlen(pre));
    if (!(flags & F_LEFT) && (flags & F_ZERO))
        put_n(k, '0', pad);
    put_n(k, '0', zeros);
    put_s(k, body, blen);
    if (flags & F_LEFT)
        put_n(k, ' ', pad);
}

static void fmt_int(struct sink *k, int flags, long width, long prec,
                    int conv, unsigned long long u, int neg)
{
    char body[72], pre[4];
    const char *dig = conv == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
    unsigned base = conv == 'o' ? 8 : (conv == 'x' || conv == 'X' || conv == 'p') ? 16 : 10;
    int i = (int)sizeof body, p = 0;
    long zeros;
    unsigned long long orig = u;

    while (u != 0) {
        body[--i] = dig[u % base];
        u /= base;
    }
    if (prec < 0)
        prec = 1;
    else
        flags &= ~F_ZERO;
    zeros = prec > (long)sizeof body - i ? prec - ((long)sizeof body - i) : 0;
    if (conv == 'o' && (flags & F_ALT) && zeros == 0 && (i == (int)sizeof body || body[i] != '0'))
        zeros = 1;
    if (conv == 'd' || conv == 'i') {
        if (neg) pre[p++] = '-';
        else if (flags & F_PLUS) pre[p++] = '+';
        else if (flags & F_SPACE) pre[p++] = ' ';
    }
    if (((conv == 'x' || conv == 'X') && (flags & F_ALT) && orig != 0) || conv == 'p') {
        pre[p++] = '0';
        pre[p++] = conv == 'X' ? 'X' : 'x';
    }
    pre[p] = '\0';
    emit(k, flags, width, pre, zeros, body + i, sizeof body - (size_t)i);
}

static void fmt_float(struct sink *k, int flags, long width, long prec, int conv, double v)
{
    char digs[BA_MAX_DIGITS + 2], pre[2];
    char *out;
    int n, dp, neg, upper, style, x, i, alt = flags & F_ALT;
    long len, pos, p, e;

    neg = sign_bit(v);
    v = from_bits(dbits(v) & ~SIGN_BIT);
    upper = conv == 'E' || conv == 'F' || conv == 'G';
    pre[0] = neg ? '-' : (flags & F_PLUS) ? '+' : (flags & F_SPACE) ? ' ' : '\0';
    pre[1] = '\0';

    if ((dbits(v) & EXP_MASK) == EXP_MASK) {
        int nan = (dbits(v) & FRAC_MASK) != 0;
        emit(k, flags & ~F_ZERO, width, pre, 0,
             nan ? (upper ? "NAN" : "nan") : (upper ? "INF" : "inf"), 3);
        return;
    }
    if (prec < 0)
        prec = 6;

    if (dbits(v) == 0) {
        n = 0;
        dp = 1;
    } else {
        n = __ba_exact_digits(v, digs, &dp);
    }

    style = conv | 32;          /* 'e', 'f' or 'g' */
    if (style == 'g') {
        if (prec == 0)
            prec = 1;
        if (n > 0)
            round_digits(digs, &n, &dp, (int)prec);
        x = n > 0 ? dp - 1 : 0;
        if (prec > x && x >= -4) {
            style = 'f';
            prec = prec - 1 - x;
        } else {
            style = 'e';
            prec = prec - 1;
        }
    } else if (style == 'e') {
        if (n > 0)
            round_digits(digs, &n, &dp, (int)prec + 1);
    } else {
        if (n > 0)
            round_digits(digs, &n, &dp, (int)(dp + prec > INT_MAX ? INT_MAX : dp + prec));
        if (n == 0)
            dp = 1;
    }

    len = (style == 'f' ? (dp > 0 ? dp : 1) : 1) + 1 + prec + 8;
    out = (char *)malloc((size_t)len);
    if (out == NULL) {
        k->err = 1;
        return;
    }
    pos = 0;
    if (style == 'f') {
        if (dp <= 0)
            out[pos++] = '0';
        for (i = 0; i < dp; i++)
            out[pos++] = i < n ? digs[i] : '0';
        if (prec > 0 || alt)
            out[pos++] = '.';
        for (p = 0; p < prec; p++) {
            e = dp + p;
            out[pos++] = (e >= 0 && e < n) ? digs[e] : '0';
        }
    } else {
        x = n > 0 ? dp - 1 : 0;
        out[pos++] = n > 0 ? digs[0] : '0';
        if (prec > 0 || alt)
            out[pos++] = '.';
        for (p = 1; p <= prec; p++)
            out[pos++] = p < n ? digs[p] : '0';
    }
    /* %g drops trailing zeros (and a bare point) unless '#' is given. */
    if ((conv | 32) == 'g' && !alt) {
        for (i = 0; i < pos && out[i] != '.'; i++)
            ;
        if (i < pos) {
            while (out[pos - 1] == '0')
                pos--;
            if (out[pos - 1] == '.')
                pos--;
        }
    }
    if (style == 'e') {
        out[pos++] = upper ? 'E' : 'e';
        out[pos++] = x < 0 ? '-' : '+';
        if (x < 0)
            x = -x;
        if (x >= 100)
            out[pos++] = (char)('0' + x / 100);
        out[pos++] = (char)('0' + x / 10 % 10);
        out[pos++] = (char)('0' + x % 10);
    }
    emit(k, flags, width, pre, 0, out, (size_t)pos);
    free(out);
}

static int vformat(struct sink *k, const char *fmt, va_list ap)
{
    int flags, conv;
    long width, prec;
    char len;
    const char *s;
    size_t sl;
    long long sv;
    unsigned long long uv;
    char c;

    while (*fmt != '\0') {
        if (*fmt != '%') {
            put(k, (unsigned char)*fmt++);
            continue;
        }
        fmt++;
        flags = 0;
        for (;; fmt++) {
            if (*fmt == '-') flags |= F_LEFT;
            else if (*fmt == '+') flags |= F_PLUS;
            else if (*fmt == ' ') flags |= F_SPACE;
            else if (*fmt == '#') flags |= F_ALT;
            else if (*fmt == '0') flags |= F_ZERO;
            else break;
        }
        width = 0;
        if (*fmt == '*') {
            width = va_arg(ap, int);
            if (width < 0) {
                flags |= F_LEFT;
                width = -width;
            }
            fmt++;
        } else {
            while (*fmt >= '0' && *fmt <= '9')
                width = width * 10 + (*fmt++ - '0');
        }
        prec = -1;
        if (*fmt == '.') {
            fmt++;
            prec = 0;
            if (*fmt == '*') {
                prec = va_arg(ap, int);
                if (prec < 0)
                    prec = -1;
                fmt++;
            } else {
                while (*fmt >= '0' && *fmt <= '9')
                    prec = prec * 10 + (*fmt++ - '0');
            }
        }
        if (flags & F_LEFT)
            flags &= ~F_ZERO;
        if (flags & F_PLUS)
            flags &= ~F_SPACE;
        len = 0;
        if (*fmt == 'h') {
            len = 'h';
            if (*++fmt == 'h') { len = 'H'; fmt++; }
        } else if (*fmt == 'l') {
            len = 'l';
            if (*++fmt == 'l') { len = 'q'; fmt++; }
        } else if (*fmt == 'L' || *fmt == 'q' || *fmt == 'j') {
            len = *fmt == 'L' ? 'L' : 'q';
            fmt++;
        } else if (*fmt == 'z' || *fmt == 't') {
            len = 'z';
            fmt++;
        }
        conv = (unsigned char)*fmt;
        if (conv == '\0')
            break;
        fmt++;
        switch (conv) {
        case 'd':
        case 'i':
            if (len == 'q') sv = va_arg(ap, long long);
            else if (len == 'l' || len == 'z') sv = va_arg(ap, long);
            else sv = va_arg(ap, int);
            if (len == 'h') sv = (short)sv;
            if (len == 'H') sv = (signed char)sv;
            uv = sv < 0 ? 0ULL - (unsigned long long)sv : (unsigned long long)sv;
            fmt_int(k, flags, width, prec, 'd', uv, sv < 0);
            break;
        case 'o':
        case 'u':
        case 'x':
        case 'X':
            if (len == 'q') uv = va_arg(ap, unsigned long long);
            else if (len == 'l' || len == 'z') uv = va_arg(ap, unsigned long);
            else uv = va_arg(ap, unsigned int);
            if (len == 'h') uv = (unsigned short)uv;
            if (len == 'H') uv = (unsigned char)uv;
            fmt_int(k, flags, width, prec, conv, uv, 0);
            break;
        case 'p':
            s = (const char *)va_arg(ap, void *);
            if (s == NULL)
                emit(k, flags & ~F_ZERO, width, "", 0, "(nil)", 5);
            else
                fmt_int(k, flags, width, prec, 'p', (unsigned long long)(size_t)s, 0);
            break;
        case 'c':
            c = (char)va_arg(ap, int);
            emit(k, flags & ~F_ZERO, width, "", 0, &c, 1);
            break;
        case 's':
            s = va_arg(ap, const char *);
            if (s == NULL)
                s = (prec < 0 || prec >= 6) ? "(null)" : "";
            for (sl = 0; (prec < 0 || (long)sl < prec) && s[sl] != '\0'; sl++)
                ;
            emit(k, flags & ~F_ZERO, width, "", 0, s, sl);
            break;
        case 'e':
        case 'E':
        case 'f':
        case 'F':
        case 'g':
        case 'G':
            if (len == 'L')
                fmt_float(k, flags, width, prec, conv, (double)va_arg(ap, long double));
            else
                fmt_float(k, flags, width, prec, conv, va_arg(ap, double));
            break;
        case 'n':
            if (len == 'h') *va_arg(ap, short *) = (short)k->pos;
            else if (len == 'H') *va_arg(ap, signed char *) = (signed char)k->pos;
            else if (len == 'l' || len == 'z') *va_arg(ap, long *) = (long)k->pos;
            else if (len == 'q') *va_arg(ap, long long *) = (long long)k->pos;
            else *va_arg(ap, int *) = (int)k->pos;
            break;
        case '%':
            put(k, '%');
            break;
        default:        /* unknown conversion: print it as is */
            put(k, '%');
            put(k, conv);
            break;
        }
    }
    sink_flush(k);
    if (k->s != NULL && k->cap > 0)
        k->s[k->pos < k->cap ? k->pos : k->cap - 1] = '\0';
    if (k->err || k->pos > (size_t)INT_MAX)
        return -1;
    return (int)k->pos;
}

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
    struct sink k;
    k.f = f;
    k.s = NULL;
    k.cap = 0;
    k.pos = 0;
    k.err = 0;
    k.blen = 0;
    return vformat(&k, fmt, ap);
}

int vsnprintf(char *s, size_t n, const char *fmt, va_list ap)
{
    struct sink k;
    k.f = NULL;
    k.s = s;
    k.cap = n;
    k.pos = 0;
    k.err = 0;
    k.blen = 0;
    return vformat(&k, fmt, ap);
}

int vsprintf(char *s, const char *fmt, va_list ap)
{
    return vsnprintf(s, (size_t)-1, fmt, ap);
}

int vprintf(const char *fmt, va_list ap)
{
    return vfprintf(stdout, fmt, ap);
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfprintf(f, fmt, ap);
    va_end(ap);
    return r;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfprintf(stdout, fmt, ap);
    va_end(ap);
    return r;
}

int sprintf(char *s, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsnprintf(s, (size_t)-1, fmt, ap);
    va_end(ap);
    return r;
}

int snprintf(char *s, size_t n, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsnprintf(s, n, fmt, ap);
    va_end(ap);
    return r;
}

/* ===================================================================== */
/* strtod                                                                */
/* ===================================================================== */

/* Unsigned big integers in base 2^16, least significant limb first. */
#define BN_LIMBS 520

struct bn {
    int n;
    unsigned long d[BN_LIMBS];
};

static void bn_small(struct bn *b, unsigned long v)
{
    b->n = 0;
    while (v != 0) {
        b->d[b->n++] = v & 0xFFFFUL;
        v >>= 16;
    }
}

static void bn_muladd(struct bn *b, unsigned long m, unsigned long a)  /* m, a < 2^16 */
{
    unsigned long carry = a, t;
    int i;
    for (i = 0; i < b->n; i++) {
        t = b->d[i] * m + carry;
        b->d[i] = t & 0xFFFFUL;
        carry = t >> 16;
    }
    if (carry != 0 && b->n < BN_LIMBS)
        b->d[b->n++] = carry;
}

static int bn_bits(const struct bn *b)
{
    int bits;
    unsigned long top;
    if (b->n == 0)
        return 0;
    bits = (b->n - 1) * 16;
    for (top = b->d[b->n - 1]; top != 0; top >>= 1)
        bits++;
    return bits;
}

static void bn_shl(struct bn *b, int s)
{
    int limbs = s / 16, bits = s % 16, i;
    if (b->n == 0 || s <= 0)
        return;
    if (b->n + limbs + 1 > BN_LIMBS)
        return;         /* cannot happen with the input limits below */
    b->d[b->n] = 0;
    for (i = b->n; i >= 0; i--)
        b->d[i + limbs] = b->d[i];
    for (i = 0; i < limbs; i++)
        b->d[i] = 0;
    b->n += limbs + 1;
    if (bits != 0) {
        for (i = b->n - 1; i > limbs; i--)
            b->d[i] = ((b->d[i] << bits) | (b->d[i - 1] >> (16 - bits))) & 0xFFFFUL;
        b->d[limbs] = (b->d[limbs] << bits) & 0xFFFFUL;
    }
    while (b->n > 0 && b->d[b->n - 1] == 0)
        b->n--;
}

static void bn_shr1(struct bn *b)
{
    int i;
    for (i = 0; i < b->n; i++) {
        b->d[i] >>= 1;
        if (i + 1 < b->n)
            b->d[i] |= (b->d[i + 1] & 1UL) << 15;
    }
    while (b->n > 0 && b->d[b->n - 1] == 0)
        b->n--;
}

static int bn_cmp(const struct bn *a, const struct bn *b)
{
    int i;
    if (a->n != b->n)
        return a->n < b->n ? -1 : 1;
    for (i = a->n - 1; i >= 0; i--)
        if (a->d[i] != b->d[i])
            return a->d[i] < b->d[i] ? -1 : 1;
    return 0;
}

static void bn_sub(struct bn *a, const struct bn *b)    /* a -= b, a >= b */
{
    unsigned long borrow = 0, t;
    int i;
    for (i = 0; i < a->n; i++) {
        t = a->d[i] + 0x10000UL - borrow - (i < b->n ? b->d[i] : 0);
        a->d[i] = t & 0xFFFFUL;
        borrow = t < 0x10000UL;
    }
    while (a->n > 0 && a->d[a->n - 1] == 0)
        a->n--;
}

static void bn_pow10(struct bn *b, int k)
{
    for (; k >= 4; k -= 4)
        bn_muladd(b, 10000UL, 0);
    for (; k > 0; k--)
        bn_muladd(b, 10UL, 0);
}

static int match_word(const char *s, const char *w)    /* case-insensitive prefix */
{
    int i;
    for (i = 0; w[i] != '\0'; i++)
        if (tolower((unsigned char)s[i]) != w[i])
            return 0;
    return 1;
}

static double signed_zero(int neg)
{
    return from_bits(neg ? SIGN_BIT : 0);
}

static double signed_inf(int neg)
{
    return from_bits(neg ? SIGN_BIT | EXP_MASK : EXP_MASK);
}

/* Round quo * 2^-s (plus a nonzero tail below quo if sticky) to the
   nearest double, ties to even. Sets errno to ERANGE on overflow and when
   the result underflows to zero. */
static double round_quo(unsigned long long quo, long s, int sticky, int neg)
{
    unsigned long long kept, u;
    long ex, prec, d;
    int bits = 0;

    for (kept = quo; kept != 0; kept >>= 1)
        bits++;
    if (bits == 0)
        return signed_zero(neg);
    ex = bits - 1 - s;          /* value is in [2^ex, 2^(ex+1)) */
    if (ex > 1023) {
        errno = ERANGE;
        return signed_inf(neg);
    }
    prec = ex < -1022 ? 53 - (-1022 - ex) : 53;
    d = bits - prec;            /* low bits to drop */
    if (d > bits) {
        errno = ERANGE;
        return signed_zero(neg);
    }
    if (d <= 0) {
        kept = quo << -d;       /* exact: widen to prec bits */
    } else {
        kept = quo >> d;
        if (((quo >> (d - 1)) & 1ULL) &&
            (sticky || (quo & ((1ULL << (d - 1)) - 1ULL)) != 0 || (kept & 1ULL)))
            kept++;
    }
    if (kept == 0) {
        errno = ERANGE;
        return signed_zero(neg);
    }
    /* value = kept * 2^(d - s). For a normal result kept is in [2^52, 2^53]
       and the biased exponent is (d - s) + 1075; for a subnormal one d - s is
       -1074 and the bits are kept itself. Both are this sum, and a carry
       out of the significand moves into the exponent as it should. */
    u = ((unsigned long long)(d - s + 1074) << 52) + kept;
    if (u >= EXP_MASK) {
        errno = ERANGE;
        return signed_inf(neg);
    }
    return from_bits(neg ? u | SIGN_BIT : u);
}

double ldexp(double x, int n)
{
    unsigned long long u = dbits(x), m;
    long q;
    int neg = (u & SIGN_BIT) != 0;

    if ((u & ~SIGN_BIT) == 0 || (u & EXP_MASK) == EXP_MASK)
        return x;               /* zero, infinity or NaN */
    m = u & FRAC_MASK;
    q = (long)((u & EXP_MASK) >> 52);
    if (q == 0) {
        q = -1074;
    } else {
        m |= 1ULL << 52;
        q -= 1075;
    }
    if (n > 5000) n = 5000;
    if (n < -5000) n = -5000;
    return round_quo(m, -(q + n), 0, neg);
}

static int hex_value(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* C99 hexadecimal floating constants: 0x1.8p3. p points after "0x". */
static double hex_float(const char *p, char **end, int neg)
{
    unsigned long long m = 0;
    long e2 = 0, ex = 0;
    int sticky = 0, v, eneg;
    const char *q;

    for (; (v = hex_value((unsigned char)*p)) >= 0; p++) {
        if (m < (1ULL << 56)) m = m * 16 + (unsigned)v;
        else { e2 += 4; if (v != 0) sticky = 1; }
    }
    if (*p == '.') {
        for (p++; (v = hex_value((unsigned char)*p)) >= 0; p++) {
            if (m < (1ULL << 56)) { m = m * 16 + (unsigned)v; e2 -= 4; }
            else if (v != 0) sticky = 1;
        }
    }
    if (*p == 'p' || *p == 'P') {
        q = p + 1;
        eneg = 0;
        if (*q == '+' || *q == '-')
            eneg = *q++ == '-';
        if (*q >= '0' && *q <= '9') {
            for (; *q >= '0' && *q <= '9'; q++)
                if (ex < 100000L)
                    ex = ex * 10 + (*q - '0');
            p = q;
            e2 += eneg ? -ex : ex;
        }
    }
    if (end) *end = (char *)p;
    if (e2 > 100000L) e2 = 100000L;
    if (e2 < -100000L) e2 = -100000L;
    return round_quo(m, -e2, sticky, neg);
}

double strtod(const char *str, char **end)
{
    static struct bn num, den;  /* 4 KB each: kept off the stack */
    char digs[BA_MAX_DIGITS];
    const char *p = str, *q;
    int neg = 0, nd = 0, sticky = 0, seen = 0, k = 0, ex, eneg, s, b, i;
    long e10 = 0;
    unsigned long long quo;

    while (isspace((unsigned char)*p))
        p++;
    if (*p == '+' || *p == '-')
        neg = *p++ == '-';

    if (match_word(p, "inf")) {
        p += match_word(p, "infinity") ? 8 : 3;
        if (end) *end = (char *)p;
        return signed_inf(neg);
    }
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X') &&
        (hex_value((unsigned char)p[2]) >= 0 ||
         (p[2] == '.' && hex_value((unsigned char)p[3]) >= 0)))
        return hex_float(p + 2, end, neg);
    if (match_word(p, "nan")) {
        p += 3;
        if (*p == '(') {
            for (q = p + 1; isalnum((unsigned char)*q) || *q == '_'; q++)
                ;
            if (*q == ')')
                p = q + 1;
        }
        if (end) *end = (char *)p;
        return __ba_nan();
    }

    /* Mantissa: keep up to BA_MAX_DIGITS significant digits. */
    for (; *p >= '0' && *p <= '9'; p++) {
        seen = 1;
        if (nd == 0 && *p == '0')
            continue;
        if (nd < BA_MAX_DIGITS) digs[nd++] = *p;
        else { k++; if (*p != '0') sticky = 1; }
    }
    if (*p == '.') {
        for (p++; *p >= '0' && *p <= '9'; p++) {
            seen = 1;
            if (nd == 0 && *p == '0') { k--; continue; }
            if (nd < BA_MAX_DIGITS) { digs[nd++] = *p; k--; }
            else if (*p != '0') sticky = 1;
        }
    }
    if (!seen) {
        if (end) *end = (char *)str;
        return signed_zero(0);
    }
    if (*p == 'e' || *p == 'E') {
        q = p + 1;
        eneg = 0;
        if (*q == '+' || *q == '-')
            eneg = *q++ == '-';
        if (*q >= '0' && *q <= '9') {
            for (; *q >= '0' && *q <= '9'; q++)
                if (e10 < 100000L)
                    e10 = e10 * 10 + (*q - '0');
            p = q;
            if (eneg)
                e10 = -e10;
        }
    }
    if (end) *end = (char *)p;

    while (nd > 0 && digs[nd - 1] == '0' && !sticky) {
        nd--;
        k++;
    }
    if (nd == 0)
        return signed_zero(neg);
    e10 += k;           /* value = DIGITS * 10^e10 */
    if (e10 + nd > 310) {
        errno = ERANGE;
        return signed_inf(neg);
    }
    if (e10 + nd < -330) {
        errno = ERANGE;
        return signed_zero(neg);
    }
    ex = (int)e10;

    num.n = 0;
    for (i = 0; i < nd; i++)
        bn_muladd(&num, 10UL, (unsigned long)(digs[i] - '0'));
    if (sticky) {       /* stands in for the dropped digits; see header */
        bn_muladd(&num, 10UL, 1UL);
        ex--;
    }
    bn_small(&den, 1UL);
    if (ex >= 0)
        bn_pow10(&num, ex);
    else
        bn_pow10(&den, -ex);

    /* Scale so that num / den lies in [2^55, 2^57). */
    s = 56 + bn_bits(&den) - bn_bits(&num);
    if (s > 0) bn_shl(&num, s);
    else bn_shl(&den, -s);

    /* 58-bit quotient by binary long division; the remainder is sticky. */
    bn_shl(&den, 57);
    quo = 0;
    for (b = 57; b >= 0; b--) {
        if (bn_cmp(&num, &den) >= 0) {
            bn_sub(&num, &den);
            quo |= 1ULL << b;
        }
        bn_shr1(&den);
    }
    sticky = num.n != 0;

    return round_quo(quo, (long)s, sticky, neg);
}

double atof(const char *s)
{
    return strtod(s, (char **)0);
}

/* ===================================================================== */
/* scanf                                                                 */
/* ===================================================================== */

struct src {
    FILE *f;
    const char *s;
    long count;
};

static int src_get(struct src *in)
{
    int c;
    if (in->f != NULL) {
        c = getc(in->f);
    } else {
        c = *in->s != '\0' ? (unsigned char)*in->s : EOF;
        if (c != EOF)
            in->s++;
    }
    if (c != EOF)
        in->count++;
    return c;
}

static void src_unget(struct src *in, int c)
{
    if (c == EOF)
        return;
    in->count--;
    if (in->f != NULL)
        ungetc(c, in->f);
    else
        in->s--;
}

#define SCAN_BUF 512

/* Read the longest prefix of a number in base `base` (0 = C rules) into buf. */
static int scan_int_text(struct src *in, long width, int base, char *buf)
{
    int n = 0, c;
    if (width <= 0 || width > SCAN_BUF - 1)
        width = SCAN_BUF - 1;
    c = src_get(in);
    if ((c == '+' || c == '-') && n < width) {
        buf[n++] = (char)c;
        c = src_get(in);
    }
    if ((base == 0 || base == 16) && c == '0' && n < width) {
        buf[n++] = (char)c;
        c = src_get(in);
        if ((c == 'x' || c == 'X') && n < width) {
            buf[n++] = (char)c;
            c = src_get(in);
            base = 16;
            if (n >= width || c == EOF || !isxdigit(c)) {
                src_unget(in, c);
                return 0;       /* "0x" with no digits: matching failure */
            }
        } else if (base == 0) {
            base = 8;
        }
    }
    if (base == 0)
        base = 10;
    while (n < width && c != EOF &&
           ((base == 16 && isxdigit(c)) || (base == 10 && isdigit(c)) ||
            (base == 8 && c >= '0' && c <= '7'))) {
        buf[n++] = (char)c;
        c = src_get(in);
    }
    src_unget(in, c);
    buf[n] = '\0';
    return n;
}

static int scan_float_text(struct src *in, long width, char *buf)
{
    int n = 0, c, digits = 0;
    if (width <= 0 || width > SCAN_BUF - 1)
        width = SCAN_BUF - 1;
    c = src_get(in);
    if ((c == '+' || c == '-') && n < width) {
        buf[n++] = (char)c;
        c = src_get(in);
    }
    if (c == 'i' || c == 'I' || c == 'n' || c == 'N') {   /* inf, nan */
        while (n < width && c != EOF && isalpha(c)) {
            buf[n++] = (char)c;
            c = src_get(in);
        }
        src_unget(in, c);
        buf[n] = '\0';
        return n;
    }
    if (c == '0' && n < width) {
        buf[n++] = (char)c;
        digits++;
        c = src_get(in);
        if ((c == 'x' || c == 'X') && n < width) {       /* C99 hex float */
            buf[n++] = (char)c;
            c = src_get(in);
            digits = 0;
            while (n < width && c != EOF && isxdigit(c)) {
                buf[n++] = (char)c;
                digits++;
                c = src_get(in);
            }
            if (n < width && c == '.') {
                buf[n++] = (char)c;
                c = src_get(in);
                while (n < width && c != EOF && isxdigit(c)) {
                    buf[n++] = (char)c;
                    digits++;
                    c = src_get(in);
                }
            }
            if (digits > 0 && n < width && (c == 'p' || c == 'P')) {
                buf[n++] = (char)c;
                c = src_get(in);
                if (n < width && (c == '+' || c == '-')) {
                    buf[n++] = (char)c;
                    c = src_get(in);
                }
                while (n < width && c != EOF && isdigit(c)) {
                    buf[n++] = (char)c;
                    c = src_get(in);
                }
            }
            src_unget(in, c);
            buf[n] = '\0';
            return digits > 0 ? n : 0;
        }
    }
    while (n < width && c != EOF && isdigit(c)) {
        buf[n++] = (char)c;
        digits++;
        c = src_get(in);
    }
    if (n < width && c == '.') {
        buf[n++] = (char)c;
        c = src_get(in);
        while (n < width && c != EOF && isdigit(c)) {
            buf[n++] = (char)c;
            digits++;
            c = src_get(in);
        }
    }
    if (digits > 0 && n < width && (c == 'e' || c == 'E')) {
        buf[n++] = (char)c;
        c = src_get(in);
        if (n < width && (c == '+' || c == '-')) {
            buf[n++] = (char)c;
            c = src_get(in);
        }
        while (n < width && c != EOF && isdigit(c)) {
            buf[n++] = (char)c;
            c = src_get(in);
        }
    }
    src_unget(in, c);
    buf[n] = '\0';
    return digits > 0 ? n : 0;
}

static int vscan(struct src *in, const char *fmt, va_list ap)
{
    char buf[SCAN_BUF], set[256];
    int assigned = 0, c, suppress, conv, n, invert, i;
    long width;
    char len;
    char *s, *endp;
    unsigned long long uv;
    long long sv;
    double dv;

    while (*fmt != '\0') {
        if (isspace((unsigned char)*fmt)) {
            while (isspace((unsigned char)*fmt))
                fmt++;
            do c = src_get(in); while (c != EOF && isspace(c));
            src_unget(in, c);
            continue;
        }
        if (*fmt != '%' || fmt[1] == '%') {
            if (*fmt == '%') {
                fmt++;
                do c = src_get(in); while (c != EOF && isspace(c));
            } else {
                c = src_get(in);
            }
            if (c != (unsigned char)*fmt) {
                src_unget(in, c);
                return (c == EOF && assigned == 0) ? EOF : assigned;
            }
            fmt++;
            continue;
        }
        fmt++;
        suppress = 0;
        if (*fmt == '*') {
            suppress = 1;
            fmt++;
        }
        width = 0;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (*fmt++ - '0');
        len = 0;
        if (*fmt == 'h') {
            len = 'h';
            if (*++fmt == 'h') { len = 'H'; fmt++; }
        } else if (*fmt == 'l') {
            len = 'l';
            if (*++fmt == 'l') { len = 'q'; fmt++; }
        } else if (*fmt == 'L' || *fmt == 'q' || *fmt == 'j') {
            len = *fmt == 'L' ? 'L' : 'q';
            fmt++;
        } else if (*fmt == 'z' || *fmt == 't') {
            len = 'z';
            fmt++;
        }
        conv = (unsigned char)*fmt++;
        if (conv == '\0')
            break;

        if (conv == 'n') {
            if (!suppress) {
                if (len == 'h') *va_arg(ap, short *) = (short)in->count;
                else if (len == 'H') *va_arg(ap, signed char *) = (signed char)in->count;
                else if (len == 'l' || len == 'z') *va_arg(ap, long *) = in->count;
                else if (len == 'q') *va_arg(ap, long long *) = in->count;
                else *va_arg(ap, int *) = (int)in->count;
            }
            continue;
        }
        if (conv != 'c' && conv != '[') {
            do c = src_get(in); while (c != EOF && isspace(c));
            src_unget(in, c);
            if (c == EOF)
                return assigned == 0 ? EOF : assigned;
        }

        switch (conv) {
        case 'd': case 'i': case 'o': case 'u': case 'x': case 'X': case 'p':
            n = scan_int_text(in, width,
                              conv == 'd' || conv == 'u' ? 10 : conv == 'i' ? 0 :
                              conv == 'o' ? 8 : 16, buf);
            if (n == 0 || ((buf[0] == '+' || buf[0] == '-') && n == 1))
                return assigned;
            if (!suppress) {
                i = conv == 'd' || conv == 'u' ? 10 : conv == 'i' ? 0 : conv == 'o' ? 8 : 16;
                if (conv == 'p') {
                    uv = strtoul(buf, &endp, 16);
                    *va_arg(ap, void **) = (void *)(size_t)uv;
                } else if (conv == 'd' || conv == 'i') {
                    sv = strtol(buf, &endp, i);
                    if (len == 'h') *va_arg(ap, short *) = (short)sv;
                    else if (len == 'H') *va_arg(ap, signed char *) = (signed char)sv;
                    else if (len == 'l' || len == 'z') *va_arg(ap, long *) = (long)sv;
                    else if (len == 'q') *va_arg(ap, long long *) = sv;
                    else *va_arg(ap, int *) = (int)sv;
                } else {
                    uv = buf[0] == '-' ? 0ULL - (unsigned long long)strtoul(buf + 1, &endp, i)
                                       : (unsigned long long)strtoul(buf, &endp, i);
                    if (len == 'h') *va_arg(ap, unsigned short *) = (unsigned short)uv;
                    else if (len == 'H') *va_arg(ap, unsigned char *) = (unsigned char)uv;
                    else if (len == 'l' || len == 'z') *va_arg(ap, unsigned long *) = (unsigned long)uv;
                    else if (len == 'q') *va_arg(ap, unsigned long long *) = uv;
                    else *va_arg(ap, unsigned int *) = (unsigned int)uv;
                }
                assigned++;
            }
            break;
        case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A':
            n = scan_float_text(in, width, buf);
            if (n == 0)
                return assigned;
            dv = strtod(buf, &endp);
            if (*endp != '\0')
                return assigned;
            if (!suppress) {
                if (len == 'l') *va_arg(ap, double *) = dv;
                else if (len == 'L') *va_arg(ap, long double *) = dv;
                else *va_arg(ap, float *) = (float)dv;
                assigned++;
            }
            break;
        case 's':
            s = suppress ? NULL : va_arg(ap, char *);
            n = 0;
            c = src_get(in);
            while (c != EOF && !isspace(c) && (width == 0 || n < width)) {
                if (s) s[n] = (char)c;
                n++;
                c = src_get(in);
            }
            src_unget(in, c);
            if (s) {
                s[n] = '\0';
                assigned++;
            }
            break;
        case 'c':
            s = suppress ? NULL : va_arg(ap, char *);
            if (width == 0)
                width = 1;
            for (n = 0; n < width; n++) {
                c = src_get(in);
                if (c == EOF)
                    return assigned == 0 ? EOF : assigned;
                if (s) s[n] = (char)c;
            }
            if (s)
                assigned++;
            break;
        case '[':
            invert = 0;
            if (*fmt == '^') {
                invert = 1;
                fmt++;
            }
            memset(set, 0, sizeof set);
            if (*fmt == ']')
                set[(unsigned char)*fmt++] = 1;
            while (*fmt != '\0' && *fmt != ']') {
                if (fmt[1] == '-' && fmt[2] != ']' && fmt[2] != '\0' &&
                    (unsigned char)fmt[0] <= (unsigned char)fmt[2]) {
                    for (i = (unsigned char)fmt[0]; i <= (unsigned char)fmt[2]; i++)
                        set[i] = 1;
                    fmt += 3;
                } else {
                    set[(unsigned char)*fmt++] = 1;
                }
            }
            if (*fmt == ']')
                fmt++;
            s = suppress ? NULL : va_arg(ap, char *);
            n = 0;
            c = src_get(in);
            while (c != EOF && (set[c] != 0) != invert && (width == 0 || n < width)) {
                if (s) s[n] = (char)c;
                n++;
                c = src_get(in);
            }
            src_unget(in, c);
            if (n == 0)
                return (c == EOF && assigned == 0) ? EOF : assigned;
            if (s) {
                s[n] = '\0';
                assigned++;
            }
            break;
        default:
            return assigned;
        }
    }
    return assigned;
}

int vfscanf(FILE *f, const char *fmt, va_list ap)
{
    struct src in;
    in.f = f;
    in.s = NULL;
    in.count = 0;
    return vscan(&in, fmt, ap);
}

int vsscanf(const char *s, const char *fmt, va_list ap)
{
    struct src in;
    in.f = NULL;
    in.s = s;
    in.count = 0;
    return vscan(&in, fmt, ap);
}

int vscanf(const char *fmt, va_list ap)
{
    return vfscanf(stdin, fmt, ap);
}

int fscanf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfscanf(f, fmt, ap);
    va_end(ap);
    return r;
}

int sscanf(const char *s, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsscanf(s, fmt, ap);
    va_end(ap);
    return r;
}

int scanf(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfscanf(stdin, fmt, ap);
    va_end(ap);
    return r;
}
