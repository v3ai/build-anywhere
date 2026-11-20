/* stdlib.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_STDLIB_H
#define _BA_SH_STDLIB_H
#include <stddef.h>
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 32767
/* malloc, free and exit are built into pnut. */
void *calloc(int n, int size);
int atoi(char *s);
long atol(char *s);
long strtol(char *s, char **end, int base);
double atof(char *s);
double strtod(char *s, char **end);
int abs(int v);
long labs(long v);
int rand(void);
void srand(int seed);
void abort(void);
#endif
