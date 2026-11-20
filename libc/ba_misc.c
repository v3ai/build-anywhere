/*
 * ba_misc.c: C89 library functions missing from GNU Mes libc that need
 * nothing from the operating system: <stdlib.h> (div, ldiv, labs, rand,
 * srand, bsearch, multibyte conversions), <string.h> (strtok, strcoll,
 * strxfrm), <locale.h> and the assert() failure handler.
 *
 * Part of build-anywhere. Only the "C" locale exists.
 */
#include <limits.h>
#include <locale.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ba_libc.h"

/* C89 requires the quotient to be truncated toward zero; plain `/` may
   round either way in C89, so fix up the result. */
div_t div(int num, int den)
{
    div_t r;
    r.quot = num / den;
    r.rem = num % den;
    if (r.rem != 0 && ((r.rem < 0) != (num < 0))) {
        r.quot += 1;
        r.rem -= den;
    }
    return r;
}

ldiv_t ldiv(long num, long den)
{
    ldiv_t r;
    r.quot = num / den;
    r.rem = num % den;
    if (r.rem != 0 && ((r.rem < 0) != (num < 0))) {
        r.quot += 1;
        r.rem -= den;
    }
    return r;
}

long labs(long v)
{
    return v < 0 ? -v : v;
}

/* The portable generator from the C standard, so sequences are the same
   everywhere. */
static unsigned long ba_seed = 1;

int rand(void)
{
    ba_seed = (ba_seed * 1103515245UL + 12345UL) & 0xFFFFFFFFUL;
    return (int)((ba_seed / 65536UL) % 32768UL);
}

void srand(unsigned int seed)
{
    ba_seed = seed;
}

void *bsearch(const void *key, const void *base, size_t n, size_t size,
              int (*cmp)(const void *, const void *))
{
    const char *lo = (const char *)base;
    const char *mid;
    int c;

    while (n > 0) {
        mid = lo + (n / 2) * size;
        c = cmp(key, mid);
        if (c == 0)
            return (void *)mid;
        if (c > 0) {
            lo = mid + size;
            n -= n / 2 + 1;
        } else {
            n /= 2;
        }
    }
    return NULL;
}

/* Multibyte functions for the "C" locale: one byte is one character. */
int mblen(const char *s, size_t n)
{
    if (s == NULL)
        return 0;
    if (n == 0)
        return -1;
    return *s != '\0';
}

int mbtowc(wchar_t *pwc, const char *s, size_t n)
{
    if (s == NULL)
        return 0;
    if (n == 0)
        return -1;
    if (pwc != NULL)
        *pwc = (wchar_t)(unsigned char)*s;
    return *s != '\0';
}

int wctomb(char *s, wchar_t wc)
{
    if (s == NULL)
        return 0;
    if (wc < 0 || wc > UCHAR_MAX)
        return -1;
    *s = (char)wc;
    return 1;
}

size_t wcstombs(char *s, const wchar_t *pwcs, size_t n)
{
    size_t i = 0;
    while (s == NULL || i < n) {
        if (pwcs[i] < 0 || pwcs[i] > UCHAR_MAX)
            return (size_t)-1;
        if (s != NULL)
            s[i] = (char)pwcs[i];
        if (pwcs[i] == 0)
            return i;
        i++;
    }
    return i;
}

char *strtok(char *s, const char *delim)
{
    static char *next;
    char *tok;

    if (s == NULL)
        s = next;
    if (s == NULL)
        return NULL;
    s += strspn(s, delim);
    if (*s == '\0') {
        next = NULL;
        return NULL;
    }
    tok = s;
    s += strcspn(s, delim);
    if (*s != '\0')
        *s++ = '\0';
    else
        s = NULL;
    next = s;
    return tok;
}

int strcoll(const char *a, const char *b)
{
    return strcmp(a, b);
}

size_t strxfrm(char *dst, const char *src, size_t n)
{
    size_t len = strlen(src);
    if (n > 0) {
        if (len < n) {
            memcpy(dst, src, len + 1);
        } else {
            memcpy(dst, src, n - 1);
            dst[n - 1] = '\0';
        }
    }
    return len;
}

char *setlocale(int category, const char *name)
{
    static char c_name[] = "C";
    (void)category;
    if (name == NULL || name[0] == '\0' || strcmp(name, "C") == 0 ||
        strcmp(name, "POSIX") == 0)
        return c_name;
    return NULL;
}

struct lconv *localeconv(void)
{
    static struct lconv lc;
    static char point[] = ".";
    static char empty[] = "";

    lc.decimal_point = point;
    lc.thousands_sep = empty;
    lc.grouping = empty;
    lc.int_curr_symbol = empty;
    lc.currency_symbol = empty;
    lc.mon_decimal_point = empty;
    lc.mon_thousands_sep = empty;
    lc.mon_grouping = empty;
    lc.positive_sign = empty;
    lc.negative_sign = empty;
    lc.int_frac_digits = CHAR_MAX;
    lc.frac_digits = CHAR_MAX;
    lc.p_cs_precedes = CHAR_MAX;
    lc.p_sep_by_space = CHAR_MAX;
    lc.n_cs_precedes = CHAR_MAX;
    lc.n_sep_by_space = CHAR_MAX;
    lc.p_sign_posn = CHAR_MAX;
    lc.n_sign_posn = CHAR_MAX;
    return &lc;
}

void __ba_assert_fail(const char *expr, const char *file, int line)
{
    fprintf(stderr, "Assertion failed: %s, file %s, line %d\n", expr, file, line);
    fflush(stderr);
    abort();
}
