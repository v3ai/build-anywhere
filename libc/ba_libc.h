/*
 * ba_libc.h: internal declarations shared by the build-anywhere libc
 * complement (libc/ba_*.c). Not installed; programs never include it.
 */
#ifndef BA_LIBC_H
#define BA_LIBC_H

double __ba_inf(void);
double __ba_nan(void);

/* Exact decimal expansion of a finite double v > 0: writes its significant
   digits (no leading or trailing zeros) to digs and returns how many, with
   v == 0.DIGITS * 10^(*dp). digs must hold BA_MAX_DIGITS chars. */
#define BA_MAX_DIGITS 800
int __ba_exact_digits(double v, char *digs, int *dp);

void __ba_assert_fail(const char *expr, const char *file, int line);

#endif
