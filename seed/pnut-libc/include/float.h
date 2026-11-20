/* float.h: build-anywhere shell tier. double is IEEE-754 binary64; float
   uses the same representation (it is computed as double) but these
   limits describe the C type. */
#ifndef _BA_SH_FLOAT_H
#define _BA_SH_FLOAT_H
#define FLT_RADIX 2
#define FLT_ROUNDS 1
#define FLT_EVAL_METHOD 1
#define DECIMAL_DIG 17
#define DBL_MANT_DIG 53
#define DBL_DIG 15
#define DBL_DECIMAL_DIG 17
#define DBL_MIN_EXP (-1021)
#define DBL_MAX_EXP 1024
#define DBL_MIN_10_EXP (-307)
#define DBL_MAX_10_EXP 308
#define DBL_MAX 1.7976931348623157e308
#define DBL_MIN 2.2250738585072014e-308
#define DBL_TRUE_MIN 4.9406564584124654e-324
#define DBL_EPSILON 2.2204460492503131e-16
#define FLT_MANT_DIG 24
#define FLT_DIG 6
#define FLT_DECIMAL_DIG 9
#define FLT_MIN_EXP (-125)
#define FLT_MAX_EXP 128
#define FLT_MIN_10_EXP (-37)
#define FLT_MAX_10_EXP 38
#define FLT_MAX 3.40282347e+38
#define FLT_MIN 1.17549435e-38
#define FLT_TRUE_MIN 1.40129846e-45
#define FLT_EPSILON 1.19209290e-07
#define LDBL_MANT_DIG DBL_MANT_DIG
#define LDBL_DIG DBL_DIG
#define LDBL_MIN_EXP DBL_MIN_EXP
#define LDBL_MAX_EXP DBL_MAX_EXP
#define LDBL_MIN_10_EXP DBL_MIN_10_EXP
#define LDBL_MAX_10_EXP DBL_MAX_10_EXP
#define LDBL_MAX DBL_MAX
#define LDBL_MIN DBL_MIN
#define LDBL_EPSILON DBL_EPSILON
#endif
