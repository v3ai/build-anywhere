/*
 * ba_time.c: the C89 <time.h> conversions (gmtime, localtime, mktime,
 * asctime, ctime, strftime, difftime).
 *
 * Part of build-anywhere. There is no time zone database, so local time is
 * UTC. Dates use the proleptic Gregorian calendar (H. Hinnant's algorithms).
 */
#include <stddef.h>
#include <time.h>

static struct tm ba_tm;
static char ba_asc[32];

static const char *const wday_name[7] = {
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};
static const char *const mon_name[12] = {
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"
};

static long floor_div(long a, long b)
{
    long q = a / b, r = a % b;
    if (r != 0 && ((r < 0) != (b < 0)))
        q--;
    return q;
}

/* Days since 1970-01-01 of a Gregorian date (m is 1-12). */
static long days_from_civil(long y, long m, long d)
{
    long era, yoe, doy, doe;
    y -= m <= 2;
    era = floor_div(y, 400L);
    yoe = y - era * 400L;
    doy = (153L * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    doe = yoe * 365L + yoe / 4 - yoe / 100 + doy;
    return era * 146097L + doe - 719468L;
}

static void civil_from_days(long z, long *y, long *m, long *d)
{
    long era, doe, yoe, doy, mp;
    z += 719468L;
    era = floor_div(z, 146097L);
    doe = z - era * 146097L;
    yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    *y = yoe + era * 400L;
    doy = doe - (365L * yoe + yoe / 4 - yoe / 100);
    mp = (5 * doy + 2) / 153;
    *d = doy - (153 * mp + 2) / 5 + 1;
    *m = mp < 10 ? mp + 3 : mp - 9;
    *y += *m <= 2;
}

static void fill_tm(struct tm *tm, long days, long secs)
{
    long y, m, d;
    civil_from_days(days, &y, &m, &d);
    tm->tm_year = (int)(y - 1900);
    tm->tm_mon = (int)(m - 1);
    tm->tm_mday = (int)d;
    tm->tm_hour = (int)(secs / 3600);
    tm->tm_min = (int)(secs / 60 % 60);
    tm->tm_sec = (int)(secs % 60);
    tm->tm_wday = (int)((days % 7 + 11) % 7);        /* 1970-01-01 was a Thursday */
    tm->tm_yday = (int)(days - days_from_civil(y, 1L, 1L));
    tm->tm_isdst = 0;
}

struct tm *gmtime(const time_t *t)
{
    long v = (long)*t;
    long days = floor_div(v, 86400L);
    fill_tm(&ba_tm, days, v - days * 86400L);
    return &ba_tm;
}

struct tm *localtime(const time_t *t)
{
    return gmtime(t);
}

time_t mktime(struct tm *tm)
{
    long y, mon, days, secs;

    /* Normalize months into the year first, then everything into seconds. */
    y = (long)tm->tm_year + 1900L;
    mon = tm->tm_mon;
    y += floor_div(mon, 12L);
    mon -= floor_div(mon, 12L) * 12L;
    days = days_from_civil(y, mon + 1, 1L) + (long)tm->tm_mday - 1;
    secs = (long)tm->tm_hour * 3600L + (long)tm->tm_min * 60L + (long)tm->tm_sec;
    days += floor_div(secs, 86400L);
    secs -= floor_div(secs, 86400L) * 86400L;
    fill_tm(tm, days, secs);
    return (time_t)(days * 86400L + secs);
}

double difftime(time_t t1, time_t t0)
{
    return (double)t1 - (double)t0;
}

static char *put2(char *p, int v)
{
    *p++ = (char)('0' + v / 10 % 10);
    *p++ = (char)('0' + v % 10);
    return p;
}

static char *put_num(char *p, long v, int width, char pad)
{
    char tmp[24];
    int n = 0, neg = v < 0;
    unsigned long u = neg ? 0UL - (unsigned long)v : (unsigned long)v;
    do {
        tmp[n++] = (char)('0' + (int)(u % 10UL));
        u /= 10UL;
    } while (u != 0);
    if (neg)
        *p++ = '-';
    while (width-- > n)
        *p++ = pad;
    while (n > 0)
        *p++ = tmp[--n];
    return p;
}

static char *put_str(char *p, const char *s, int n)
{
    while (*s != '\0' && n-- != 0)
        *p++ = *s++;
    return p;
}

char *asctime(const struct tm *tm)
{
    char *p = ba_asc;
    p = put_str(p, wday_name[(tm->tm_wday % 7 + 7) % 7], 3);
    *p++ = ' ';
    p = put_str(p, mon_name[(tm->tm_mon % 12 + 12) % 12], 3);
    *p++ = ' ';
    p = put_num(p, (long)tm->tm_mday, 2, ' ');
    *p++ = ' ';
    p = put2(p, tm->tm_hour);
    *p++ = ':';
    p = put2(p, tm->tm_min);
    *p++ = ':';
    p = put2(p, tm->tm_sec);
    *p++ = ' ';
    p = put_num(p, (long)tm->tm_year + 1900L, 0, '0');
    *p++ = '\n';
    *p = '\0';
    return ba_asc;
}

char *ctime(const time_t *t)
{
    return asctime(localtime(t));
}

/* Week of the year (00-53) whose weeks start on `first` (0 = Sunday). */
static int week_number(const struct tm *tm, int first)
{
    int wd = (tm->tm_wday - first + 7) % 7;
    return (tm->tm_yday + 7 - wd) / 7;
}

size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm)
{
    char tmp[64], *p;
    size_t n = 0, len;
    int h12;

    if (max == 0)
        return 0;
    for (; *fmt != '\0'; fmt++) {
        p = tmp;
        if (*fmt != '%') {
            *p++ = *fmt;
        } else {
            fmt++;
            if (*fmt == 'E' || *fmt == 'O')     /* C99 modifiers: ignore */
                fmt++;
            h12 = tm->tm_hour % 12 == 0 ? 12 : tm->tm_hour % 12;
            switch (*fmt) {
            case 'a': p = put_str(p, wday_name[(tm->tm_wday % 7 + 7) % 7], 3); break;
            case 'A': p = put_str(p, wday_name[(tm->tm_wday % 7 + 7) % 7], -1); break;
            case 'b': case 'h':
                      p = put_str(p, mon_name[(tm->tm_mon % 12 + 12) % 12], 3); break;
            case 'B': p = put_str(p, mon_name[(tm->tm_mon % 12 + 12) % 12], -1); break;
            case 'c':
                p = put_str(p, wday_name[(tm->tm_wday % 7 + 7) % 7], 3);
                *p++ = ' ';
                p = put_str(p, mon_name[(tm->tm_mon % 12 + 12) % 12], 3);
                *p++ = ' ';
                p = put_num(p, (long)tm->tm_mday, 2, ' ');
                *p++ = ' ';
                p = put2(p, tm->tm_hour); *p++ = ':';
                p = put2(p, tm->tm_min); *p++ = ':';
                p = put2(p, tm->tm_sec); *p++ = ' ';
                p = put_num(p, (long)tm->tm_year + 1900L, 0, '0');
                break;
            case 'd': p = put2(p, tm->tm_mday); break;
            case 'e': p = put_num(p, (long)tm->tm_mday, 2, ' '); break;
            case 'D': case 'x':
                p = put2(p, tm->tm_mon + 1); *p++ = '/';
                p = put2(p, tm->tm_mday); *p++ = '/';
                p = put2(p, (tm->tm_year % 100 + 100) % 100);
                break;
            case 'F':
                p = put_num(p, (long)tm->tm_year + 1900L, 4, '0'); *p++ = '-';
                p = put2(p, tm->tm_mon + 1); *p++ = '-';
                p = put2(p, tm->tm_mday);
                break;
            case 'H': p = put2(p, tm->tm_hour); break;
            case 'I': p = put2(p, h12); break;
            case 'j': p = put_num(p, (long)tm->tm_yday + 1L, 3, '0'); break;
            case 'm': p = put2(p, tm->tm_mon + 1); break;
            case 'M': p = put2(p, tm->tm_min); break;
            case 'n': *p++ = '\n'; break;
            case 't': *p++ = '\t'; break;
            case 'p': p = put_str(p, tm->tm_hour < 12 ? "AM" : "PM", -1); break;
            case 'r':
                p = put2(p, h12); *p++ = ':';
                p = put2(p, tm->tm_min); *p++ = ':';
                p = put2(p, tm->tm_sec); *p++ = ' ';
                p = put_str(p, tm->tm_hour < 12 ? "AM" : "PM", -1);
                break;
            case 'R':
                p = put2(p, tm->tm_hour); *p++ = ':';
                p = put2(p, tm->tm_min);
                break;
            case 'S': p = put2(p, tm->tm_sec); break;
            case 'T': case 'X':
                p = put2(p, tm->tm_hour); *p++ = ':';
                p = put2(p, tm->tm_min); *p++ = ':';
                p = put2(p, tm->tm_sec);
                break;
            case 'u': p = put_num(p, (long)(tm->tm_wday == 0 ? 7 : tm->tm_wday), 1, '0'); break;
            case 'w': p = put_num(p, (long)tm->tm_wday, 1, '0'); break;
            case 'U': p = put2(p, week_number(tm, 0)); break;
            case 'W': p = put2(p, week_number(tm, 1)); break;
            case 'y': p = put2(p, (tm->tm_year % 100 + 100) % 100); break;
            case 'C': p = put2(p, (int)(((long)tm->tm_year + 1900L) / 100L)); break;
            case 'Y': p = put_num(p, (long)tm->tm_year + 1900L, 0, '0'); break;
            case 'z': p = put_str(p, "+0000", -1); break;
            case 'Z': p = put_str(p, "UTC", -1); break;
            case '%': *p++ = '%'; break;
            case '\0': fmt--; break;
            default: *p++ = '%'; *p++ = *fmt; break;
            }
        }
        len = (size_t)(p - tmp);
        if (n + len >= max)
            return 0;
        for (p = tmp; len > 0; len--)
            s[n++] = *p++;
    }
    s[n] = '\0';
    return n;
}
