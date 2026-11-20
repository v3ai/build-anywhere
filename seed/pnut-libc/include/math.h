/* math.h: build-anywhere shell tier. double and float are computed in
   software (pnut-libc/float.c); float is computed as double. */
#ifndef _BA_SH_MATH_H
#define _BA_SH_MATH_H

#define HUGE_VAL 1e999
#define HUGE_VALF 1e999
#define INFINITY 1e999
#define NAN (ba_nan())
#define M_E        2.7182818284590452354
#define M_LOG2E    1.4426950408889634074
#define M_LOG10E   0.43429448190325182765
#define M_LN2      0.69314718055994530942
#define M_LN10     2.30258509299404568402
#define M_PI       3.14159265358979323846
#define M_PI_2     1.57079632679489661923
#define M_PI_4     0.78539816339744830962
#define M_1_PI     0.31830988618379067154
#define M_2_PI     0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2    1.41421356237309504880
#define M_SQRT1_2  0.70710678118654752440

#define FP_NAN       0
#define FP_INFINITE  1
#define FP_ZERO      2
#define FP_SUBNORMAL 3
#define FP_NORMAL    4
#define isnan(x)      ba_isnan(x)
#define isinf(x)      ba_isinf(x)
#define isfinite(x)   ba_isfinite(x)
#define isnormal(x)   (ba_fpclassify(x) == FP_NORMAL)
#define signbit(x)    ba_signbit(x)
#define fpclassify(x) ba_fpclassify(x)
int ba_isnan(double x);
int ba_isinf(double x);
int ba_isfinite(double x);
int ba_signbit(double x);
int ba_fpclassify(double x);
double ba_nan(void);

double fabs(double x);
double sqrt(double x);
double cbrt(double x);
double hypot(double x, double y);
double floor(double x);
double ceil(double x);
double trunc(double x);
double round(double x);
double rint(double x);
double nearbyint(double x);
long lround(double x);
double fmod(double x, double y);
double remainder(double x, double y);
double modf(double x, double *ip);
double frexp(double x, int *e);
double ldexp(double x, int n);
double scalbn(double x, int n);
int ilogb(double x);
double logb(double x);
double copysign(double x, double y);
double fmin(double x, double y);
double fmax(double x, double y);
double fdim(double x, double y);
double fma(double x, double y, double z);
double nan(char *tag);
double exp(double x);
double exp2(double x);
double expm1(double x);
double log(double x);
double log2(double x);
double log10(double x);
double log1p(double x);
double pow(double x, double y);
double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
double sinh(double x);
double cosh(double x);
double tanh(double x);
double asinh(double x);
double acosh(double x);
double atanh(double x);

#define fabsf fabs
#define sqrtf sqrt
#define floorf floor
#define ceilf ceil
#define truncf trunc
#define roundf round
#define fmodf fmod
#define expf exp
#define logf log
#define log10f log10
#define powf pow
#define sinf sin
#define cosf cos
#define tanf tan
#define asinf asin
#define acosf acos
#define atanf atan
#define atan2f atan2
#define fminf fmin
#define fmaxf fmax
#define hypotf hypot
#endif
