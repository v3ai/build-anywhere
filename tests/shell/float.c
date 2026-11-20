/* The shell tier's floating point: tests/run.sh compiles this with the
   shell tier and compares what it prints with float.golden, the output of
   the same program compiled by gcc with glibc. */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <float.h>

struct pt { double x; double y; };
double g = 2.5;
double tab[4] = { 1.5, -2.25, 1e10, 0.1 };

double norm(struct pt *p) { return sqrt(p->x * p->x + p->y * p->y); }

double avg(double *v, int n)
{
    double s = 0;
    int i;
    for (i = 0; i < n; i++) s += v[i];
    return s / n;
}

int part1(void)
{
    struct pt *p = malloc(sizeof(struct pt) * 2);
    double x = 3, y, z;
    float f = 0.5f;
    int i, n = 7;
    p->x = 3.0;
    p->y = 4;
    printf("norm %g\n", norm(p));
    printf("avg %.4f\n", avg(tab, 4));
    y = x / 7;
    printf("%f %e %g %.17g\n", y, y, y, y);
    printf("[%10.3f] [%-10.2e] [%+g] [%08.2f]\n", g, -g, g * 100, -1.5);
    z = 0;
    for (i = 0; i < 10; i++) z += 0.1;
    printf("z=%.17g z==1? %d z<1? %d\n", z, z == 1.0, z < 1.0);
    i = (int)(x * 2.6);
    printf("i=%d n/2.0=%g (double)n=%.1f -x=%g\n", i, n / 2.0, (double)n, -x);
    printf("sin %.15g cos %.15g exp %.15g log %.15g pow %.15g atan2 %.15g\n",
           sin(1.0), cos(1.0), exp(1.0), log(10.0), pow(2.0, 0.5), atan2(1.0, -1.0));
    printf("atof %.17g strtod %g\n", atof("3.14159"), strtod("-1e-5x", 0));
    printf("inf %f nan %f -0 %g\n", HUGE_VAL, NAN, -0.0);
    printf("floor %g ceil %g round %g fmod %g\n", floor(-2.5), ceil(-2.5), round(2.5), fmod(10.0, 3.0));
    f = f * 3;
    printf("float %g\n", f);
    if (y) printf("y is true\n");
    x = x > 2 ? x * 2 : 0;
    printf("x=%g ", x);
    printf("++x=%g\n", ++x);
    x--;
    printf("x=%g\n", x);
    return 0;
}

typedef struct { double re; double im; int tag; } cplx;
static double weights[] = { 0.25, 0.5, 0.125, 3 };
static double fsum;
int counter = 0;

double square(double v) { return v * v; }
int lt3(double a, double b, double c) { return a < b && b < c; }
double pick(int c, double a, double b) { return c ? a + 1 : b * 2; }
void addto(double *acc, double v) { *acc += v; }
double horner(double *c, int n, double x)
{
    double r = 0;
    while (n-- > 0) r = r * x + c[n];
    return r;
}
cplx *cmul(cplx *a, cplx *b)
{
    cplx *r = malloc(sizeof(cplx));
    r->re = a->re * b->re - a->im * b->im;
    r->im = a->re * b->im + a->im * b->re;
    r->tag = a->tag + b->tag;
    return r;
}

int part2(void)
{
    double *arr = malloc(10 * sizeof(double));
    cplx *a = malloc(sizeof(cplx)), *b = malloc(sizeof(cplx)), *c;
    double t;
    double *acc = malloc(sizeof(double));
    int i, k;
    int l;
    for (i = 0; i < 10; i++) arr[i] = i * 1.5 - 4;
    arr[3] *= -2;
    arr[4] /= 3;
    arr[5] -= 0.75;
    for (i = 0; i < 10; i++) printf("%d:%.6g ", i, arr[i]);
    printf("\n");
    a->re = 1.5; a->im = -2; a->tag = 1;
    b->re = 0.5; b->im = 4; b->tag = 2;
    c = cmul(a, b);
    printf("cmul %g %g %d\n", c->re, c->im, c->tag);
    printf("horner %.10f\n", horner(weights, 4, 1.1));
    *acc = 0;
    addto(acc, 2.5); addto(acc, square(1.5));
    printf("acc %g lt3 %d %d pick %g %g\n", *acc, lt3(1, 2, 3), lt3(1, 3, 2), pick(1, 2.5, 4), pick(0, 2.5, 4));
    k = 10;
    k += 2.7;
    k *= 1.5;
    l = (int)(1e9 * 1.5);
    printf("k=%d l=%d\n", k, l);
    printf("length modifiers %ld %li %hd\n", (long)k, (long)l, (short)k);
    fsum = 0;
    for (i = 1; i <= 100; i++) fsum += 1.0 / i;
    printf("harmonic %.12f\n", fsum);
    t = 1;
    for (i = 0; i < 1100; i++) t /= 2;
    printf("tiny %g %e\n", t, t * 3);
    t = 1;
    for (i = 0; i < 1030; i++) t *= 2;
    printf("big %g isinf %d\n", t, isinf(t));
    printf("DBL_MAX %g DBL_EPSILON %g DBL_MIN %g\n", DBL_MAX, DBL_EPSILON, DBL_MIN);
    printf("%.3f %.0f %.0f %.0f %#.0f %5.1e|%-8.3g|%G %E\n", 2.0005, 0.5, 1.5, 2.5, 3.0, 12345.678, 0.0001234, 1e-10, 6.02e23);
    printf("%f %f %.20f\n", 1e20, -123456789.125, 0.1);
    printf("conv %d %d %d %d\n", (int)-2.9, (int)2.9, (int)(0.1 + 0.2 == 0.3), (int)(sqrt(2) * sqrt(2) == 2));
    printf("cmp %d %d %d %d %d\n", 1.0 < 2, 2 > 1.5, 3.0 >= 3, -0.0 == 0.0, NAN != NAN);
    if (!(*acc > 4.74 && *acc < 4.76)) printf("bad acc\n");
    for (t = 0; t < 1; t += 0.25) counter++;
    printf("counter %d\n", counter);
    printf("trig %.15g %.15g %.15g %.15g\n", tan(0.5), asin(0.5), acos(-0.3), atan(100));
    printf("hyp %.15g %.15g %.15g\n", sinh(1), cosh(-2), tanh(0.3));
    printf("misc %.15g %.15g %.15g %.15g %.15g\n", log10(2), log2(10), cbrt(27.5), hypot(3, 4), exp2(0.5));
    printf("big trig %.15g %.15g\n", sin(1e15), cos(123456789.0));
    printf("strtod %.17g %.17g %.17g %g\n", strtod("1.7976931348623157e308", 0), strtod("4.9e-324", 0), atof("  -0x1.8p3"), strtod("inf", 0));
    return 0;
}

int main(void)
{
    part1();
    part2();
    return 0;
}
