/*
 * ba_linux.c: the operating-system layer of the build-anywhere libc, for
 * Linux on x86_64 and i386: system calls, setjmp/longjmp, signals and the
 * POSIX functions the rest of the library (and TinyCC) needs.
 *
 * Part of build-anywhere. Compiled by TinyCC: the assembly below uses its
 * GNU-compatible assembler.
 */
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>

int errno;
char **environ;

long __ba_syscall(long n, long a, long b, long c, long d, long e, long f);
void __ba_restore_rt(void);

#if defined(__x86_64__)

__asm__(
    ".text\n"
    ".globl __ba_syscall\n"
    "__ba_syscall:\n"
    "  mov %rdi, %rax\n"
    "  mov %rsi, %rdi\n"
    "  mov %rdx, %rsi\n"
    "  mov %rcx, %rdx\n"
    "  mov %r8, %r10\n"
    "  mov %r9, %r8\n"
    "  mov 8(%rsp), %r9\n"
    "  syscall\n"
    "  ret\n"
    ".globl __ba_restore_rt\n"
    "__ba_restore_rt:\n"
    "  mov $15, %rax\n"             /* rt_sigreturn */
    "  syscall\n"
    ".globl setjmp\n"
    "setjmp:\n"
    "  mov %rbx, (%rdi)\n"
    "  mov %rbp, 8(%rdi)\n"
    "  mov %r12, 16(%rdi)\n"
    "  mov %r13, 24(%rdi)\n"
    "  mov %r14, 32(%rdi)\n"
    "  mov %r15, 40(%rdi)\n"
    "  lea 8(%rsp), %rdx\n"
    "  mov %rdx, 48(%rdi)\n"
    "  mov (%rsp), %rdx\n"
    "  mov %rdx, 56(%rdi)\n"
    "  xor %eax, %eax\n"
    "  ret\n"
    ".globl longjmp\n"
    "longjmp:\n"
    "  mov %esi, %eax\n"
    "  test %eax, %eax\n"
    "  jnz __ba_longjmp_go\n"
    "  inc %eax\n"
    "__ba_longjmp_go:\n"
    "  mov (%rdi), %rbx\n"
    "  mov 8(%rdi), %rbp\n"
    "  mov 16(%rdi), %r12\n"
    "  mov 24(%rdi), %r13\n"
    "  mov 32(%rdi), %r14\n"
    "  mov 40(%rdi), %r15\n"
    "  mov 48(%rdi), %rsp\n"
    "  jmp *56(%rdi)\n"
);

#define NR_read 0
#define NR_write 1
#define NR_open 2
#define NR_close 3
#define NR_lseek 8
#define NR_mmap 9
#define NR_mprotect 10
#define NR_munmap 11
#define NR_brk 12
#define NR_rt_sigaction 13
#define NR_ioctl 16
#define NR_access 21
#define NR_pipe 22
#define NR_dup 32
#define NR_dup2 33
#define NR_nanosleep 35
#define NR_getpid 39
#define NR_fork 57
#define NR_execve 59
#define NR_wait4 61
#define NR_kill 62
#define NR_fcntl 72
#define NR_getcwd 79
#define NR_chdir 80
#define NR_rename 82
#define NR_mkdir 83
#define NR_rmdir 84
#define NR_unlink 87
#define NR_readlink 89
#define NR_chmod 90
#define NR_umask 95
#define NR_gettimeofday 96
#define NR_time 201
#define NR_clock_gettime 228
#define NR_exit_group 231
#define BA_O_LARGEFILE 0

#elif defined(__i386__)

__asm__(
    ".text\n"
    ".globl __ba_syscall\n"
    "__ba_syscall:\n"
    "  push %ebp\n"
    "  push %edi\n"
    "  push %esi\n"
    "  push %ebx\n"
    "  mov 20(%esp), %eax\n"
    "  mov 24(%esp), %ebx\n"
    "  mov 28(%esp), %ecx\n"
    "  mov 32(%esp), %edx\n"
    "  mov 36(%esp), %esi\n"
    "  mov 40(%esp), %edi\n"
    "  mov 44(%esp), %ebp\n"
    "  int $0x80\n"
    "  pop %ebx\n"
    "  pop %esi\n"
    "  pop %edi\n"
    "  pop %ebp\n"
    "  ret\n"
    /* Without SA_SIGINFO the kernel builds a legacy (non-rt) signal frame
       on i386, which sigreturn undoes once the signal number is popped. */
    ".globl __ba_restore_rt\n"
    "__ba_restore_rt:\n"
    "  pop %eax\n"
    "  mov $119, %eax\n"            /* sigreturn */
    "  int $0x80\n"
    ".globl setjmp\n"
    "setjmp:\n"
    "  mov 4(%esp), %eax\n"
    "  mov %ebx, (%eax)\n"
    "  mov %esi, 4(%eax)\n"
    "  mov %edi, 8(%eax)\n"
    "  mov %ebp, 12(%eax)\n"
    "  lea 4(%esp), %ecx\n"
    "  mov %ecx, 16(%eax)\n"
    "  mov (%esp), %ecx\n"
    "  mov %ecx, 20(%eax)\n"
    "  xor %eax, %eax\n"
    "  ret\n"
    ".globl longjmp\n"
    "longjmp:\n"
    "  mov 4(%esp), %edx\n"
    "  mov 8(%esp), %eax\n"
    "  test %eax, %eax\n"
    "  jnz __ba_longjmp_go\n"
    "  inc %eax\n"
    "__ba_longjmp_go:\n"
    "  mov (%edx), %ebx\n"
    "  mov 4(%edx), %esi\n"
    "  mov 8(%edx), %edi\n"
    "  mov 12(%edx), %ebp\n"
    "  mov 16(%edx), %esp\n"
    "  jmp *20(%edx)\n"
);

#define NR_read 3
#define NR_write 4
#define NR_open 5
#define NR_close 6
#define NR_lseek 19
#define NR_mmap 192         /* mmap2: offset in 4096-byte pages */
#define NR_mprotect 125
#define NR_munmap 91
#define NR_brk 45
#define NR_rt_sigaction 174
#define NR_ioctl 54
#define NR_access 33
#define NR_pipe 42
#define NR_dup 41
#define NR_dup2 63
#define NR_nanosleep 162
#define NR_getpid 20
#define NR_fork 2
#define NR_execve 11
#define NR_wait4 114
#define NR_kill 37
#define NR_fcntl 55
#define NR_getcwd 183
#define NR_chdir 12
#define NR_rename 38
#define NR_mkdir 39
#define NR_rmdir 40
#define NR_unlink 10
#define NR_readlink 85
#define NR_chmod 15
#define NR_umask 60
#define NR_gettimeofday 78
#define NR_time 13
#define NR_clock_gettime 265
#define NR_exit_group 252
#define BA_O_LARGEFILE 0100000

#else
#error "build-anywhere libc supports Linux on x86_64 and i386 only"
#endif

/* Turn a raw system call result into the C convention. */
static long sysret(long r)
{
    if (r < 0 && r > -4096) {
        errno = (int)-r;
        return -1;
    }
    return r;
}

#define SYS0(n)             sysret(__ba_syscall(n, 0, 0, 0, 0, 0, 0))
#define SYS1(n, a)          sysret(__ba_syscall(n, (long)(a), 0, 0, 0, 0, 0))
#define SYS2(n, a, b)       sysret(__ba_syscall(n, (long)(a), (long)(b), 0, 0, 0, 0))
#define SYS3(n, a, b, c)    sysret(__ba_syscall(n, (long)(a), (long)(b), (long)(c), 0, 0, 0))
#define SYS4(n, a, b, c, d) sysret(__ba_syscall(n, (long)(a), (long)(b), (long)(c), (long)(d), 0, 0))

ssize_t read(int fd, void *buf, size_t n) { return SYS3(NR_read, fd, buf, n); }
ssize_t write(int fd, const void *buf, size_t n) { return SYS3(NR_write, fd, buf, n); }
int close(int fd) { return (int)SYS1(NR_close, fd); }
off_t lseek(int fd, off_t off, int whence) { return SYS3(NR_lseek, fd, off, whence); }
int unlink(const char *path) { return (int)SYS1(NR_unlink, path); }
int rmdir(const char *path) { return (int)SYS1(NR_rmdir, path); }
int access(const char *path, int mode) { return (int)SYS2(NR_access, path, mode); }
int chdir(const char *path) { return (int)SYS1(NR_chdir, path); }
int dup(int fd) { return (int)SYS1(NR_dup, fd); }
int dup2(int fd, int fd2) { return (int)SYS2(NR_dup2, fd, fd2); }
int pipe(int fds[2]) { return (int)SYS1(NR_pipe, fds); }
pid_t getpid(void) { return (pid_t)SYS0(NR_getpid); }
pid_t fork(void) { return (pid_t)SYS0(NR_fork); }
int kill(int pid, int sig) { return (int)SYS2(NR_kill, pid, sig); }
int rename(const char *from, const char *to) { return (int)SYS2(NR_rename, from, to); }
int mkdir(const char *path, mode_t mode) { return (int)SYS2(NR_mkdir, path, mode); }
int chmod(const char *path, mode_t mode) { return (int)SYS2(NR_chmod, path, mode); }
mode_t umask(mode_t mask) { return (mode_t)SYS1(NR_umask, mask); }
ssize_t readlink(const char *path, char *buf, size_t size) { return SYS3(NR_readlink, path, buf, size); }
int mprotect(void *addr, size_t len, int prot) { return (int)SYS3(NR_mprotect, addr, len, prot); }
int munmap(void *addr, size_t len) { return (int)SYS2(NR_munmap, addr, len); }
int execve(const char *path, char *const argv[], char *const envp[])
{
    return (int)SYS3(NR_execve, path, argv, envp);
}
int clock_gettime(int clk, struct timespec *ts) { return (int)SYS2(NR_clock_gettime, clk, ts); }
int gettimeofday(struct timeval *tv, void *tz) { return (int)SYS2(NR_gettimeofday, tv, tz); }
int nanosleep(const struct timespec *req, struct timespec *rem) { return (int)SYS2(NR_nanosleep, req, rem); }

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
#if defined(__i386__)
    off /= 4096;
#endif
    return (void *)sysret(__ba_syscall(NR_mmap, (long)addr, (long)len, (long)prot,
                                       (long)flags, (long)fd, (long)off));
}

int open(const char *path, int flags, ...)
{
    va_list ap;
    int mode;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
    return (int)SYS3(NR_open, path, flags | BA_O_LARGEFILE, mode);
}

int creat(const char *path, mode_t mode)
{
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
}

int fcntl(int fd, int cmd, ...)
{
    va_list ap;
    long arg;
    va_start(ap, cmd);
    arg = va_arg(ap, long);
    va_end(ap);
    return (int)SYS3(NR_fcntl, fd, cmd, arg);
}

int isatty(int fd)
{
    char termios[64];
    return SYS3(NR_ioctl, fd, 0x5401 /* TCGETS */, termios) == 0;
}

char *getcwd(char *buf, size_t size)
{
    if (SYS2(NR_getcwd, buf, size) < 0)
        return NULL;
    return buf;
}

time_t time(time_t *t)
{
    time_t now = (time_t)SYS1(NR_time, 0);
    if (t != NULL)
        *t = now;
    return now;
}

clock_t clock(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) != 0)
        return (clock_t)-1;
    return (clock_t)(ts.tv_sec * 1000000L + ts.tv_nsec / 1000L);
}

unsigned int sleep(unsigned int seconds)
{
    struct timespec req, rem;
    req.tv_sec = (time_t)seconds;
    req.tv_nsec = 0;
    if (nanosleep(&req, &rem) != 0)
        return (unsigned int)rem.tv_sec;
    return 0;
}

pid_t waitpid(pid_t pid, int *status, int options)
{
    return (pid_t)SYS4(NR_wait4, pid, status, options, 0);
}

pid_t wait(int *status)
{
    return waitpid(-1, status, 0);
}

void _exit(int status)
{
    for (;;)
        __ba_syscall(NR_exit_group, status, 0, 0, 0, 0, 0);
}

/* Heap growth for malloc. Returns the new break, or the old one on failure. */
void *__ba_brk(void *addr)
{
    return (void *)__ba_syscall(NR_brk, (long)addr, 0, 0, 0, 0, 0);
}

int execv(const char *path, char *const argv[])
{
    return execve(path, argv, environ);
}

int execvp(const char *file, char *const argv[])
{
    const char *path, *p, *colon;
    char buf[4096];
    size_t dlen, flen;
    int saved = ENOENT;

    if (strchr(file, '/') != NULL)
        return execve(file, argv, environ);
    path = NULL;
    if (environ != NULL) {
        char **e;
        for (e = environ; *e != NULL; e++)
            if (strncmp(*e, "PATH=", 5) == 0)
                path = *e + 5;
    }
    if (path == NULL)
        path = "/usr/local/bin:/bin:/usr/bin";
    flen = strlen(file);
    for (p = path;; p = colon + 1) {
        colon = strchr(p, ':');
        dlen = colon != NULL ? (size_t)(colon - p) : strlen(p);
        if (dlen + flen + 2 <= sizeof buf) {
            memcpy(buf, p, dlen);
            if (dlen == 0)
                buf[dlen++] = '.';
            buf[dlen] = '/';
            memcpy(buf + dlen + 1, file, flen + 1);
            execve(buf, argv, environ);
            if (errno != ENOENT)
                saved = errno;
        }
        if (colon == NULL)
            break;
    }
    errno = saved;
    return -1;
}

/* ---- signals -------------------------------------------------------- */

struct ba_ksigaction {
    void (*handler)(int);
    unsigned long flags;
    void (*restorer)(void);
    unsigned long mask[8 / sizeof(unsigned long)];
};

#define BA_SA_RESTORER 0x04000000UL
#define BA_SA_RESTART  0x10000000UL

void (*signal(int sig, void (*func)(int)))(int)
{
    struct ba_ksigaction sa, old;
    memset(&sa, 0, sizeof sa);
    memset(&old, 0, sizeof old);
    sa.handler = func;
    sa.flags = BA_SA_RESTORER | BA_SA_RESTART;
    sa.restorer = __ba_restore_rt;
    if (sysret(__ba_syscall(NR_rt_sigaction, sig, (long)&sa, (long)&old, 8, 0, 0)) < 0)
        return SIG_ERR;
    return old.handler;
}

int raise(int sig)
{
    return kill(getpid(), sig);
}
