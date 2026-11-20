/*
 * test_libc.c: checks libc/ba_*.c against the host C library.
 *
 * The libc sources are compiled with rename.h, so every function they define
 * is called ba_<name> here and can be compared with the host's <name>.
 * Formatting and strtod must match exactly; math functions must be within
 * a few units in the last place (ULPs); exact functions must match bit for bit.
 *
 * Build and run: sh tests/libc/run.sh
 */
#define _GNU_SOURCE
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

double ba_fabs(double), ba_frexp(double, int *), ba_ldexp(double, int), ba_fmod(double, double);
double ba_floor(double), ba_ceil(double), ba_modf(double, double *), ba_sqrt(double);
double ba_exp(double), ba_log(double), ba_log10(double), ba_pow(double, double);
double ba_sin(double), ba_cos(double), ba_tan(double), ba_atan(double), ba_atan2(double, double);
double ba_asin(double), ba_acos(double), ba_sinh(double), ba_cosh(double), ba_tanh(double);
int ba_snprintf(char *, size_t, const char *, ...);
int ba_sprintf(char *, const char *, ...);
int ba_fprintf(FILE *, const char *, ...);
double ba_strtod(const char *, char **);
double ba_atof(const char *);
int ba_sscanf(const char *, const char *, ...);
struct tm *ba_gmtime(const time_t *);
time_t ba_mktime(struct tm *);
char *ba_asctime(const struct tm *);
size_t ba_strftime(char *, size_t, const char *, const struct tm *);
div_t ba_div(int, int);
ldiv_t ba_ldiv(long, long);
long ba_labs(long);
int ba_rand(void);
void ba_srand(unsigned);
void *ba_bsearch(const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
char *ba_strtok(char *, const char *);
size_t ba_strxfrm(char *, const char *, size_t);
char *ba_setlocale(int, const char *);
struct lconv *ba_localeconv(void);
int ba_mbtowc(wchar_t *, const char *, size_t);
int ba_wctomb(char *, wchar_t);

static long failures, checks;

static void fail(const char *fmt, ...)
{
    va_list ap;
    failures++;
    if (failures > 60)
        return;
    va_start(ap, fmt);
    fprintf(stderr, "FAIL: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

/* ---- random doubles ------------------------------------------------- */

static uint64_t rng = 0x9E3779B97F4A7C15ULL;

static uint64_t next64(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

static double from_bits(uint64_t b)
{
    double d;
    memcpy(&d, &b, sizeof d);
    return d;
}

static uint64_t to_bits(double d)
{
    uint64_t b;
    memcpy(&b, &d, sizeof b);
    return b;
}

/* A random finite double: any bit pattern except inf/nan. */
static double rand_double(void)
{
    double d;
    do d = from_bits(next64()); while (isnan(d) || isinf(d));
    return d;
}

/* Random double with a "human" magnitude (exponent in [-40, 40]). */
static double rand_human(void)
{
    double m = (double)(next64() >> 11) / 9007199254740992.0;
    int e = (int)(next64() % 81) - 40;
    double d = m * pow(10.0, e);
    return (next64() & 1) ? -d : d;
}

static int64_t ordered(double d)
{
    int64_t i;
    memcpy(&i, &d, sizeof i);
    return i < 0 ? INT64_MIN - i : i;
}

static double ulps(double got, double want)
{
    if (isnan(got) && isnan(want))
        return 0;
    if (isnan(got) || isnan(want))
        return 1e300;
    if (got == want)
        return 0;
    if (isinf(got) || isinf(want))
        return 1e300;
    return fabs((double)(ordered(got) - ordered(want)));
}

/* ---- printf --------------------------------------------------------- */

static void check_fmt_double(const char *fmt, double v)
{
    char a[2048], b[2048];
    int ra, rb;
    /* glibc prints "%#g" of values that round up to a new power of ten with
       too few digits (999999.5 -> "1.e+06"); C requires "1.00000e+06". */
    if (strncmp(fmt, "%#", 2) == 0 && strchr(fmt, 'g') != NULL)
        return;
    ra = snprintf(a, sizeof a, fmt, v);
    rb = ba_snprintf(b, sizeof b, fmt, v);
    checks++;
    if (ra != rb || strcmp(a, b) != 0)
        fail("printf(\"%s\", %.17g): host \"%s\" (%d), ours \"%s\" (%d)", fmt, v, a, ra, b, rb);
}

static void test_printf(void)
{
    static const char *ffmts[] = {
        "%f", "%.0f", "%.1f", "%.2f", "%.3f", "%.10f", "%.20f", "%.60f", "%e", "%.0e",
        "%.1e", "%.3e", "%.16e", "%.30e", "%E", "%g", "%.0g", "%.1g", "%.2g", "%.3g",
        "%.6g", "%.10g", "%.15g", "%.17g", "%.25g", "%#g", "%#.3g", "%#.0f", "%#.0e",
        "%10.4f", "%-12.3e|", "%+f", "% f", "%012.3f", "%-012.3f|", "%G", "%+.3e",
        "%20g", "%-20g|", "%020g", "%.400f", "%.1100f"
    };
    static const double fixed[] = {
        0.0, 1.0, -1.0, 0.5, 1.5, 2.5, 3.5, -2.5, 0.125, 0.375, 1e-5, 123456789.0, 1e100,
        1e-100, 1e300, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, 0.1, 0.2,
        0.3, 1.0 / 3.0, 2.0 / 3.0, 9.9999, 99.995, 0.000123456, 1e15, 1e16, 1e17, 1e21,
        1e22, 1e23, 4.35, 0.05, 0.15, 0.25, 0.35, 9.5, 10.5, 999999.5, 0.9999995, 1e-4,
        9.9999e-5, 123.456, 65536.0, 4294967296.0, 9007199254740993.0, 3.14159265358979
    };
    static const char *ifmts[] = {
        "%d", "%5d", "%-5d|", "%05d", "%+d", "% d", "%.3d", "%.0d", "%8.3d", "%-8.3d|",
        "%x", "%#x", "%#o", "%o", "%X", "%#X", "%u", "%#.0o", "%+05d", "%c", "%%"
    };
    static const long ivals[] = { 0, 1, -1, 7, 42, -42, 255, 256, 65535, -32768, 100000,
                                  2147483647L, -2147483647L - 1 };
    char a[512], b[512];
    size_t i, j;
    int ra, rb;
    double v;

    for (i = 0; i < sizeof ffmts / sizeof ffmts[0]; i++) {
        for (j = 0; j < sizeof fixed / sizeof fixed[0]; j++) {
            check_fmt_double(ffmts[i], fixed[j]);
            check_fmt_double(ffmts[i], -fixed[j]);
        }
        check_fmt_double(ffmts[i], INFINITY);
        check_fmt_double(ffmts[i], -INFINITY);
        check_fmt_double(ffmts[i], NAN);
        check_fmt_double(ffmts[i], -NAN);
        for (j = 0; j < 400; j++) {
            check_fmt_double(ffmts[i], rand_human());
            v = rand_double();
            if (strstr(ffmts[i], "1100") == NULL || fabs(v) < 1e30)
                check_fmt_double(ffmts[i], v);
        }
    }

    for (i = 0; i < sizeof ifmts / sizeof ifmts[0]; i++) {
        for (j = 0; j < sizeof ivals / sizeof ivals[0]; j++) {
            if (strchr("xXou", ifmts[i][strlen(ifmts[i]) - 1]) ||
                strstr(ifmts[i], "x") || strstr(ifmts[i], "X") || strstr(ifmts[i], "o")) {
                ra = snprintf(a, sizeof a, ifmts[i], (unsigned)ivals[j]);
                rb = ba_snprintf(b, sizeof b, ifmts[i], (unsigned)ivals[j]);
            } else if (strchr(ifmts[i], 'c')) {
                ra = snprintf(a, sizeof a, ifmts[i], (int)(ivals[j] & 127) + 32);
                rb = ba_snprintf(b, sizeof b, ifmts[i], (int)(ivals[j] & 127) + 32);
            } else {
                ra = snprintf(a, sizeof a, ifmts[i], (int)ivals[j]);
                rb = ba_snprintf(b, sizeof b, ifmts[i], (int)ivals[j]);
            }
            checks++;
            if (ra != rb || strcmp(a, b) != 0)
                fail("printf(\"%s\", %ld): host \"%s\", ours \"%s\"", ifmts[i], ivals[j], a, b);
        }
    }

#define SAME(call_a, call_b, desc) do { \
        ra = call_a; rb = call_b; checks++; \
        if (ra != rb || strcmp(a, b) != 0) \
            fail("%s: host \"%s\" (%d), ours \"%s\" (%d)", desc, a, ra, b, rb); \
    } while (0)

    SAME(snprintf(a, sizeof a, "%ld|%lu|%lx|%li", -9876543210L, 18446744073709551615UL, 0xdeadbeefcafeUL, LONG_MIN),
         ba_snprintf(b, sizeof b, "%ld|%lu|%lx|%li", -9876543210L, 18446744073709551615UL, 0xdeadbeefcafeUL, LONG_MIN), "long");
    SAME(snprintf(a, sizeof a, "%lld|%llu", -123456789012345LL, 18446744073709551615ULL),
         ba_snprintf(b, sizeof b, "%lld|%llu", -123456789012345LL, 18446744073709551615ULL), "long long");
    SAME(snprintf(a, sizeof a, "%hd|%hu|%hhd|%hhu", 70000, 70000, 300, 300),
         ba_snprintf(b, sizeof b, "%hd|%hu|%hhd|%hhu", 70000, 70000, 300, 300), "short/char");
    SAME(snprintf(a, sizeof a, "[%s][%10s][%-10s][%.3s][%10.2s][%s]", "hello", "hi", "hi", "hello", "hello", ""),
         ba_snprintf(b, sizeof b, "[%s][%10s][%-10s][%.3s][%10.2s][%s]", "hello", "hi", "hi", "hello", "hello", ""), "strings");
    SAME(snprintf(a, sizeof a, "%*d|%-*d|%.*f|%*.*e", 6, 42, 6, 42, 3, 3.14159, 12, 2, 31415.9),
         ba_snprintf(b, sizeof b, "%*d|%-*d|%.*f|%*.*e", 6, 42, 6, 42, 3, 3.14159, 12, 2, 31415.9), "star");
    SAME(snprintf(a, sizeof a, "%*d|%.*d", -6, 42, -3, 42),
         ba_snprintf(b, sizeof b, "%*d|%.*d", -6, 42, -3, 42), "negative star");
    SAME(snprintf(a, sizeof a, "%p|%p", (void *)a, (void *)0),
         ba_snprintf(b, sizeof b, "%p|%p", (void *)a, (void *)0), "pointer");
    SAME(snprintf(a, sizeof a, "%Lf|%Lg", (long double)2.5, (long double)1e10),
         ba_snprintf(b, sizeof b, "%Lf|%Lg", (long double)2.5, (long double)1e10), "long double");

    {   /* %n, truncation and return values */
        int na = -1, nb = -1;
        ra = snprintf(a, sizeof a, "abc%ndef", &na);
        rb = ba_snprintf(b, sizeof b, "abc%ndef", &nb);
        checks++;
        if (na != nb || ra != rb || strcmp(a, b) != 0)
            fail("%%n: host %d, ours %d", na, nb);
        ra = snprintf(a, 5, "%s", "truncated");
        rb = ba_snprintf(b, 5, "%s", "truncated");
        checks++;
        if (ra != rb || strcmp(a, b) != 0)
            fail("snprintf truncation: host \"%s\" %d, ours \"%s\" %d", a, ra, b, rb);
        rb = ba_snprintf(NULL, 0, "%d", 12345);
        checks++;
        if (rb != 5)
            fail("snprintf(NULL, 0) returned %d", rb);
        rb = ba_sprintf(b, "%s-%d", "x", 7);
        checks++;
        if (rb != 3 || strcmp(b, "x-7") != 0)
            fail("sprintf: \"%s\" %d", b, rb);
    }
#undef SAME
}

/* ---- strtod --------------------------------------------------------- */

static void check_strtod(const char *s)
{
    char *ea, *eb;
    double a, b;
    int erra, errb;

    errno = 0;
    a = strtod(s, &ea);
    erra = errno;
    errno = 0;
    b = ba_strtod(s, &eb);
    errb = errno;
    checks++;
    if (!(isnan(a) && isnan(b)) && to_bits(a) != to_bits(b))
        fail("strtod(\"%.60s\"): host %.17g, ours %.17g", s, a, b);
    else if (ea - s != eb - s)
        fail("strtod(\"%.60s\"): host end %d, ours end %d", s, (int)(ea - s), (int)(eb - s));
    else if ((erra == ERANGE) != (errb == ERANGE) && a != 0.0 && !isinf(a) &&
             fabs(a) >= DBL_MIN)
        fail("strtod(\"%.60s\"): host errno %d, ours %d", s, erra, errb);
}

static void test_strtod(void)
{
    static const char *cases[] = {
        "0", "-0", "1", "0.1", "  -12.5e+3xyz", "1e400", "-1e400", "1e-400",
        "2.4703282292062327e-324", "2.4703282292062328e-324", "4.9406564584124654e-324",
        "2.2250738585072011e-308", "2.2250738585072014e-308", "1.7976931348623157e308",
        "1.7976931348623158e308", "1.7976931348623159e308", "9007199254740993",
        "9007199254740993.0000000001", "0.30000000000000004", "123456789012345678901234567890",
        ".5", "5.", ".", "e5", "1e", "1e+", "1e+x", "+.e1", "-", "+", "", "   ", "inf",
        "-Infinity", "nan", "NaN(123)", "infinit", "0x10", "0x1.8p3", "-0X.8P-2", "0x1p-1074", "0x1p-1075", "0x1.0000000000000801p0",
        "0x1fffffffffffff8p-3", "0xp1", "0x.p1", "0x1p", "0x123456789abcdef123p-80", "00000000000000000001.5",
        "1.00000000000000011102230246251565404236316680908203125",
        "1.00000000000000011102230246251565404236316680908203124",
        "1.00000000000000011102230246251565404236316680908203126",
        "7.2057594037927933e16", "3.4e38", "6.02214076e23", "1.602176634e-19", "1e23",
        "8.98846567431158e307", "0.000000000000000000000000000000000000000001",
        "100000000000000000000000000000000000000000000000000000000000000000000000000000e-78"
    };
    char buf[3000];
    size_t i;
    int j, n;
    double v;

    for (i = 0; i < sizeof cases / sizeof cases[0]; i++)
        check_strtod(cases[i]);

    /* Round trips and near-halfway strings for random doubles. */
    for (j = 0; j < 30000; j++) {
        v = (j & 1) ? rand_double() : rand_human();
        sprintf(buf, "%.17g", v);
        check_strtod(buf);
        sprintf(buf, "%.16e", v);
        check_strtod(buf);
        sprintf(buf, "%.25e", v);
        check_strtod(buf);
        if (j % 10 == 0) {
            /* The exact decimal value of a midpoint between two doubles. */
            double next = nextafter(v, INFINITY);
            if (!isinf(next) && v != 0.0) {
                long double mid = ((long double)v + (long double)next) / 2;
                sprintf(buf, "%.40Le", mid);
                check_strtod(buf);
            }
        }
    }

    /* Very long inputs. */
    n = 0;
    buf[n++] = '0';
    buf[n++] = '.';
    for (j = 0; j < 1200; j++)
        buf[n++] = (char)('0' + (int)(next64() % 10));
    buf[n] = '\0';
    check_strtod(buf);
    for (j = 0; j < 2000; j++)
        buf[j] = '9';
    buf[2000] = '\0';
    check_strtod(buf);
    buf[300] = '\0';
    check_strtod(buf);
    strcpy(buf, "1");
    for (j = 1; j < 900; j++)
        buf[j] = '0';
    strcpy(buf + 900, "1e-1200");
    check_strtod(buf);

    {   /* %#g is checked separately: see check_fmt_double */
        char b[64];
        ba_snprintf(b, sizeof b, "%#g|%#.3g|%#g", 999999.5, 1.0, 100.0);
        checks++;
        if (strcmp(b, "1.00000e+06|1.00|100.000") != 0)
            fail("%%#g: \"%s\"", b);
    }
    checks++;
    if (ba_atof("2.5e2") != 250.0)
        fail("atof");
}

/* ---- math ----------------------------------------------------------- */

#define CHECK1(fn, x, limit) do { \
        double h_ = fn(x), o_ = ba_##fn(x), u_ = ulps(o_, h_); \
        checks++; \
        if (u_ > (limit)) fail(#fn "(%.17g): host %.17g, ours %.17g (%.0f ulp)", (double)(x), h_, o_, u_); \
        else if (u_ > worst_##fn) worst_##fn = u_; \
    } while (0)

#define CHECK2(fn, x, y, limit) do { \
        double h_ = fn(x, y), o_ = ba_##fn(x, y), u_ = ulps(o_, h_); \
        checks++; \
        if (u_ > (limit)) fail(#fn "(%.17g, %.17g): host %.17g, ours %.17g (%.0f ulp)", (double)(x), (double)(y), h_, o_, u_); \
        else if (u_ > worst_##fn) worst_##fn = u_; \
    } while (0)

#define EXACT1(fn, x) do { \
        double h_ = fn(x), o_ = ba_##fn(x); \
        checks++; \
        if (to_bits(h_) != to_bits(o_) && !(isnan(h_) && isnan(o_))) \
            fail(#fn "(%.17g): host %.17g, ours %.17g", (double)(x), h_, o_); \
    } while (0)

static double worst_sqrt, worst_exp, worst_log, worst_log10, worst_pow, worst_sin, worst_cos,
    worst_tan, worst_atan, worst_atan2, worst_asin, worst_acos, worst_sinh, worst_cosh, worst_tanh;

static void test_math(void)
{
    static const double specials[] = {
        0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, -1.5, 2.0, 1e-300, -1e-300, 5e-324, 1e300,
        -1e300, 4503599627370496.5, 4503599627370495.5, 2147483647.5, -2147483648.5,
        9007199254740991.0, 1e20, -1e20, 0.49999999999999994, 3.0, 10.0, 100.0, 1000.0, 1e-5
    };
    double x, y, z, ih, io, w;
    int eh, eo, i, j;

    for (i = 0; i < (int)(sizeof specials / sizeof specials[0]); i++) {
        x = specials[i];
        EXACT1(floor, x); EXACT1(ceil, x); EXACT1(fabs, x);
        checks++;
        if (to_bits(frexp(x, &eh)) != to_bits(ba_frexp(x, &eo)) || (x != 0.0 && eh != eo))
            fail("frexp(%.17g)", x);
        checks++;
        if (to_bits(modf(x, &ih)) != to_bits(ba_modf(x, &io)) || to_bits(ih) != to_bits(io))
            fail("modf(%.17g): host %.17g+%.17g ours %.17g+%.17g", x, ih, modf(x, &ih), io, ba_modf(x, &io));
    }
    EXACT1(floor, INFINITY); EXACT1(ceil, -INFINITY); EXACT1(floor, NAN);

    for (j = 0; j < 200000; j++) {
        x = (j & 3) == 0 ? rand_double() : rand_human();
        EXACT1(floor, x); EXACT1(ceil, x); EXACT1(fabs, x);
        checks++;
        if (to_bits(frexp(x, &eh)) != to_bits(ba_frexp(x, &eo)) || eh != eo)
            fail("frexp(%.17g)", x);
        checks++;
        if (to_bits(modf(x, &ih)) != to_bits(ba_modf(x, &io)) || to_bits(ih) != to_bits(io))
            fail("modf(%.17g)", x);
        i = (int)(next64() % 2200) - 1100;
        checks++;
        if (to_bits(ldexp(x, i)) != to_bits(ba_ldexp(x, i)))
            fail("ldexp(%.17g, %d): host %.17g, ours %.17g", x, i, ldexp(x, i), ba_ldexp(x, i));
        y = (j & 1) ? rand_human() : rand_double();
        if (y != 0.0) {
            checks++;
            if (to_bits(fmod(x, y)) != to_bits(ba_fmod(x, y)))
                fail("fmod(%.17g, %.17g): host %.17g, ours %.17g", x, y, fmod(x, y), ba_fmod(x, y));
        }
    }

    for (j = 0; j < 200000; j++) {
        x = (j & 3) == 0 ? rand_double() : rand_human();
        w = fabs(x);
        CHECK1(sqrt, w, 1);
        CHECK1(log, w, 1);
        CHECK1(log10, w, 2);
        CHECK1(atan, x, 1);
        CHECK1(tanh, x, 4);
        y = fmod(x, 800.0);
        CHECK1(exp, y, 1);
        CHECK1(sinh, y, 4);
        CHECK1(cosh, y, 4);
        y = fmod(x, 1e6);
        CHECK1(sin, y, 2);
        CHECK1(cos, y, 2);
        CHECK1(tan, y, 3);
        y = fmod(x, 1.0);
        CHECK1(asin, y, 2);
        CHECK1(acos, y, 2);
        y = rand_human();
        CHECK2(atan2, x, y, 2);
        y = fmod(rand_human(), 60.0);
        CHECK2(pow, w, y, 2);
        z = (double)(int)fmod(y, 30.0);
        CHECK2(pow, fmod(w, 30.0), z, 2);
        z = fmod(x, 1e5);
        CHECK2(pow, 1.0 + fmod(w, 1e-3), z, 2);
    }
    /* Exact cases programs rely on. */
    checks++;
    if (ba_sqrt(4.0) != 2.0 || ba_sqrt(2.25) != 1.5 || ba_pow(10.0, 3.0) != 1000.0 ||
        ba_pow(2.0, -2.0) != 0.25 || ba_log10(1000.0) != 3.0 || ba_log10(1e-5) != -5.0 ||
        ba_pow(-2.0, 3.0) != -8.0 || ba_exp(0.0) != 1.0 || ba_log(1.0) != 0.0 ||
        ba_pow(10.0, 15.0) != 1e15 || ba_pow(10.0, 22.0) != 1e22 || ba_pow(2.0, -1074.0) != 5e-324 ||
        ba_pow(3.0, 33.0) != 5559060566555523.0 || ba_pow(0.5, 3.0) != 0.125)
        fail("exact math cases");
    errno = 0;
    x = ba_sqrt(-1.0);
    checks++;
    if (!isnan(x) || errno != EDOM)
        fail("sqrt(-1) errno");
    errno = 0;
    x = ba_exp(1000.0);
    checks++;
    if (!isinf(x) || errno != ERANGE)
        fail("exp(1000) errno");

    printf("  worst ULP errors: sqrt %.0f, exp %.0f, log %.0f, log10 %.0f, pow %.0f, sin %.0f, "
           "cos %.0f, tan %.0f,\n    atan %.0f, atan2 %.0f, asin %.0f, acos %.0f, sinh %.0f, "
           "cosh %.0f, tanh %.0f\n",
           worst_sqrt, worst_exp, worst_log, worst_log10, worst_pow, worst_sin, worst_cos,
           worst_tan, worst_atan, worst_atan2, worst_asin, worst_acos, worst_sinh, worst_cosh,
           worst_tanh);
}

/* ---- time ----------------------------------------------------------- */

static void test_time(void)
{
    static const char *fmts[] = {
        "%a %A %b %B %d %e %H %I %j %m %M %p %S %U %w %W %y %Y %%", "%c", "%x", "%X",
        "%D %F %R %T %r %u %C %h %n%t", "%z"
    };
    char a[256], b[256];
    struct tm th, to, *p;
    time_t t, ta, tb;
    size_t ra, rb, i;
    int j;

    for (j = 0; j < 100000; j++) {
        t = (time_t)((int64_t)(next64() % 40000000000ULL) - 15000000000LL);
        if (j < 10)
            t = (time_t)j * 86399 - 5;
        gmtime_r(&t, &th);
        p = ba_gmtime(&t);
        to = *p;
        checks++;
        if (th.tm_year != to.tm_year || th.tm_mon != to.tm_mon || th.tm_mday != to.tm_mday ||
            th.tm_hour != to.tm_hour || th.tm_min != to.tm_min || th.tm_sec != to.tm_sec ||
            th.tm_wday != to.tm_wday || th.tm_yday != to.tm_yday) {
            fail("gmtime(%lld)", (long long)t);
            continue;
        }
        checks++;
        if (strcmp(asctime(&th), ba_asctime(&to)) != 0)
            fail("asctime(%lld): host %s ours %s", (long long)t, asctime(&th), ba_asctime(&to));
        for (i = 0; i < sizeof fmts / sizeof fmts[0]; i++) {
            ra = strftime(a, sizeof a, fmts[i], &th);
            rb = ba_strftime(b, sizeof b, fmts[i], &to);
            checks++;
            if (ra != rb || strcmp(a, b) != 0)
                fail("strftime(\"%s\"): host \"%s\", ours \"%s\"", fmts[i], a, b);
        }
        /* mktime normalizes out-of-range fields; compare with timegm. */
        th.tm_mon += (int)(next64() % 40) - 20;
        th.tm_mday += (int)(next64() % 100) - 50;
        th.tm_hour += (int)(next64() % 60) - 30;
        th.tm_sec += (int)(next64() % 10000) - 5000;
        to = th;
        ta = timegm(&th);
        tb = ba_mktime(&to);
        checks++;
        if (ta != tb || th.tm_mday != to.tm_mday || th.tm_mon != to.tm_mon ||
            th.tm_wday != to.tm_wday || th.tm_yday != to.tm_yday)
            fail("mktime: host %lld, ours %lld", (long long)ta, (long long)tb);
    }
    checks++;
    if (ba_strftime(a, 3, "%Y", &th) != 0)
        fail("strftime overflow should return 0");
}

/* ---- stdlib, string, locale ---------------------------------------- */

static int cmp_int(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static void test_misc(void)
{
    static const int arr[] = { 1, 3, 5, 7, 9, 11, 13 };
    char s1[64], s2[64], *ta, *tb;
    int i, j, k;
    div_t dh, dob;
    ldiv_t lh, lo;
    wchar_t wc;

    for (i = -50; i <= 50; i++) {
        for (j = -7; j <= 7; j++) {
            if (j == 0)
                continue;
            dh = div(i, j);
            dob = ba_div(i, j);
            lh = ldiv((long)i * 100000L, (long)j);
            lo = ba_ldiv((long)i * 100000L, (long)j);
            checks++;
            if (dh.quot != dob.quot || dh.rem != dob.rem || lh.quot != lo.quot || lh.rem != lo.rem)
                fail("div(%d, %d)", i, j);
        }
    }
    checks++;
    if (ba_labs(-5L) != 5L || ba_labs(LONG_MAX) != LONG_MAX)
        fail("labs");

    for (i = 0; i <= 14; i++) {
        k = i;
        checks++;
        if ((ba_bsearch(&k, arr, 7, sizeof arr[0], cmp_int) != NULL) != ((i & 1) && i <= 13))
            fail("bsearch(%d)", i);
    }
    checks++;
    if (ba_bsearch(&k, arr, 0, sizeof arr[0], cmp_int) != NULL)
        fail("bsearch empty");

    strcpy(s1, ",,a,bb;;ccc,,");
    strcpy(s2, s1);
    ta = strtok(s1, ",;");
    tb = ba_strtok(s2, ",;");
    while (ta != NULL || tb != NULL) {
        checks++;
        if (ta == NULL || tb == NULL || strcmp(ta, tb) != 0) {
            fail("strtok");
            break;
        }
        ta = strtok(NULL, ",;");
        tb = ba_strtok(NULL, ",;");
    }

    checks++;
    if (ba_strxfrm(s1, "hello", 3) != 5 || strcmp(s1, "he") != 0)
        fail("strxfrm");

    ba_srand(1);
    i = ba_rand();
    j = ba_rand();
    ba_srand(1);
    checks++;
    if (ba_rand() != i || ba_rand() != j || i != 16838 || j != 5758)
        fail("rand sequence (%d %d)", i, j);

    checks++;
    if (strcmp(ba_setlocale(LC_ALL, NULL), "C") != 0 || ba_setlocale(LC_ALL, "xx_YY") != NULL ||
        strcmp(ba_localeconv()->decimal_point, ".") != 0)
        fail("locale");

    checks++;
    if (ba_mbtowc(&wc, "A", 1) != 1 || wc != L'A' || ba_wctomb(s1, L'z') != 1 || s1[0] != 'z')
        fail("multibyte");
}

/* ---- scanf ---------------------------------------------------------- */

static void test_scanf(void)
{
    static const char *inputs[] = {
        "42", "  -17 abc", "0x1F", "077", "3.25e2", "-1.5", "hello world", "12abc",
        "   ", "", "abc", "+", "-x", "1e5x", ".5", "5.", "inf", "nan", "123456789012",
        "10 20 30", "a,b", "[x]", "1.0e", "0x", "08"
    };
    static const char *fmts[] = {
        "%d", "%i", "%x", "%o", "%u", "%ld", "%lf", "%f", "%s", "%3s", "%c", "%3c", "%[a-z]",
        "%[^ ]", "%d %d", "%d%n", "%*d %d", "%2d%d", "%e", "%lg", "%d,%d", "%[^,],%s",
        "[%[^]]]", "%%%d", " %s"
    };
    size_t i, j;
    int rh, ro, ih[3], io[3], nh, no;
    long lh, lo;
    double dh, dob;
    float fh, fo;
    char sh[64], so[64], sh2[64], so2[64];

    for (i = 0; i < sizeof inputs / sizeof inputs[0]; i++) {
        for (j = 0; j < sizeof fmts / sizeof fmts[0]; j++) {
            const char *f = fmts[j];
            memset(ih, 0, sizeof ih); memset(io, 0, sizeof io);
            memset(sh, 0, sizeof sh); memset(so, 0, sizeof so);
            memset(sh2, 0, sizeof sh2); memset(so2, 0, sizeof so2);
            lh = lo = 0; dh = dob = 0; fh = fo = 0; nh = no = -1;
            if (!strcmp(f, "%ld")) {
                rh = sscanf(inputs[i], f, &lh); ro = ba_sscanf(inputs[i], f, &lo);
                if (rh == 1 && lh != lo) ro = -99;
            } else if (!strcmp(f, "%lf") || !strcmp(f, "%lg")) {
                rh = sscanf(inputs[i], f, &dh); ro = ba_sscanf(inputs[i], f, &dob);
                if (rh == 1 && to_bits(dh) != to_bits(dob) && !(isnan(dh) && isnan(dob))) ro = -99;
            } else if (!strcmp(f, "%f") || !strcmp(f, "%e")) {
                rh = sscanf(inputs[i], f, &fh); ro = ba_sscanf(inputs[i], f, &fo);
                if (rh == 1 && fh != fo && !(isnan(fh) && isnan(fo))) ro = -99;
            } else if (strchr(f, 's') || strchr(f, '[') || strchr(f, 'c')) {
                if (!strcmp(f, "%[^,],%s")) {
                    rh = sscanf(inputs[i], f, sh, sh2); ro = ba_sscanf(inputs[i], f, so, so2);
                } else {
                    rh = sscanf(inputs[i], f, sh); ro = ba_sscanf(inputs[i], f, so);
                }
                if (rh >= 1 && (strcmp(sh, so) != 0 || strcmp(sh2, so2) != 0)) ro = -99;
            } else if (!strcmp(f, "%d%n")) {
                rh = sscanf(inputs[i], f, &ih[0], &nh); ro = ba_sscanf(inputs[i], f, &io[0], &no);
                if (rh == 1 && (ih[0] != io[0] || nh != no)) ro = -99;
            } else {
                rh = sscanf(inputs[i], f, &ih[0], &ih[1], &ih[2]);
                ro = ba_sscanf(inputs[i], f, &io[0], &io[1], &io[2]);
                if (memcmp(ih, io, sizeof ih) != 0) ro = -99;
            }
            checks++;
            /* glibc consumes "1e" / "0x" prefixes it then rejects; C allows
               either outcome there, so only compare the values. */
            if (rh != ro)
                fail("sscanf(\"%s\", \"%s\"): host %d, ours %d", inputs[i], f, rh, ro);
        }
    }
}

int main(void)
{
    printf("printf...\n");
    test_printf();
    printf("strtod...\n");
    test_strtod();
    printf("math...\n");
    test_math();
    printf("time...\n");
    test_time();
    printf("stdlib/string/locale...\n");
    test_misc();
    printf("scanf...\n");
    test_scanf();
    printf("%ld checks, %ld failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
