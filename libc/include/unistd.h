/* unistd.h: build-anywhere libc (POSIX subset). */
#ifndef _BA_UNISTD_H
#define _BA_UNISTD_H
#include <sys/types.h>
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4
#ifndef SEEK_SET
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#endif
extern char **environ;
ssize_t read(int fd, void *buf, size_t n);
ssize_t write(int fd, const void *buf, size_t n);
int close(int fd);
off_t lseek(int fd, off_t off, int whence);
int unlink(const char *path);
int rmdir(const char *path);
int access(const char *path, int mode);
char *getcwd(char *buf, size_t size);
int chdir(const char *path);
int dup(int fd);
int dup2(int fd, int fd2);
int pipe(int fds[2]);
int isatty(int fd);
pid_t getpid(void);
pid_t fork(void);
int execve(const char *path, char *const argv[], char *const envp[]);
int execv(const char *path, char *const argv[]);
int execvp(const char *file, char *const argv[]);
void _exit(int status);
unsigned int sleep(unsigned int seconds);
ssize_t readlink(const char *path, char *buf, size_t size);
#endif
