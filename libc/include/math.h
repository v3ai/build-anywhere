/* math.h: build-anywhere libc. */
#ifndef _BA_MATH_H
#define _BA_MATH_H
double __ba_inf(void);
double __ba_nan(void);
#define HUGE_VAL (__ba_inf())
#define INFINITY ((float)__ba_inf())
#define NAN ((float)__ba_nan())
double acos(double x);
double asin(double x);
double atan(double x);
double atan2(double y, double x);
double cos(double x);
double sin(double x);
double tan(double x);
double cosh(double x);
double sinh(double x);
double tanh(double x);
double exp(double x);
double frexp(double x, int *exp);
double ldexp(double x, int exp);
double log(double x);
double log10(double x);
double modf(double x, double *iptr);
double pow(double x, double y);
double sqrt(double x);
double ceil(double x);
double fabs(double x);
double floor(double x);
double fmod(double x, double y);
#endif
