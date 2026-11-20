/*
 * ba_math.c: the C89 <math.h> functions, for libcs that lack them.
 *
 * Part of build-anywhere. The polynomial kernels and constants for exp, log,
 * sin, cos and atan are from FreeBSD's msun (fdlibm), whose notice is:
 *
 *   Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *   Developed at SunSoft, a Sun Microsystems, Inc. business.
 *   Permission to use, copy, modify, and distribute this
 *   software is freely granted, provided that this notice
 *   is preserved.
 *
 * Unlike fdlibm, nothing here inspects the bits of a double: scaling and
 * splitting use exact arithmetic only (multiplying by powers of two), so the
 * code compiles with any C89 compiler. Results are within a few units in the
 * last place of the correctly rounded value; exact cases stay exact
 * (sqrt(4) == 2, pow(10, 3) == 1000, log10(1000) == 3, floor/ceil/fmod/frexp/
 * ldexp/modf are exact).
 */
#include <errno.h>
#include <math.h>

#include "ba_libc.h"

static const double two64  = 18446744073709551616.0;          /* 2^64 */
static const double twom64 = 5.42101086242752217003726400435e-20; /* 2^-64 */

static int is_nan(double x) { return x != x; }
static int is_inf(double x) { return x == x && x != 0.0 && x + x == x; }

static double domain_error(void)
{
    errno = EDOM;
    return __ba_nan();
}

static double range_error(double v)
{
    errno = ERANGE;
    return v;
}

double fabs(double x)
{
    if (x < 0.0)
        return -x;
    if (x == 0.0)
        return 0.0 * x * x;     /* -0 -> +0 */
    return x;
}

double frexp(double x, int *ep)
{
    int e = 0;
    double a;

    if (x == 0.0 || is_nan(x) || is_inf(x)) {
        *ep = 0;
        return x;
    }
    a = x < 0.0 ? -x : x;
    while (a >= two64) { a *= twom64; e += 64; }
    while (a >= 1.0)   { a *= 0.5;    e += 1; }
    while (a < twom64) { a *= two64;  e -= 64; }
    while (a < 0.5)    { a *= 2.0;    e -= 1; }
    *ep = e;
    return x < 0.0 ? -a : a;
}

/* 2^k exactly, for -1074 <= k <= 1023. */

double fmod(double x, double y)
{
    double ax, ay, t;
    int ex, ey;

    if (is_nan(x) || is_nan(y) || is_inf(x) || y == 0.0)
        return domain_error();
    if (is_inf(y))
        return x;
    ax = x < 0.0 ? -x : x;
    ay = y < 0.0 ? -y : y;
    /* Subtract the largest ay * 2^k that fits; every step is exact. */
    while (ax >= ay) {
        frexp(ax, &ex);
        frexp(ay, &ey);
        t = ldexp(ay, ex - ey);
        if (t > ax)
            t *= 0.5;
        ax -= t;
    }
    return x < 0.0 ? -ax : ax;
}

/* Integer part, rounding toward zero, keeping the sign of zero. Exact for
   every double. */
static double trunc_part(double x)
{
    double a = x < 0.0 ? -x : x, t;
    if (a >= 4503599627370496.0)        /* 2^52: already an integer */
        return x;
    if (a < 2147483647.0)
        t = (double)(long)x;
    else
        t = x - fmod(x, 1.0);
    if (t == 0.0)
        return x < 0.0 ? -0.0 : x * 0.0;  /* x * 0.0 keeps -0.0 */
    return t;
}

double floor(double x)
{
    double t;
    if (is_nan(x) || is_inf(x) || x == 0.0)
        return x;
    t = trunc_part(x);
    if (t > x)
        t -= 1.0;
    if (t == 0.0 && x < 0.0)
        return -0.0;
    return t;
}

double ceil(double x)
{
    double t;
    if (is_nan(x) || is_inf(x) || x == 0.0)
        return x;
    t = trunc_part(x);          /* -0.0 for x in (-1, 0) */
    if (t < x)
        t += 1.0;
    return t;
}

double modf(double x, double *ip)
{
    double t;
    if (is_nan(x)) {
        *ip = x;
        return x;
    }
    if (is_inf(x)) {
        *ip = x;
        return x < 0.0 ? -0.0 : 0.0;
    }
    t = trunc_part(x);
    *ip = t;
    if (x == t)
        return t * 0.0;         /* zero with the sign of x */
    return x - t;
}

/* Split a into hi + lo where hi has at most 26 significant bits (Veltkamp),
   so that products of halves are exact. */
static void split(double a, double *hi, double *lo)
{
    double c = 134217729.0 * a;         /* 2^27 + 1 */
    *hi = c - (c - a);
    *lo = a - *hi;
}

double sqrt(double x)
{
    double m, r, rh, rl, p, e;
    int k, i;

    if (is_nan(x))
        return x;
    if (x < 0.0)
        return domain_error();
    if (x == 0.0 || is_inf(x))
        return x;
    m = frexp(x, &k);           /* x = m * 2^k, m in [0.5, 1) */
    if (k & 1) {
        m *= 2.0;
        k--;
    }
    /* m in [0.5, 2): Newton's method from a linear first guess. */
    r = 0.41731 + 0.59016 * m;
    for (i = 0; i < 6; i++)
        r = 0.5 * (r + m / r);
    /* One correction with the exact residual m - r*r. */
    split(r, &rh, &rl);
    p = r * r;
    e = ((rh * rh - p) + 2.0 * rh * rl) + rl * rl;
    r += ((m - p) - e) / (2.0 * r);
    return ldexp(r, k / 2);
}

/* ---- exp and log ---------------------------------------------------- */

static const double ln2_hi = 6.93147180369123816490e-01;
static const double ln2_lo = 1.90821492927058770002e-10;
static const double inv_ln2 = 1.44269504088896338700e+00;

double exp(double x)
{
    static const double P1 = 1.66666666666666019037e-01;
    static const double P2 = -2.77777777770155933842e-03;
    static const double P3 = 6.61375632143793436117e-05;
    static const double P4 = -1.65339022054652515390e-06;
    static const double P5 = 4.13813679705723846039e-08;
    double hi, lo, r, z, c, y;
    long k;

    if (is_nan(x))
        return x;
    if (x > 7.09782712893383973096e+02)
        return range_error(__ba_inf());
    if (x < -7.45133219101941108420e+02)
        return range_error(0.0);
    if (x > -3.7252902984e-09 && x < 3.7252902984e-09)
        return 1.0 + x;

    k = (long)(x * inv_ln2 + (x < 0.0 ? -0.5 : 0.5));
    hi = x - (double)k * ln2_hi;
    lo = (double)k * ln2_lo;
    r = hi - lo;
    z = r * r;
    c = r - z * (P1 + z * (P2 + z * (P3 + z * (P4 + z * P5))));
    y = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi);
    return ldexp(y, (int)k);
}

double log(double x)
{
    static const double Lg1 = 6.666666666666735130e-01;
    static const double Lg2 = 3.999999999940941908e-01;
    static const double Lg3 = 2.857142874366239149e-01;
    static const double Lg4 = 2.222219843214978396e-01;
    static const double Lg5 = 1.818357216161805012e-01;
    static const double Lg6 = 1.531383769920937332e-01;
    static const double Lg7 = 1.479819860511658591e-01;
    double m, f, s, z, w, t1, t2, R, hfsq, dk;
    int k;

    if (is_nan(x))
        return x;
    if (x < 0.0)
        return domain_error();
    if (x == 0.0)
        return range_error(-__ba_inf());
    if (is_inf(x))
        return x;

    m = frexp(x, &k);
    if (m < 0.70710678118654752440) {
        m *= 2.0;
        k--;
    }
    f = m - 1.0;
    dk = (double)k;
    s = f / (2.0 + f);
    z = s * s;
    w = z * z;
    t1 = w * (Lg2 + w * (Lg4 + w * Lg6));
    t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
    R = t2 + t1;
    hfsq = 0.5 * f * f;
    return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f);
}

double log10(double x)
{
    static const double inv_ln10 = 4.34294481903251827651e-01;
    double r, n, p;
    int i;

    r = log(x) * inv_ln10;
    if (is_nan(r) || is_inf(r))
        return r;
    /* Make exact powers of ten give exact results. */
    n = floor(r + 0.5);
    if (n - r < 1e-9 && r - n < 1e-9 && n > -23.0 && n < 23.0) {
        p = 1.0;
        for (i = 0; i < (n < 0 ? -n : n); i++)
            p *= 10.0;
        if (n < 0 ? x * p == 1.0 : x == p)
            return n;
    }
    return r;
}

/* ---- pow ------------------------------------------------------------ */

/* Error-free transformations: a + b == *hi + *lo and a * b == *hi + *lo
   exactly (Knuth's two-sum and Dekker's two-product). */
static void two_sum(double a, double b, double *hi, double *lo)
{
    double s = a + b, bb = s - a;
    *hi = s;
    *lo = (a - (s - bb)) + (b - bb);
}

static void two_prod(double a, double b, double *hi, double *lo)
{
    double ah, al, bh, bl, p = a * b;
    split(a, &ah, &al);
    split(b, &bh, &bl);
    *hi = p;
    *lo = ((ah * bh - p) + ah * bl + al * bh) + al * bl;
}

/* log(x) for finite x > 0 as hi + lo, with about 100 bits of precision. */
static void log_dd(double x, double *hi, double *lo)
{
    double m, f, uh, ul, sh, sl, ph, pl, z, R, dk, a, b, c, e;
    int k;

    m = frexp(x, &k);
    if (m < 0.70710678118654752440) {
        m *= 2.0;
        k--;
    }
    dk = (double)k;
    f = m - 1.0;                        /* exact */
    /* s = f / (2 + f) to double-double precision. */
    two_sum(2.0, f, &uh, &ul);
    sh = f / uh;
    two_prod(sh, uh, &ph, &pl);
    sl = (((f - ph) - pl) - sh * ul) / uh;
    /* log(m) = 2s + 2s^3/3 + 2s^5/5 + ...; the tail is small enough for
       plain double precision. */
    z = sh * sh;
    R = 2.0 * sh * z * (1.0 / 3.0 + z * (1.0 / 5.0 + z * (1.0 / 7.0 + z * (1.0 / 9.0 +
        z * (1.0 / 11.0 + z * (1.0 / 13.0 + z * (1.0 / 15.0 + z * (1.0 / 17.0 +
        z * (1.0 / 19.0 + z * (1.0 / 21.0 + z * (1.0 / 23.0)))))))))));
    two_sum(dk * ln2_hi, 2.0 * sh, &a, &b);
    c = b + (dk * ln2_lo + 2.0 * sl + R);
    two_sum(a, c, hi, &e);
    *lo = e;
}

static int is_integer(double y) { return floor(y) == y; }
static int is_odd_integer(double y) { return is_integer(y) && fmod(y, 2.0) != 0.0; }

/* x^n for an integer 0 < n <= 2^20 by repeated squaring, but only if every
   product is exact (checked with two_prod); returns 0 otherwise. */
static int pow_exact(double x, double n, double *out)
{
    double r = 1.0, hi, lo;
    while (n > 0.0) {
        if (fmod(n, 2.0) != 0.0) {
            two_prod(r, x, &hi, &lo);
            if (lo != 0.0 || is_inf(hi) || hi == 0.0)
                return 0;
            r = hi;
        }
        n = floor(n * 0.5);
        if (n > 0.0) {
            two_prod(x, x, &hi, &lo);
            if (lo != 0.0 || is_inf(hi) || hi == 0.0)
                return 0;
            x = hi;
        }
    }
    *out = r;
    return 1;
}

double pow(double x, double y)
{
    double ax, r, lh, ll, th, tl, e;
    int neg = 0;

    if (y == 0.0 || x == 1.0)
        return 1.0;
    if (is_nan(x) || is_nan(y))
        return __ba_nan();
    if (is_inf(y)) {
        ax = fabs(x);
        if (ax == 1.0)
            return 1.0;
        if ((ax < 1.0) == (y > 0.0))
            return 0.0;
        return __ba_inf();
    }
    if (x == 0.0) {
        if (y > 0.0)
            return is_odd_integer(y) ? x : 0.0;
        r = __ba_inf();
        errno = ERANGE;
        return (is_odd_integer(y) && 1.0 / x < 0.0) ? -r : r;
    }
    if (x < 0.0) {
        if (!is_integer(y))
            return domain_error();
        neg = is_odd_integer(y);
        x = -x;
    }
    if (is_inf(x)) {
        r = y > 0.0 ? x : 0.0;
        return neg ? -r : r;
    }

    if (is_integer(y) && fabs(y) <= 1048576.0 && pow_exact(x, fabs(y), &r)) {
        /* Exactly representable power: exact result (one rounding if y < 0). */
        if (y < 0.0)
            r = 1.0 / r;
    } else {
        /* x^y = e^(y log x), carrying y log x in double-double precision. */
        log_dd(x, &lh, &ll);
        two_prod(y, lh, &th, &tl);
        tl += y * ll;
        two_sum(th, tl, &th, &tl);
        if (th > 7.09782712893383973096e+02)
            return range_error(neg ? -__ba_inf() : __ba_inf());
        if (th < -7.45133219101941108420e+02)
            return range_error(neg ? -0.0 : 0.0);
        e = exp(th);
        r = e + e * tl;
    }
    if (is_inf(r) || r == 0.0)
        errno = ERANGE;
    return neg ? -r : r;
}

/* ---- trigonometry --------------------------------------------------- */

static double ksin(double x)    /* |x| <= pi/4 */
{
    static const double S1 = -1.66666666666666324348e-01;
    static const double S2 = 8.33333333332248946124e-03;
    static const double S3 = -1.98412698298579493134e-04;
    static const double S4 = 2.75573137070700676789e-06;
    static const double S5 = -2.50507602534068634195e-08;
    static const double S6 = 1.58969099521155010221e-10;
    double z = x * x;
    double r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
    return x + x * z * (S1 + z * r);
}

static double kcos(double x)    /* |x| <= pi/4 */
{
    static const double C1 = 4.16666666666666019037e-02;
    static const double C2 = -1.38888888888741095749e-03;
    static const double C3 = 2.48015872894767294178e-05;
    static const double C4 = -2.75573143513906633035e-07;
    static const double C5 = 2.08757232129817482790e-09;
    static const double C6 = -1.13596475577881948265e-11;
    double z = x * x;
    double r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
    double hz = 0.5 * z;
    double w = 1.0 - hz;
    return w + (((1.0 - w) - hz) + z * r);
}

/* Reduce x to r in [-pi/4, pi/4] with x = r + n*pi/2; returns n mod 4. */
static int reduce(double x, double *r)
{
    static const double pio2_1 = 1.57079632673412561417e+00;
    static const double pio2_2 = 6.07710050630396597660e-11;
    static const double pio2_3 = 2.02226624871116645580e-21;
    static const double pio2_3t = 8.47842766036889956997e-32;
    static const double twopi = 6.28318530717958647692;
    double n, y;
    int q;

    if (fabs(x) <= 7.85398163397448278999e-01) {
        *r = x;
        return 0;
    }
    if (fabs(x) > 1.0e6)            /* reduce coarsely first */
        x = fmod(x, twopi);
    n = floor(x * 6.36619772367581382433e-01 + 0.5);    /* 2/pi */
    y = x - n * pio2_1;
    y -= n * pio2_2;
    y -= n * pio2_3;
    y -= n * pio2_3t;
    *r = y;
    q = (int)fmod(n, 4.0);
    if (q < 0)
        q += 4;
    return q;
}

double sin(double x)
{
    double r;
    if (is_nan(x))
        return x;
    if (is_inf(x))
        return domain_error();
    switch (reduce(x, &r)) {
    case 0:  return ksin(r);
    case 1:  return kcos(r);
    case 2:  return -ksin(r);
    default: return -kcos(r);
    }
}

double cos(double x)
{
    double r;
    if (is_nan(x))
        return x;
    if (is_inf(x))
        return domain_error();
    switch (reduce(x, &r)) {
    case 0:  return kcos(r);
    case 1:  return -ksin(r);
    case 2:  return -kcos(r);
    default: return ksin(r);
    }
}

double tan(double x)
{
    double r;
    int q;
    if (is_nan(x))
        return x;
    if (is_inf(x))
        return domain_error();
    q = reduce(x, &r);
    if (q & 1)
        return -kcos(r) / ksin(r);
    return ksin(r) / kcos(r);
}

double atan(double x)
{
    static const double atanhi[4] = {
        4.63647609000806093515e-01, 7.85398163397448278999e-01,
        9.82793723247329054082e-01, 1.57079632679489655800e+00
    };
    static const double atanlo[4] = {
        2.26987774529616870924e-17, 3.06161699786838301793e-17,
        1.39033110312309984516e-17, 6.12323399573676603587e-17
    };
    static const double aT[11] = {
        3.33333333333329318027e-01, -1.99999999998764832476e-01,
        1.42857142725034663711e-01, -1.11111104054623557880e-01,
        9.09088713343650656196e-02, -7.69187620504482999495e-02,
        6.66107313738753120669e-02, -5.83357013379057348645e-02,
        4.97687799461593236017e-02, -3.65315727442169155270e-02,
        1.62858201153657823623e-02
    };
    double ax, z, w, s1, s2, r;
    int id, neg;

    if (is_nan(x))
        return x;
    neg = x < 0.0;
    ax = neg ? -x : x;
    if (ax > 7.3786976294838206464e+19) {   /* 2^66 */
        r = atanhi[3] + atanlo[3];
        return neg ? -r : r;
    }
    if (ax < 0.4375) {
        id = -1;
    } else if (ax < 0.6875) {
        id = 0;
        ax = (2.0 * ax - 1.0) / (2.0 + ax);
    } else if (ax < 1.1875) {
        id = 1;
        ax = (ax - 1.0) / (ax + 1.0);
    } else if (ax < 2.4375) {
        id = 2;
        ax = (ax - 1.5) / (1.0 + 1.5 * ax);
    } else {
        id = 3;
        ax = -1.0 / ax;
    }
    z = ax * ax;
    w = z * z;
    s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0) {
        r = ax - ax * (s1 + s2);
    } else {
        r = atanhi[id] - ((ax * (s1 + s2) - atanlo[id]) - ax);
    }
    return neg ? -r : r;
}

double atan2(double y, double x)
{
    static const double pi = 3.14159265358979311600e+00;
    static const double pi_lo = 1.22464679914735317720e-16;
    static const double pio2 = 1.57079632679489655800e+00;
    double r;
    int yneg;

    if (is_nan(x) || is_nan(y))
        return __ba_nan();
    yneg = y < 0.0 || (y == 0.0 && 1.0 / y < 0.0);
    if (y == 0.0) {
        if (x > 0.0 || (x == 0.0 && 1.0 / x > 0.0))
            return y;
        return yneg ? -(pi + pi_lo) : pi + pi_lo;
    }
    if (x == 0.0)
        return yneg ? -pio2 : pio2;
    if (is_inf(x)) {
        if (is_inf(y))
            r = x > 0.0 ? pio2 * 0.5 : 3.0 * pio2 * 0.5;
        else
            r = x > 0.0 ? 0.0 : pi;
        return yneg ? -r : r;
    }
    if (is_inf(y))
        return yneg ? -pio2 : pio2;

    r = atan(fabs(y / x));
    if (x < 0.0)
        r = (pi - (r - pi_lo));
    return yneg ? -r : r;
}

double asin(double x)
{
    if (is_nan(x))
        return x;
    if (x > 1.0 || x < -1.0)
        return domain_error();
    if (x == 1.0 || x == -1.0)
        return x * 1.57079632679489655800e+00;
    return atan2(x, sqrt((1.0 - x) * (1.0 + x)));
}

double acos(double x)
{
    if (is_nan(x))
        return x;
    if (x > 1.0 || x < -1.0)
        return domain_error();
    return atan2(sqrt((1.0 - x) * (1.0 + x)), x);
}

/* ---- hyperbolic functions ------------------------------------------- */

/* Taylor series of sinh and cosh for |x| < 0.5, in Horner form. */
static double sinh_small(double x)
{
    double z = x * x;
    return x * (1.0 + z / 6.0 * (1.0 + z / 20.0 * (1.0 + z / 42.0 * (1.0 + z / 72.0 *
           (1.0 + z / 110.0 * (1.0 + z / 156.0 * (1.0 + z / 210.0 * (1.0 + z / 272.0))))))));
}

static double cosh_small(double x)
{
    double z = x * x;
    return 1.0 + z / 2.0 * (1.0 + z / 12.0 * (1.0 + z / 30.0 * (1.0 + z / 56.0 *
           (1.0 + z / 90.0 * (1.0 + z / 132.0 * (1.0 + z / 182.0 * (1.0 + z / 240.0)))))));
}

double sinh(double x)
{
    double ax = fabs(x), e, r;
    if (is_nan(x) || is_inf(x))
        return x;
    if (ax < 0.5) {
        return sinh_small(x);
    } else if (ax < 709.0) {
        e = exp(ax);
        r = 0.5 * (e - 1.0 / e);
    } else {
        e = exp(0.5 * ax);
        r = 0.5 * e * e;
        if (is_inf(r))
            errno = ERANGE;
    }
    return x < 0.0 ? -r : r;
}

double cosh(double x)
{
    double ax = fabs(x), e, r;
    if (is_nan(x))
        return x;
    if (ax < 709.0) {
        e = exp(ax);
        return 0.5 * (e + 1.0 / e);
    }
    e = exp(0.5 * ax);
    r = 0.5 * e * e;
    if (is_inf(r))
        errno = ERANGE;
    return r;
}

double tanh(double x)
{
    double ax = fabs(x), e, r;
    if (is_nan(x))
        return x;
    if (ax > 22.0) {
        r = 1.0;
    } else if (ax < 0.5) {
        r = sinh_small(ax) / cosh_small(ax);
    } else {
        e = exp(2.0 * ax);
        r = 1.0 - 2.0 / (e + 1.0);
    }
    return x < 0.0 ? -r : r;
}
