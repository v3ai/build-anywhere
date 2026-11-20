/* smoke.c: exercises the build-anywhere libc as a whole (its own startup,
   system calls, stdio, malloc, setjmp, signals). Prints "smoke: ok" and
   exits 0 when every check passes. */
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures;
#define CHECK(c) do { if (!(c)) { failures++; printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); } } while (0)

static jmp_buf jb;
static volatile sig_atomic_t got_sig;
static void on_sig(int s) { got_sig = s; }
static int cmp_int(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? -1 : x > y;
}
static void jump(int depth) { if (depth == 0) longjmp(jb, 42); else jump(depth - 1); }
static int atexit_ran;
static void at_exit_fn(void) { atexit_ran = 1; }

int main(int argc, char **argv)
{
    char buf[256], name[L_tmpnam];
    FILE *f;
    int i, n, *arr;
    void *ptrs[1000];
    double d;
    long l;
    char *end;
    time_t t;
    struct tm *tm;

    CHECK(argc >= 1 && argv[0] != NULL && argv[argc] == NULL);
    CHECK(getenv("PATH") != NULL);

    /* printf and friends */
    sprintf(buf, "%d %5.2f %s %x %e %g", -42, 3.14159, "str", 255, 1e-10, 0.1);
    CHECK(strcmp(buf, "-42  3.14 str ff 1.000000e-10 0.1") == 0);
    CHECK(snprintf(buf, 4, "%s", "abcdef") == 6 && strcmp(buf, "abc") == 0);

    /* files */
    CHECK(tmpnam(name) != NULL);
    f = fopen(name, "w+");
    CHECK(f != NULL);
    for (i = 0; i < 10000; i++)
        fprintf(f, "line %d\n", i);
    rewind(f);
    n = 0;
    while (fgets(buf, sizeof buf, f) != NULL)
        n++;
    CHECK(n == 10000 && feof(f));
    CHECK(fseek(f, 5, SEEK_SET) == 0 && fgetc(f) == '0' && ftell(f) == 6);
    CHECK(ungetc('X', f) == 'X' && fgetc(f) == 'X' && fgetc(f) == '\n');
    CHECK(fseek(f, 0, SEEK_END) == 0 && ftell(f) > 80000);
    CHECK(fclose(f) == 0);
    f = fopen(name, "r");
    CHECK(f != NULL && fscanf(f, "line %d", &i) == 1 && i == 0);
    fclose(f);
    f = fopen(name, "a");
    fputs("tail\n", f);
    fclose(f);
    f = fopen(name, "rb");
    fseek(f, -5, SEEK_END);
    CHECK(fread(buf, 1, 5, f) == 5 && memcmp(buf, "tail\n", 5) == 0);
    fclose(f);
    CHECK(remove(name) == 0 && fopen(name, "r") == NULL && errno == ENOENT);
    f = tmpfile();
    CHECK(f != NULL && fwrite("hello", 1, 5, f) == 5);
    rewind(f);
    CHECK(fread(buf, 1, 10, f) == 5 && memcmp(buf, "hello", 5) == 0);
    fclose(f);

    /* malloc */
    for (i = 0; i < 1000; i++) {
        ptrs[i] = malloc((size_t)(i * 37 % 5000 + 1));
        CHECK(ptrs[i] != NULL && ((size_t)ptrs[i] & 15) == 0);
        memset(ptrs[i], i & 255, (size_t)(i * 37 % 5000 + 1));
    }
    for (i = 0; i < 1000; i += 2)
        free(ptrs[i]);
    for (i = 1; i < 1000; i += 2)
        CHECK(((unsigned char *)ptrs[i])[0] == (i & 255));
    arr = (int *)malloc(10 * sizeof(int));
    for (i = 0; i < 10; i++)
        arr[i] = i;
    arr = (int *)realloc(arr, 3000000 * sizeof(int));
    CHECK(arr != NULL && arr[9] == 9);
    for (i = 0; i < 3000000; i++)
        arr[i] = (int)((i * 7919L) % 3000017);
    qsort(arr, 3000000, sizeof(int), cmp_int);
    for (i = 1; i < 3000000; i++)
        if (arr[i - 1] > arr[i])
            break;
    CHECK(i == 3000000);
    free(arr);
    arr = (int *)calloc(100, sizeof(int));
    CHECK(arr[0] == 0 && arr[99] == 0);
    free(arr);

    /* conversions */
    CHECK(strtol("  -0x1f", &end, 0) == -31 && *end == '\0');
    CHECK(strtol("077", NULL, 0) == 63);
    errno = 0;
    l = strtol("99999999999999999999", NULL, 10);
    CHECK(l == LONG_MAX && errno == ERANGE);
    CHECK(strtoul("-1", NULL, 10) == ULONG_MAX);
    CHECK(strtoull("18446744073709551615", NULL, 10) == 18446744073709551615ULL);
    CHECK(atoi("123abc") == 123);
    d = strtod("2.5e3x", &end);
    CHECK(d == 2500.0 && *end == 'x');
    CHECK(sqrt(2.0) * sqrt(2.0) - 2.0 < 1e-15 && fabs(pow(2.0, 10.0) - 1024.0) == 0.0);

    /* strings and ctype */
    CHECK(strcmp(strerror(ENOENT), "No such file or directory") == 0);
    CHECK(strstr("hello world", "o w") != NULL && strpbrk("abc", "xc") != NULL);
    CHECK(isalpha('a') && !isalpha('1') && toupper('q') == 'Q' && isspace('\n'));
    strcpy(buf, "a,b,,c");
    CHECK(strcmp(strtok(buf, ","), "a") == 0 && strcmp(strtok(NULL, ","), "b") == 0);
    memmove(buf + 1, buf, 5);

    /* setjmp, signals */
    i = setjmp(jb);
    if (i == 0)
        jump(50);
    CHECK(i == 42);
    CHECK(signal(SIGUSR1, on_sig) != SIG_ERR);
    raise(SIGUSR1);
    CHECK(got_sig == SIGUSR1);

    /* environment, time, processes */
    CHECK(setenv("BA_SMOKE", "yes", 1) == 0 && strcmp(getenv("BA_SMOKE"), "yes") == 0);
    t = time(NULL);
    CHECK(t > 1600000000L);
    tm = gmtime(&t);
    CHECK(tm != NULL && tm->tm_year >= 120);
    CHECK(strftime(buf, sizeof buf, "%Y-%m-%d", tm) == 10);
    CHECK(clock() >= 0);
    CHECK(system("exit 3") == 3 << 8);
    CHECK(system("test \"$BA_SMOKE\" = yes") == 0);
    CHECK(setlocale(LC_ALL, "") != NULL || setlocale(LC_ALL, "C") != NULL);
    assert(failures == 0);
    atexit(at_exit_fn);

    printf("smoke: %s\n", failures == 0 ? "ok" : "FAILED");
    return failures != 0;
}
