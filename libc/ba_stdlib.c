/*
 * ba_stdlib.c: <stdlib.h> for the build-anywhere libc: memory allocation,
 * integer conversion, sorting, the environment, process exit and system().
 *
 * Part of build-anywhere.
 */
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

/* ---- malloc ---------------------------------------------------------
 * Blocks carry a 16-byte header holding their size class. Small blocks
 * (up to 1 MiB) come in power-of-two classes, are carved from 4 MiB arenas
 * and are kept on per-class free lists when freed. Larger blocks are mapped
 * on their own and unmapped when freed. */

#define HDR 16
#define MIN_SHIFT 4
#define MAX_SHIFT 20
#define ARENA (4UL << 20)

union hdr {
    struct { size_t size; size_t cls; } h;   /* cls > MAX_SHIFT: mapped */
    long double align;
    char pad[HDR];
};

static void *free_list[MAX_SHIFT + 1];
static char *arena_ptr, *arena_end;

static void *map(size_t n)
{
    void *p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return p == MAP_FAILED ? NULL : p;
}

void *malloc(size_t n)
{
    size_t cls, bsize;
    union hdr *h;

    if (n > (size_t)-1 / 2) {
        errno = ENOMEM;
        return NULL;
    }
    for (cls = MIN_SHIFT; cls <= MAX_SHIFT && ((size_t)1 << cls) < n + HDR; cls++)
        ;
    if (cls > MAX_SHIFT) {
        bsize = (n + HDR + 4095) & ~(size_t)4095;
        h = (union hdr *)map(bsize);
        if (h == NULL) {
            errno = ENOMEM;
            return NULL;
        }
        h->h.size = bsize;
        h->h.cls = MAX_SHIFT + 1;
        return (char *)h + HDR;
    }
    if (free_list[cls] != NULL) {
        h = (union hdr *)free_list[cls];
        free_list[cls] = *(void **)((char *)h + HDR);
        return (char *)h + HDR;
    }
    bsize = (size_t)1 << cls;
    if ((size_t)(arena_end - arena_ptr) < bsize) {
        /* Put the rest of the arena on the free lists, then start a new one. */
        while (arena_ptr != NULL && (size_t)(arena_end - arena_ptr) >= ((size_t)1 << MIN_SHIFT)) {
            size_t c = MAX_SHIFT;
            while (((size_t)1 << c) > (size_t)(arena_end - arena_ptr))
                c--;
            h = (union hdr *)arena_ptr;
            h->h.size = (size_t)1 << c;
            h->h.cls = c;
            *(void **)((char *)h + HDR) = free_list[c];
            free_list[c] = h;
            arena_ptr += (size_t)1 << c;
        }
        arena_ptr = (char *)map(ARENA);
        if (arena_ptr == NULL) {
            arena_end = NULL;
            errno = ENOMEM;
            return NULL;
        }
        arena_end = arena_ptr + ARENA;
    }
    h = (union hdr *)arena_ptr;
    arena_ptr += bsize;
    h->h.size = bsize;
    h->h.cls = cls;
    return (char *)h + HDR;
}

void free(void *p)
{
    union hdr *h;
    if (p == NULL)
        return;
    h = (union hdr *)((char *)p - HDR);
    if (h->h.cls > MAX_SHIFT) {
        munmap(h, h->h.size);
        return;
    }
    *(void **)p = free_list[h->h.cls];
    free_list[h->h.cls] = h;
}

void *calloc(size_t n, size_t size)
{
    void *p;
    if (size != 0 && n > (size_t)-1 / size) {
        errno = ENOMEM;
        return NULL;
    }
    p = malloc(n * size);
    if (p != NULL)
        memset(p, 0, n * size);   /* recycled blocks are not zero */
    return p;
}

void *realloc(void *p, size_t n)
{
    union hdr *h;
    size_t have;
    void *q;
    if (p == NULL)
        return malloc(n);
    if (n == 0) {
        free(p);
        return NULL;
    }
    h = (union hdr *)((char *)p - HDR);
    have = h->h.size - HDR;
    if (n <= have && (h->h.cls > MAX_SHIFT || n > have / 2 || h->h.cls == MIN_SHIFT))
        return p;
    q = malloc(n);
    if (q == NULL)
        return NULL;
    memcpy(q, p, n < have ? n : have);
    free(p);
    return q;
}

/* ---- numbers -------------------------------------------------------- */

int abs(int v) { return v < 0 ? -v : v; }

static int digit_value(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'z') return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return 99;
}

/* Parse an unsigned magnitude; shared by the strto* integer functions.
   Sets *neg, *overflow and *end. */
static unsigned long long parse_ull(const char *s, char **end, int base, int *neg, int *overflow)
{
    const char *p = s;
    unsigned long long v = 0;
    int any = 0, d;

    *neg = 0;
    *overflow = 0;
    while (*p == ' ' || (*p >= '\t' && *p <= '\r'))
        p++;
    if (*p == '+' || *p == '-')
        *neg = *p++ == '-';
    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')
        && digit_value((unsigned char)p[2]) < 16) {
        p += 2;
        base = 16;
    } else if (base == 0) {
        base = p[0] == '0' ? 8 : 10;
    }
    if (base < 2 || base > 36) {
        errno = EINVAL;
        if (end != NULL)
            *end = (char *)s;
        return 0;
    }
    for (; (d = digit_value((unsigned char)*p)) < base; p++) {
        any = 1;
        if (v > (~0ULL - (unsigned long long)d) / (unsigned long long)base)
            *overflow = 1;
        else
            v = v * (unsigned long long)base + (unsigned long long)d;
    }
    if (end != NULL)
        *end = (char *)(any ? p : s);
    return v;
}

unsigned long long strtoull(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = parse_ull(s, end, base, &neg, &ovf);
    if (ovf) {
        errno = ERANGE;
        return ~0ULL;
    }
    return neg ? 0ULL - v : v;
}

long long strtoll(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = parse_ull(s, end, base, &neg, &ovf);
    unsigned long long lim = neg ? (unsigned long long)LLONG_MAX + 1ULL : (unsigned long long)LLONG_MAX;
    if (ovf || v > lim) {
        errno = ERANGE;
        return neg ? LLONG_MIN : LLONG_MAX;
    }
    return neg ? (long long)(0ULL - v) : (long long)v;
}

unsigned long strtoul(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = parse_ull(s, end, base, &neg, &ovf);
    if (ovf || v > ULONG_MAX) {
        errno = ERANGE;
        return ULONG_MAX;
    }
    return neg ? (unsigned long)(0UL - (unsigned long)v) : (unsigned long)v;
}

long strtol(const char *s, char **end, int base)
{
    int neg, ovf;
    unsigned long long v = parse_ull(s, end, base, &neg, &ovf);
    unsigned long long lim = neg ? (unsigned long long)LONG_MAX + 1ULL : (unsigned long long)LONG_MAX;
    if (ovf || v > lim) {
        errno = ERANGE;
        return neg ? LONG_MIN : LONG_MAX;
    }
    return neg ? (long)(0UL - (unsigned long)v) : (long)v;
}

int atoi(const char *s) { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }
float strtof(const char *s, char **end) { return (float)strtod(s, end); }
long double strtold(const char *s, char **end) { return (long double)strtod(s, end); }

size_t mbstowcs(wchar_t *pwcs, const char *s, size_t n)
{
    size_t i;
    for (i = 0; s[i] != '\0'; i++) {
        if (pwcs != NULL) {
            if (i >= n)
                return i;
            pwcs[i] = (wchar_t)(unsigned char)s[i];
        }
    }
    if (pwcs != NULL && i < n)
        pwcs[i] = 0;
    return i;
}

/* ---- qsort: heapsort, so no recursion and no worst case ------------- */

static void swap_bytes(char *a, char *b, size_t n)
{
    while (n-- > 0) {
        char t = *a;
        *a++ = *b;
        *b++ = t;
    }
}

static void sift_down(char *base, size_t root, size_t n, size_t size,
                      int (*cmp)(const void *, const void *))
{
    for (;;) {
        size_t child = 2 * root + 1;
        if (child >= n)
            return;
        if (child + 1 < n && cmp(base + child * size, base + (child + 1) * size) < 0)
            child++;
        if (cmp(base + root * size, base + child * size) >= 0)
            return;
        swap_bytes(base + root * size, base + child * size, size);
        root = child;
    }
}

void qsort(void *b, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    char *base = (char *)b;
    size_t i;
    if (n < 2 || size == 0)
        return;
    for (i = n / 2; i-- > 0;)
        sift_down(base, i, n, size, cmp);
    for (i = n - 1; i > 0; i--) {
        swap_bytes(base, base + i * size, size);
        sift_down(base, 0, i, size, cmp);
    }
}

/* ---- environment ---------------------------------------------------- */

extern char **environ;
static char **own_environ;      /* environ, once we have copied it */

char *getenv(const char *name)
{
    size_t n = strlen(name);
    char **e;
    if (environ == NULL)
        return NULL;
    for (e = environ; *e != NULL; e++)
        if (strncmp(*e, name, n) == 0 && (*e)[n] == '=')
            return *e + n + 1;
    return NULL;
}

static int env_count(void)
{
    int n = 0;
    if (environ != NULL)
        while (environ[n] != NULL)
            n++;
    return n;
}

int unsetenv(const char *name)
{
    size_t n = strlen(name);
    char **e, **d;
    if (n == 0 || strchr(name, '=') != NULL) {
        errno = EINVAL;
        return -1;
    }
    if (environ == NULL)
        return 0;
    for (e = d = environ; *e != NULL; e++)
        if (!(strncmp(*e, name, n) == 0 && (*e)[n] == '='))
            *d++ = *e;
    *d = NULL;
    return 0;
}

int setenv(const char *name, const char *value, int overwrite)
{
    size_t n = strlen(name), m = strlen(value);
    char *entry, **e;
    int count, i;

    if (n == 0 || strchr(name, '=') != NULL) {
        errno = EINVAL;
        return -1;
    }
    if (getenv(name) != NULL && !overwrite)
        return 0;
    entry = (char *)malloc(n + m + 2);
    if (entry == NULL)
        return -1;
    memcpy(entry, name, n);
    entry[n] = '=';
    memcpy(entry + n + 1, value, m + 1);
    count = env_count();
    for (i = 0; i < count; i++)
        if (strncmp(environ[i], name, n) == 0 && environ[i][n] == '=') {
            environ[i] = entry;
            return 0;
        }
    e = (char **)malloc((size_t)(count + 2) * sizeof *e);
    if (e == NULL) {
        free(entry);
        return -1;
    }
    for (i = 0; i < count; i++)
        e[i] = environ[i];
    e[count] = entry;
    e[count + 1] = NULL;
    free(own_environ);
    own_environ = environ = e;
    return 0;
}

/* ---- exit ----------------------------------------------------------- */

#define ATEXIT_MAX 64
static void (*atexit_fns[ATEXIT_MAX])(void);
static int atexit_count;
void __ba_stdio_exit(void);

int atexit(void (*func)(void))
{
    if (atexit_count >= ATEXIT_MAX)
        return -1;
    atexit_fns[atexit_count++] = func;
    return 0;
}

void exit(int status)
{
    while (atexit_count > 0)
        atexit_fns[--atexit_count]();
    __ba_stdio_exit();
    _exit(status);
}

void _Exit(int status)
{
    _exit(status);
}

void abort(void)
{
    signal(SIGABRT, SIG_DFL);
    raise(SIGABRT);
    _exit(127);
}

int system(const char *cmd)
{
    char *argv[4];
    int status = 0;
    pid_t pid;

    if (cmd == NULL)
        return access("/bin/sh", X_OK) == 0;
    fflush(NULL);
    pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        argv[0] = (char *)"sh";
        argv[1] = (char *)"-c";
        argv[2] = (char *)cmd;
        argv[3] = NULL;
        execve("/bin/sh", argv, environ);
        _exit(127);
    }
    while (waitpid(pid, &status, 0) < 0)
        if (errno != EINTR)
            return -1;
    return status;
}
