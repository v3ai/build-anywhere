/* stdio.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_STDIO_H
#define _BA_SH_STDIO_H
#include <stddef.h>
/* A FILE is a file descriptor, as in pnut's runtime. */
typedef int FILE;
#define stdin ((FILE *)0)
#define stdout ((FILE *)1)
#define stderr ((FILE *)2)
#define EOF (-1)
#define BUFSIZ 1024
#define getc(f) fgetc(f)
/* printf, putchar, getchar, fopen, fclose and fgetc are built into pnut. */
int puts(char *s);
int fputs(char *s, FILE *f);
int fputc(int c, FILE *f);
int putc(int c, FILE *f);
char *fgets(char *s, int n, FILE *f);
int fflush(FILE *f);
#endif
