/* time.h: build-anywhere libc. Local time is UTC (no time zone database). */
#ifndef _BA_TIME_H
#define _BA_TIME_H
#include <stddef.h>
typedef long time_t;
typedef long clock_t;
#define CLOCKS_PER_SEC 1000000L
struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
};
struct timespec {
    time_t tv_sec;
    long tv_nsec;
};
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define CLOCK_PROCESS_CPUTIME_ID 2
clock_t clock(void);
double difftime(time_t t1, time_t t0);
time_t mktime(struct tm *tm);
time_t time(time_t *t);
char *asctime(const struct tm *tm);
char *ctime(const time_t *t);
struct tm *gmtime(const time_t *t);
struct tm *localtime(const time_t *t);
size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm);
int clock_gettime(int clk, struct timespec *ts);
int nanosleep(const struct timespec *req, struct timespec *rem);
#endif
