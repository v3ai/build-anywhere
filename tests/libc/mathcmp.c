/* mathcmp.c: math, printf and strtod results for fixed inputs.

     mathcmp              print the results (mathcmp.golden is this output
                          from glibc on x86_64)
     mathcmp GOLDEN       compare with GOLDEN: printf and strtod must match
                          exactly, the math functions within 2 ULP (i386
                          evaluates in x87 extended precision, so its last
                          bit can differ from x86_64's). Prints "mathcmp: ok". */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long s = 12345;
static double rnd(double lo, double hi) { s = s * 1103515245UL + 12345UL; return lo + (hi - lo) * (double)((s >> 8) & 0xffffff) / 16777216.0; }

/* Distance in units in the last place between two finite doubles. */
static unsigned long long ulps(double a, double b)
{
    long long ia, ib;
    memcpy(&ia, &a, sizeof ia);
    memcpy(&ib, &b, sizeof ib);
    if (ia < 0) ia = -(ia & 0x7fffffffffffffffLL);
    if (ib < 0) ib = -(ib & 0x7fffffffffffffffLL);
    return ia > ib ? (unsigned long long)(ia - ib) : (unsigned long long)(ib - ia);
}

int main(int argc, char **argv)
{
    static const char *names[9] = { "exp", "log", "pow", "sin", "cos", "tan", "atan2", "sqrt", "sinh" };
    int i, k, bad = 0;
    double x, y, v[9], g[9];
    char buf[64], gbuf[64], gs[64];
    FILE *f = NULL;
    if (argc > 1 && (f = fopen(argv[1], "r")) == NULL) { perror(argv[1]); return 2; }
    for (i = 0; i < 400; i++) {
        x = rnd(-700, 700); y = rnd(0.001, 1000);
        v[0] = exp(x / 2); v[1] = log(y); v[2] = pow(y, rnd(-30, 30)); v[3] = sin(x); v[4] = cos(x);
        v[5] = tan(x / 10); v[6] = atan2(x, y); v[7] = sqrt(y); v[8] = sinh(x / 100);
        sprintf(buf, "%.17g", y * 1e-300);
        if (f == NULL) {
            printf("%.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g\n",
                   v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]);
            printf("%s %.17g\n", buf, strtod(buf, 0));
            continue;
        }
        if (fscanf(f, "%lf %lf %lf %lf %lf %lf %lf %lf %lf %63s %63s", &g[0], &g[1], &g[2], &g[3],
                   &g[4], &g[5], &g[6], &g[7], &g[8], gbuf, gs) != 11) {
            printf("mathcmp: %s is short or malformed at row %d\n", argv[1], i);
            return 1;
        }
        for (k = 0; k < 9; k++) {
            if (ulps(v[k], g[k]) > 2) {
                printf("row %d: %s = %.17g, expected %.17g\n", i, names[k], v[k], g[k]);
                bad++;
            }
        }
        /* gs is glibc's strtod of the same string, printed with %.17g, which
           identifies a double exactly. */
        if (strcmp(buf, gbuf) != 0) { printf("row %d: printf gives %s, expected %s\n", i, buf, gbuf); bad++; }
        else if (strtod(buf, 0) != strtod(gs, 0)) { printf("row %d: strtod(%s) differs\n", i, buf); bad++; }
    }
    if (f != NULL) {
        fclose(f);
        if (bad) { printf("mathcmp: %d differences\n", bad); return 1; }
        printf("mathcmp: ok\n");
    }
    return 0;
}
