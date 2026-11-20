/*
 * libc.c: the C library of the build-anywhere shell tier, compiled by
 * pnut-sh together with the program. pnut's runtime already provides
 * printf, putchar, getchar, malloc, free, exit, open, read, write, close,
 * fopen, fclose and fgetc; this adds <string.h>, <ctype.h> and the rest of
 * the commonly used <stdio.h> and <stdlib.h> functions.
 *
 * pnut-sh compiles a subset of C (no unsigned types, no local arrays), and
 * this file stays inside it. Floating point is in float.c, terminal control
 * in term.c and sockets in net.c. Part of build-anywhere.
 */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

int errno;
char ba_sh_char[2];
int ba_sh_seed = 1;

int strlen(char *s)
{
    int n = 0;
    while (s[n] != 0)
        n++;
    return n;
}

char *strcpy(char *d, char *s)
{
    int i = 0;
    while ((d[i] = s[i]) != 0)
        i++;
    return d;
}

char *strncpy(char *d, char *s, int n)
{
    int i = 0;
    while (i < n && s[i] != 0) {
        d[i] = s[i];
        i++;
    }
    while (i < n) {
        d[i] = 0;
        i++;
    }
    return d;
}

char *strcat(char *d, char *s)
{
    strcpy(d + strlen(d), s);
    return d;
}

char *strncat(char *d, char *s, int n)
{
    int i = strlen(d), j = 0;
    while (j < n && s[j] != 0) {
        d[i + j] = s[j];
        j++;
    }
    d[i + j] = 0;
    return d;
}

int strcmp(char *a, char *b)
{
    int i = 0;
    while (a[i] != 0 && a[i] == b[i])
        i++;
    return (a[i] & 255) - (b[i] & 255);
}

int strncmp(char *a, char *b, int n)
{
    int i = 0;
    while (i < n) {
        if (a[i] != b[i])
            return (a[i] & 255) - (b[i] & 255);
        if (a[i] == 0)
            return 0;
        i++;
    }
    return 0;
}

char *strchr(char *s, int c)
{
    int i = 0;
    while (1) {
        if (s[i] == c)
            return s + i;
        if (s[i] == 0)
            return 0;
        i++;
    }
}

char *strrchr(char *s, int c)
{
    char *last = 0;
    int i = 0;
    while (1) {
        if (s[i] == c)
            last = s + i;
        if (s[i] == 0)
            return last;
        i++;
    }
}

char *strstr(char *h, char *n)
{
    int len = strlen(n);
    int i = 0;
    if (len == 0)
        return h;
    while (h[i] != 0) {
        if (strncmp(h + i, n, len) == 0)
            return h + i;
        i++;
    }
    return 0;
}

int strspn(char *s, char *set)
{
    int n = 0;
    while (s[n] != 0 && strchr(set, s[n]) != 0)
        n++;
    return n;
}

int strcspn(char *s, char *set)
{
    int n = 0;
    while (s[n] != 0 && strchr(set, s[n]) == 0)
        n++;
    return n;
}

char *strpbrk(char *s, char *set)
{
    int n = strcspn(s, set);
    if (s[n] == 0)
        return 0;
    return s + n;
}

char *strdup(char *s)
{
    char *d = malloc(strlen(s) + 1);
    if (d != 0)
        strcpy(d, s);
    return d;
}

void *memcpy(void *dst, void *src, int n)
{
    char *d = dst;
    char *s = src;
    int i = 0;
    while (i < n) {
        d[i] = s[i];
        i++;
    }
    return dst;
}

void *memmove(void *dst, void *src, int n)
{
    char *d = dst;
    char *s = src;
    if (d < s)
        return memcpy(dst, src, n);
    while (n > 0) {
        n--;
        d[n] = s[n];
    }
    return dst;
}

void *memset(void *dst, int c, int n)
{
    char *d = dst;
    int i = 0;
    while (i < n) {
        d[i] = c;
        i++;
    }
    return dst;
}

int memcmp(void *pa, void *pb, int n)
{
    char *a = pa;
    char *b = pb;
    int i = 0;
    while (i < n) {
        if (a[i] != b[i])
            return (a[i] & 255) - (b[i] & 255);
        i++;
    }
    return 0;
}

void *memchr(void *ps, int c, int n)
{
    char *s = ps;
    int i = 0;
    while (i < n) {
        if ((s[i] & 255) == (c & 255))
            return s + i;
        i++;
    }
    return 0;
}

/* pnut-sh allows && and || around function calls only inside conditions,
   hence the if statements. */
int isdigit(int c) { if (c >= '0' && c <= '9') return 1; return 0; }
int isupper(int c) { if (c >= 'A' && c <= 'Z') return 1; return 0; }
int islower(int c) { if (c >= 'a' && c <= 'z') return 1; return 0; }
int isalpha(int c) { if (isupper(c) || islower(c)) return 1; return 0; }
int isalnum(int c) { if (isalpha(c) || isdigit(c)) return 1; return 0; }
int isspace(int c) { if (c == ' ' || (c >= 9 && c <= 13)) return 1; return 0; }
int isxdigit(int c)
{
    if (isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))
        return 1;
    return 0;
}
int isprint(int c) { if (c >= 32 && c < 127) return 1; return 0; }
int isgraph(int c) { if (c > 32 && c < 127) return 1; return 0; }
int iscntrl(int c) { if ((c >= 0 && c < 32) || c == 127) return 1; return 0; }
int ispunct(int c) { if (isgraph(c) && !isalnum(c)) return 1; return 0; }
int toupper(int c) { if (islower(c)) return c - 'a' + 'A'; return c; }
int tolower(int c) { if (isupper(c)) return c - 'A' + 'a'; return c; }

void *calloc(int n, int size)
{
    char *p = malloc(n * size);
    if (p != 0)
        memset(p, 0, n * size);
    return p;
}

int abs(int v) { if (v < 0) return -v; return v; }
long labs(long v) { if (v < 0) return -v; return v; }

long strtol(char *s, char **end, int base)
{
    int i = 0, neg = 0, any = 0, d;
    long v = 0;
    while (isspace(s[i]))
        i++;
    if (s[i] == '+' || s[i] == '-') {
        if (s[i] == '-')
            neg = 1;
        i++;
    }
    if ((base == 0 || base == 16) && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')
        && isxdigit(s[i + 2]) != 0) {
        base = 16;
        i += 2;
    } else if (base == 0) {
        if (s[i] == '0')
            base = 8;
        else
            base = 10;
    }
    while (1) {
        if (isdigit(s[i]))
            d = s[i] - '0';
        else if (islower(s[i]))
            d = s[i] - 'a' + 10;
        else if (isupper(s[i]))
            d = s[i] - 'A' + 10;
        else
            break;
        if (d >= base)
            break;
        v = v * base + d;
        any = 1;
        i++;
    }
    if (end != 0) {
        if (any)
            *end = s + i;
        else
            *end = s;
    }
    if (neg)
        return -v;
    return v;
}

int atoi(char *s) { return strtol(s, 0, 10); }
long atol(char *s) { return strtol(s, 0, 10); }

int rand(void)
{
    ba_sh_seed = (ba_sh_seed * 1103515245 + 12345) & 2147483647;
    return (ba_sh_seed / 65536) & 32767;
}

void srand(int seed) { ba_sh_seed = seed; }

int fputc(int c, FILE *f)
{
    ba_sh_char[0] = c;
    if (write(f, ba_sh_char, 1) != 1)
        return EOF;
    return c & 255;
}

int putc(int c, FILE *f) { return fputc(c, f); }

int fputs(char *s, FILE *f)
{
    int n = strlen(s);
    if (n > 0 && write(f, s, n) != n)
        return EOF;
    return 1;
}

int puts(char *s)
{
    if (fputs(s, stdout) == EOF)
        return EOF;
    return fputc('\n', stdout);
}

char *fgets(char *s, int n, FILE *f)
{
    int i = 0, c;
    while (i < n - 1) {
        c = fgetc(f);
        if (c == EOF)
            break;
        s[i] = c;
        i++;
        if (c == '\n')
            break;
    }
    if (i == 0)
        return 0;
    s[i] = 0;
    return s;
}

int fflush(FILE *f) { return 0; }

void abort(void)
{
    fputs("abort\n", stderr);
    exit(134);
}

void ba_sh_assert(int ok, char *expr, char *file, int line)
{
    if (!ok) {
        fputs(file, stderr);
        fputs(": assertion failed: ", stderr);
        fputs(expr, stderr);
        fputc('\n', stderr);
        abort();
    }
}
