/* stdio.h: build-anywhere libc. */
#ifndef _BA_STDIO_H
#define _BA_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct __ba_file FILE;
typedef long fpos_t;
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;
#define EOF (-1)
#define BUFSIZ 8192
#define FILENAME_MAX 4096
#define FOPEN_MAX 1000
#define L_tmpnam 256
#define TMP_MAX 238328
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
FILE *fopen(const char *name, const char *mode);
FILE *freopen(const char *name, const char *mode, FILE *f);
FILE *fdopen(int fd, const char *mode);
int fclose(FILE *f);
int fflush(FILE *f);
int fileno(FILE *f);
void setbuf(FILE *f, char *buf);
int setvbuf(FILE *f, char *buf, int mode, size_t size);
int fprintf(FILE *f, const char *fmt, ...);
int printf(const char *fmt, ...);
int sprintf(char *s, const char *fmt, ...);
int snprintf(char *s, size_t n, const char *fmt, ...);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vprintf(const char *fmt, va_list ap);
int vsprintf(char *s, const char *fmt, va_list ap);
int vsnprintf(char *s, size_t n, const char *fmt, va_list ap);
int fscanf(FILE *f, const char *fmt, ...);
int scanf(const char *fmt, ...);
int sscanf(const char *s, const char *fmt, ...);
int vfscanf(FILE *f, const char *fmt, va_list ap);
int vscanf(const char *fmt, va_list ap);
int vsscanf(const char *s, const char *fmt, va_list ap);
int fgetc(FILE *f);
char *fgets(char *s, int n, FILE *f);
int fputc(int c, FILE *f);
int fputs(const char *s, FILE *f);
int getc(FILE *f);
int getchar(void);
int putc(int c, FILE *f);
int putchar(int c);
int puts(const char *s);
int ungetc(int c, FILE *f);
size_t fread(void *p, size_t size, size_t n, FILE *f);
size_t fwrite(const void *p, size_t size, size_t n, FILE *f);
int fgetpos(FILE *f, fpos_t *pos);
int fseek(FILE *f, long off, int whence);
int fsetpos(FILE *f, const fpos_t *pos);
long ftell(FILE *f);
void rewind(FILE *f);
void clearerr(FILE *f);
int feof(FILE *f);
int ferror(FILE *f);
void perror(const char *s);
int remove(const char *name);
int rename(const char *from, const char *to);
FILE *tmpfile(void);
char *tmpnam(char *s);
#endif
