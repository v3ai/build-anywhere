/* stdlib.h: build-anywhere libc. */
#ifndef _BA_STDLIB_H
#define _BA_STDLIB_H
#include <stddef.h>
typedef struct { int quot; int rem; } div_t;
typedef struct { long quot; long rem; } ldiv_t;
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 32767
#define MB_CUR_MAX 1
double atof(const char *s);
int atoi(const char *s);
long atol(const char *s);
double strtod(const char *s, char **end);
float strtof(const char *s, char **end);
long double strtold(const char *s, char **end);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
long long strtoll(const char *s, char **end, int base);
unsigned long long strtoull(const char *s, char **end, int base);
int rand(void);
void srand(unsigned int seed);
void *calloc(size_t n, size_t size);
void free(void *p);
void *malloc(size_t size);
void *realloc(void *p, size_t size);
void abort(void);
int atexit(void (*func)(void));
void exit(int status);
void _Exit(int status);
char *getenv(const char *name);
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
int system(const char *cmd);
void *bsearch(const void *key, const void *base, size_t n, size_t size,
              int (*cmp)(const void *, const void *));
void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
int abs(int v);
long labs(long v);
div_t div(int num, int den);
ldiv_t ldiv(long num, long den);
int mblen(const char *s, size_t n);
int mbtowc(wchar_t *pwc, const char *s, size_t n);
int wctomb(char *s, wchar_t wc);
size_t mbstowcs(wchar_t *pwcs, const char *s, size_t n);
size_t wcstombs(char *s, const wchar_t *pwcs, size_t n);
#endif
