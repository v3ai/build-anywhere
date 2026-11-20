/* mathcmp.c: prints math, printf and strtod results for fixed inputs. Its
   output must match mathcmp.golden on every architecture (tests/run.sh). */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned long s = 12345;
static double rnd(double lo, double hi) { s = s * 1103515245UL + 12345UL; return lo + (hi - lo) * (double)((s >> 8) & 0xffffff) / 16777216.0; }
int main(void) {
    int i; double x, y; char buf[64];
    for (i = 0; i < 400; i++) {
        x = rnd(-700, 700); y = rnd(0.001, 1000);
        printf("%.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g\n",
            exp(x / 2), log(y), pow(y, rnd(-30, 30)), sin(x), cos(x), tan(x / 10),
            atan2(x, y), sqrt(y), sinh(x / 100));
        sprintf(buf, "%.17g", y * 1e-300); printf("%s %.17g\n", buf, strtod(buf, 0));
    }
    return 0;
}
