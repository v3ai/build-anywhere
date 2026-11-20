/*
 * ba_stdio.c: buffered streams for the build-anywhere libc: FILE, fopen and
 * friends, character and block I/O, positioning, tmpfile and remove. The
 * formatted I/O (printf and scanf families) lives in ba_fmt.c.
 *
 * Part of build-anywhere.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define F_READ   1      /* opened for reading */
#define F_WRITE  2      /* opened for writing */
#define F_APPEND 4
#define F_EOF    8
#define F_ERR    16
#define F_OWNBUF 32     /* buf was malloc'ed by us */
#define F_STATIC 64     /* one of stdin, stdout, stderr: never freed */

struct __ba_file {
    int fd;
    int flags;
    int mode;           /* _IOFBF, _IOLBF or _IONBF */
    unsigned char *buf;
    size_t size;        /* buffer capacity */
    size_t pos;         /* read: next byte; write: bytes pending */
    size_t len;         /* read: bytes in buffer; 0 while writing */
    int writing;        /* buffer holds pending output */
    int unget;          /* pushed-back character, or EOF */
    unsigned char one;  /* buffer for unbuffered streams */
    struct __ba_file *next;
};

static unsigned char ba_inbuf[BUFSIZ], ba_outbuf[BUFSIZ];
static struct __ba_file ba_stdin = { 0, F_READ | F_STATIC, -1, ba_inbuf, BUFSIZ, 0, 0, 0, EOF, 0, 0 };
static struct __ba_file ba_stdout = { 1, F_WRITE | F_STATIC, -1, ba_outbuf, BUFSIZ, 0, 0, 0, EOF, 0, 0 };
static struct __ba_file ba_stderr = { 2, F_WRITE | F_STATIC, _IONBF, 0, 0, 0, 0, 0, EOF, 0, 0 };
FILE *stdin = &ba_stdin;
FILE *stdout = &ba_stdout;
FILE *stderr = &ba_stderr;
static FILE *ba_open_files;

static int write_all(int fd, const unsigned char *p, size_t n)
{
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

/* Write out pending output. */
static int flush_out(FILE *f)
{
    int r = 0;
    if (f->writing && f->pos > 0) {
        r = write_all(f->fd, f->buf, f->pos);
        if (r != 0)
            f->flags |= F_ERR;
    }
    f->pos = 0;
    f->writing = 0;
    return r;
}

/* stdout is line buffered on a terminal, fully buffered otherwise. */
static void decide_mode(FILE *f)
{
    if (f->mode < 0)
        f->mode = isatty(f->fd) ? _IOLBF : _IOFBF;
}

static int ensure_buf(FILE *f)
{
    if (f->buf == NULL) {
        if (f->mode == _IONBF) {
            f->buf = &f->one;
            f->size = 1;
        } else {
            f->buf = (unsigned char *)malloc(BUFSIZ);
            if (f->buf == NULL) {
                f->buf = &f->one;
                f->size = 1;
                f->mode = _IONBF;
            } else {
                f->size = BUFSIZ;
                f->flags |= F_OWNBUF;
            }
        }
    }
    return 0;
}

/* Called before reading: flush stdout when reading from a terminal-ish
   interactive stream, and switch the buffer from writing to reading. */
static int begin_read(FILE *f)
{
    if (!(f->flags & F_READ)) {
        f->flags |= F_ERR;
        errno = EBADF;
        return -1;
    }
    if (f->writing && flush_out(f) != 0)
        return -1;
    if (f == stdin && ba_stdout.writing)
        fflush(stdout);
    return 0;
}

static int begin_write(FILE *f)
{
    if (!(f->flags & F_WRITE)) {
        f->flags |= F_ERR;
        errno = EBADF;
        return -1;
    }
    if (!f->writing) {
        /* Drop read-ahead: move the descriptor back to the logical position. */
        if (f->len > f->pos || f->unget != EOF) {
            long back = (long)(f->len - f->pos) + (f->unget != EOF);
            lseek(f->fd, -back, SEEK_CUR);
        }
        f->pos = f->len = 0;
        f->unget = EOF;
        f->writing = 1;
    }
    decide_mode(f);
    ensure_buf(f);
    return 0;
}

static int refill(FILE *f)
{
    ssize_t n;
    decide_mode(f);
    ensure_buf(f);
    if (f->mode != _IOFBF)
        fflush(stdout);
    for (;;) {
        n = read(f->fd, f->buf, f->size);
        if (n >= 0 || errno != EINTR)
            break;
    }
    if (n <= 0) {
        f->flags |= n == 0 ? F_EOF : F_ERR;
        return EOF;
    }
    f->pos = 0;
    f->len = (size_t)n;
    return 0;
}

int fgetc(FILE *f)
{
    int c;
    if (f->unget != EOF) {
        c = f->unget;
        f->unget = EOF;
        return c;
    }
    if (f->pos >= f->len) {
        if (begin_read(f) != 0 || refill(f) != 0)
            return EOF;
    }
    return f->buf[f->pos++];
}

int getc(FILE *f) { return fgetc(f); }
int getchar(void) { return fgetc(stdin); }

int ungetc(int c, FILE *f)
{
    if (c == EOF || f->unget != EOF)
        return EOF;
    if (f->writing && flush_out(f) != 0)
        return EOF;
    f->unget = (unsigned char)c;
    f->flags &= ~F_EOF;
    return (unsigned char)c;
}

int fputc(int c, FILE *f)
{
    unsigned char ch = (unsigned char)c;
    if (begin_write(f) != 0)
        return EOF;
    if (f->pos >= f->size && flush_out(f) != 0)
        return EOF;
    f->writing = 1;
    f->buf[f->pos++] = ch;
    if (f->mode == _IONBF || (f->mode == _IOLBF && ch == '\n') || f->pos >= f->size) {
        if (flush_out(f) != 0)
            return EOF;
        f->writing = 1;
    }
    return ch;
}

int putc(int c, FILE *f) { return fputc(c, f); }
int putchar(int c) { return fputc(c, stdout); }

size_t fwrite(const void *p, size_t size, size_t n, FILE *f)
{
    const unsigned char *s = (const unsigned char *)p;
    size_t total = size * n, i;
    int nl = 0;

    if (total == 0)
        return 0;
    if (begin_write(f) != 0)
        return 0;
    if (f->mode == _IOLBF)
        for (i = 0; i < total; i++)
            if (s[i] == '\n')
                nl = 1;
    if (total >= f->size || f->mode == _IONBF) {
        /* Large or unbuffered write: send pending output, then the data. */
        if (flush_out(f) != 0 || write_all(f->fd, s, total) != 0) {
            f->flags |= F_ERR;
            return 0;
        }
        f->writing = 1;
        return n;
    }
    if (f->pos + total > f->size) {
        if (flush_out(f) != 0)
            return 0;
        f->writing = 1;
    }
    memcpy(f->buf + f->pos, s, total);
    f->pos += total;
    if (nl) {
        if (flush_out(f) != 0)
            return 0;
        f->writing = 1;
    }
    return n;
}

size_t fread(void *p, size_t size, size_t n, FILE *f)
{
    unsigned char *d = (unsigned char *)p;
    size_t total = size * n, got = 0;

    if (total == 0)
        return 0;
    if (f->unget != EOF) {
        d[got++] = (unsigned char)f->unget;
        f->unget = EOF;
    }
    while (got < total) {
        size_t avail;
        if (f->pos >= f->len) {
            if (begin_read(f) != 0)
                break;
            if (total - got >= BUFSIZ) {
                /* Read straight into the caller's memory. */
                ssize_t r = read(f->fd, d + got, total - got);
                if (r < 0 && errno == EINTR)
                    continue;
                if (r <= 0) {
                    f->flags |= r == 0 ? F_EOF : F_ERR;
                    break;
                }
                got += (size_t)r;
                continue;
            }
            if (refill(f) != 0)
                break;
        }
        avail = f->len - f->pos;
        if (avail > total - got)
            avail = total - got;
        memcpy(d + got, f->buf + f->pos, avail);
        f->pos += avail;
        got += avail;
    }
    return got / size;
}

char *fgets(char *s, int n, FILE *f)
{
    int i = 0, c;
    if (n <= 0)
        return NULL;
    while (i < n - 1) {
        c = fgetc(f);
        if (c == EOF)
            break;
        s[i++] = (char)c;
        if (c == '\n')
            break;
    }
    if (i == 0)
        return NULL;
    s[i] = '\0';
    return s;
}

int fputs(const char *s, FILE *f)
{
    size_t n = strlen(s);
    if (n > 0 && fwrite(s, 1, n, f) != n)
        return EOF;
    return 1;
}

int puts(const char *s)
{
    if (fputs(s, stdout) == EOF || fputc('\n', stdout) == EOF)
        return EOF;
    return 1;
}

int fflush(FILE *f)
{
    int r = 0;
    if (f == NULL) {
        FILE *g;
        r |= fflush(stdout);
        r |= fflush(stderr);
        for (g = ba_open_files; g != NULL; g = g->next)
            r |= fflush(g);
        return r ? EOF : 0;
    }
    if (f->writing)
        return flush_out(f) != 0 ? EOF : 0;
    if (f->flags & F_READ) {
        /* Discard read-ahead so the descriptor matches the stream position. */
        if (f->len > f->pos || f->unget != EOF) {
            long back = (long)(f->len - f->pos) + (f->unget != EOF);
            lseek(f->fd, -back, SEEK_CUR);
        }
        f->pos = f->len = 0;
        f->unget = EOF;
    }
    return 0;
}

static int parse_mode(const char *mode, int *rw)
{
    int plus = strchr(mode, '+') != NULL;
    switch (mode[0]) {
    case 'r':
        *rw = plus ? F_READ | F_WRITE : F_READ;
        return plus ? O_RDWR : O_RDONLY;
    case 'w':
        *rw = plus ? F_READ | F_WRITE : F_WRITE;
        return (plus ? O_RDWR : O_WRONLY) | O_CREAT | O_TRUNC;
    case 'a':
        *rw = (plus ? F_READ | F_WRITE : F_WRITE) | F_APPEND;
        return (plus ? O_RDWR : O_WRONLY) | O_CREAT | O_APPEND;
    }
    errno = EINVAL;
    return -1;
}

static FILE *new_file(int fd, int rw)
{
    FILE *f = (FILE *)calloc(1, sizeof *f);
    if (f == NULL)
        return NULL;
    f->fd = fd;
    f->flags = rw;
    f->mode = -1;
    f->unget = EOF;
    f->next = ba_open_files;
    ba_open_files = f;
    return f;
}

FILE *fdopen(int fd, const char *mode)
{
    int rw;
    if (parse_mode(mode, &rw) < 0)
        return NULL;
    return new_file(fd, rw);
}

FILE *fopen(const char *name, const char *mode)
{
    int rw, fd, flags = parse_mode(mode, &rw);
    FILE *f;
    if (flags < 0)
        return NULL;
    fd = open(name, flags | O_CLOEXEC, 0666);
    if (fd < 0)
        return NULL;
    f = new_file(fd, rw);
    if (f == NULL)
        close(fd);
    return f;
}

static void unlink_file(FILE *f)
{
    FILE **pp;
    for (pp = &ba_open_files; *pp != NULL; pp = &(*pp)->next)
        if (*pp == f) {
            *pp = f->next;
            break;
        }
}

int fclose(FILE *f)
{
    int r = fflush(f);
    if (close(f->fd) != 0)
        r = EOF;
    if (f->flags & F_OWNBUF)
        free(f->buf);
    if (f->flags & F_STATIC) {
        f->fd = -1;
        f->flags &= F_STATIC;
        f->buf = NULL;
        f->pos = f->len = 0;
    } else {
        unlink_file(f);
        free(f);
    }
    return r;
}

FILE *freopen(const char *name, const char *mode, FILE *f)
{
    int rw, fd, flags = parse_mode(mode, &rw);
    fflush(f);
    if (f->fd >= 0)
        close(f->fd);
    if (flags < 0 || name == NULL)
        return NULL;
    fd = open(name, flags, 0666);
    if (fd < 0)
        return NULL;
    if (f->fd >= 0 && fd != f->fd) {
        dup2(fd, f->fd);
        close(fd);
        fd = f->fd;
    }
    f->fd = fd;
    f->flags = (f->flags & (F_STATIC | F_OWNBUF)) | rw;
    f->pos = f->len = 0;
    f->writing = 0;
    f->unget = EOF;
    return f;
}

int fileno(FILE *f) { return f->fd; }
void clearerr(FILE *f) { f->flags &= ~(F_EOF | F_ERR); }
int feof(FILE *f) { return (f->flags & F_EOF) != 0; }
int ferror(FILE *f) { return (f->flags & F_ERR) != 0; }

int fseek(FILE *f, long off, int whence)
{
    if (f->writing) {
        if (flush_out(f) != 0)
            return -1;
    } else if (whence == SEEK_CUR) {
        off -= (long)(f->len - f->pos) + (f->unget != EOF);
    }
    f->pos = f->len = 0;
    f->unget = EOF;
    if (lseek(f->fd, off, whence) < 0)
        return -1;
    f->flags &= ~F_EOF;
    return 0;
}

long ftell(FILE *f)
{
    long p = (long)lseek(f->fd, 0, SEEK_CUR);
    if (p < 0)
        return -1;
    if (f->writing)
        return p + (long)f->pos;
    return p - (long)(f->len - f->pos) - (f->unget != EOF);
}

void rewind(FILE *f)
{
    fseek(f, 0L, SEEK_SET);
    clearerr(f);
}

int fgetpos(FILE *f, fpos_t *pos)
{
    long p = ftell(f);
    if (p < 0)
        return -1;
    *pos = p;
    return 0;
}

int fsetpos(FILE *f, const fpos_t *pos)
{
    return fseek(f, *pos, SEEK_SET) == 0 ? 0 : -1;
}

int setvbuf(FILE *f, char *buf, int mode, size_t size)
{
    if (mode != _IOFBF && mode != _IOLBF && mode != _IONBF)
        return -1;
    if (f->flags & F_OWNBUF)
        free(f->buf);
    f->flags &= ~F_OWNBUF;
    f->mode = mode;
    f->pos = f->len = 0;
    if (mode == _IONBF) {
        f->buf = &f->one;
        f->size = 1;
    } else if (buf != NULL && size > 0) {
        f->buf = (unsigned char *)buf;
        f->size = size;
    } else {
        f->buf = NULL;  /* allocated on first use */
        f->size = 0;
    }
    return 0;
}

void setbuf(FILE *f, char *buf)
{
    setvbuf(f, buf, buf != NULL ? _IOFBF : _IONBF, (size_t)BUFSIZ);
}

void perror(const char *s)
{
    const char *msg = strerror(errno);
    if (s != NULL && *s != '\0') {
        fputs(s, stderr);
        fputs(": ", stderr);
    }
    fputs(msg, stderr);
    fputc('\n', stderr);
}

int remove(const char *name)
{
    if (unlink(name) == 0)
        return 0;
    if (errno == EISDIR || errno == EPERM)
        return rmdir(name);
    return -1;
}

char *tmpnam(char *s)
{
    static char buf[L_tmpnam];
    static unsigned long counter;
    char *out = s != NULL ? s : buf;
    const char *dir = getenv("TMPDIR");
    int tries;

    if (dir == NULL || *dir == '\0' || strlen(dir) > L_tmpnam - 64)
        dir = "/tmp";
    for (tries = 0; tries < 1000; tries++) {
        sprintf(out, "%s/tmp.%lu.%lu", dir, (unsigned long)getpid(), counter++);
        if (access(out, F_OK) != 0)
            return out;
    }
    return NULL;
}

FILE *tmpfile(void)
{
    char name[L_tmpnam];
    int tries, fd;
    for (tries = 0; tries < 100; tries++) {
        if (tmpnam(name) == NULL)
            return NULL;
        fd = open(name, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (fd >= 0) {
            unlink(name);   /* the file lives until it is closed */
            return new_file(fd, F_READ | F_WRITE);
        }
        if (errno != EEXIST)
            return NULL;
    }
    return NULL;
}

/* Called by exit(). */
void __ba_stdio_exit(void)
{
    fflush(NULL);
}
