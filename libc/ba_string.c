/*
 * ba_string.c: <string.h>, <ctype.h> ("C" locale) and strerror for the
 * build-anywhere libc.
 *
 * Part of build-anywhere.
 */
#include <ctype.h>
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (n >= 16 && ((size_t)d % sizeof(long)) == 0 && ((size_t)s % sizeof(long)) == 0) {
        long *dl = (long *)d;
        const long *sl = (const long *)s;
        for (; n >= sizeof(long); n -= sizeof(long))
            *dl++ = *sl++;
        d = (unsigned char *)dl;
        s = (const unsigned char *)sl;
    }
    while (n-- > 0)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d == s || n == 0)
        return dst;
    if (d < s || d >= s + n)
        return memcpy(dst, src, n);
    while (n-- > 0)
        d[n] = s[n];
    return dst;
}

void *memset(void *s, int c, size_t n)
{
    unsigned char *p = (unsigned char *)s;
    if (n >= 16 && ((size_t)p % sizeof(long)) == 0) {
        unsigned long v = (unsigned char)c;
        long *pl = (long *)p;
        v |= v << 8;
        v |= v << 16;
        if (sizeof(long) > 4)
            v |= (v << 16) << 16;
        for (; n >= sizeof(long); n -= sizeof(long))
            *pl++ = (long)v;
        p = (unsigned char *)pl;
    }
    while (n-- > 0)
        *p++ = (unsigned char)c;
    return s;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    for (; n > 0; n--, x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = (const unsigned char *)s;
    for (; n > 0; n--, p++)
        if (*p == (unsigned char)c)
            return (void *)p;
    return NULL;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p != '\0')
        p++;
    return (size_t)(p - s);
}

char *strcpy(char *dst, const char *src)
{
    char *d = dst;
    while ((*d++ = *src++) != '\0')
        ;
    return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    for (; i < n && src[i] != '\0'; i++)
        dst[i] = src[i];
    for (; i < n; i++)
        dst[i] = '\0';
    return dst;
}

char *strcat(char *dst, const char *src)
{
    strcpy(dst + strlen(dst), src);
    return dst;
}

char *strncat(char *dst, const char *src, size_t n)
{
    char *d = dst + strlen(dst);
    while (n-- > 0 && *src != '\0')
        *d++ = *src++;
    *d = '\0';
    return dst;
}

int strcmp(const char *a, const char *b)
{
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    for (; n > 0; n--, a++, b++) {
        if (*a != *b)
            return (unsigned char)*a - (unsigned char)*b;
        if (*a == '\0')
            return 0;
    }
    return 0;
}

char *strchr(const char *s, int c)
{
    for (;; s++) {
        if (*s == (char)c)
            return (char *)s;
        if (*s == '\0')
            return NULL;
    }
}

char *strrchr(const char *s, int c)
{
    const char *last = NULL;
    for (;; s++) {
        if (*s == (char)c)
            last = s;
        if (*s == '\0')
            return (char *)last;
    }
}

size_t strspn(const char *s, const char *accept)
{
    size_t n = 0;
    while (s[n] != '\0' && strchr(accept, s[n]) != NULL)
        n++;
    return n;
}

size_t strcspn(const char *s, const char *reject)
{
    size_t n = 0;
    while (s[n] != '\0' && strchr(reject, s[n]) == NULL)
        n++;
    return n;
}

char *strpbrk(const char *s, const char *accept)
{
    s += strcspn(s, accept);
    return *s != '\0' ? (char *)s : NULL;
}

char *strstr(const char *hay, const char *needle)
{
    size_t n = strlen(needle);
    if (n == 0)
        return (char *)hay;
    for (; *hay != '\0'; hay++)
        if (*hay == *needle && strncmp(hay, needle, n) == 0)
            return (char *)hay;
    return NULL;
}

char *strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (p != NULL)
        memcpy(p, s, n);
    return p;
}

char *strndup(const char *s, size_t n)
{
    size_t len = 0;
    char *p;
    while (len < n && s[len] != '\0')
        len++;
    p = (char *)malloc(len + 1);
    if (p != NULL) {
        memcpy(p, s, len);
        p[len] = '\0';
    }
    return p;
}

static const struct { int num; const char *msg; } ba_errors[] = {
    { 0, "Success" },
    { EPERM, "Operation not permitted" },
    { ENOENT, "No such file or directory" },
    { ESRCH, "No such process" },
    { EINTR, "Interrupted system call" },
    { EIO, "Input/output error" },
    { ENXIO, "No such device or address" },
    { E2BIG, "Argument list too long" },
    { ENOEXEC, "Exec format error" },
    { EBADF, "Bad file descriptor" },
    { ECHILD, "No child processes" },
    { EAGAIN, "Resource temporarily unavailable" },
    { ENOMEM, "Cannot allocate memory" },
    { EACCES, "Permission denied" },
    { EFAULT, "Bad address" },
    { EBUSY, "Device or resource busy" },
    { EEXIST, "File exists" },
    { EXDEV, "Invalid cross-device link" },
    { ENODEV, "No such device" },
    { ENOTDIR, "Not a directory" },
    { EISDIR, "Is a directory" },
    { EINVAL, "Invalid argument" },
    { ENFILE, "Too many open files in system" },
    { EMFILE, "Too many open files" },
    { ENOTTY, "Inappropriate ioctl for device" },
    { EFBIG, "File too large" },
    { ENOSPC, "No space left on device" },
    { ESPIPE, "Illegal seek" },
    { EROFS, "Read-only file system" },
    { EMLINK, "Too many links" },
    { EPIPE, "Broken pipe" },
    { EDOM, "Numerical argument out of domain" },
    { ERANGE, "Numerical result out of range" },
    { EDEADLK, "Resource deadlock avoided" },
    { ENAMETOOLONG, "File name too long" },
    { ENOLCK, "No locks available" },
    { ENOSYS, "Function not implemented" },
    { ENOTEMPTY, "Directory not empty" },
    { ELOOP, "Too many levels of symbolic links" },
    { EILSEQ, "Invalid or incomplete multibyte or wide character" }
};

char *strerror(int err)
{
    static char unknown[32];
    size_t i;
    char digits[12], *p = digits + sizeof digits;
    unsigned int u = err < 0 ? 0U - (unsigned int)err : (unsigned int)err;

    for (i = 0; i < sizeof ba_errors / sizeof ba_errors[0]; i++)
        if (ba_errors[i].num == err)
            return (char *)ba_errors[i].msg;
    *--p = '\0';
    do {
        *--p = (char)('0' + u % 10);
        u /= 10;
    } while (u != 0);
    if (err < 0)
        *--p = '-';
    strcpy(unknown, "Unknown error ");
    strcat(unknown, p);
    return unknown;
}

/* ---- ctype ---------------------------------------------------------- */

int isdigit(int c) { return c >= '0' && c <= '9'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int isalpha(int c) { return islower(c) || isupper(c); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
int isxdigit(int c) { return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
int isspace(int c) { return c == ' ' || (c >= '\t' && c <= '\r'); }
int isblank(int c) { return c == ' ' || c == '\t'; }
int iscntrl(int c) { return (c >= 0 && c < 32) || c == 127; }
int isprint(int c) { return c >= 32 && c < 127; }
int isgraph(int c) { return c > 32 && c < 127; }
int ispunct(int c) { return isgraph(c) && !isalnum(c); }
int isascii(int c) { return c >= 0 && c < 128; }
int tolower(int c) { return isupper(c) ? c - 'A' + 'a' : c; }
int toupper(int c) { return islower(c) ? c - 'a' + 'A' : c; }
