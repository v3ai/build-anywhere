// sh-float-lit.c: floating-point literals for the POSIX shell backend.
// Added by build-anywhere; BSD 2-Clause, like the rest of pnut.
//
// The shell backend keeps a double as its IEEE-754 bit pattern in a 64-bit
// shell integer (see sh-float.c). A literal such as 0.1 is converted here,
// exactly and with round-to-nearest-even, to that bit pattern. The
// conversion uses big integers made of 16-bit limbs so that it only needs
// 32-bit int arithmetic, which keeps it correct both in the native pnut and
// in pnut-sh.sh.

#define FL_BN 320        // limbs: 5120 bits, more than 10^1125 * 2^60
#define FL_MAX_DIGITS 780

int fl_bn_n[FL_BN];      // numerator
int fl_bn_m[FL_BN];      // divisor (a power of ten)
int fl_bn_q[FL_BN];      // quotient
int fl_bits[4];          // result, in 16-bit pieces, fl_bits[0] lowest
char fl_digits[FL_MAX_DIGITS];
int fl_nd;               // number of digits in fl_digits
int fl_exp;              // value = fl_digits * 10^fl_exp
int fl_sticky;           // nonzero digits were dropped after fl_digits
int fl_rec;              // accum_digit also records digits for a float
int fl_ovf;              // the integer part overflowed an int

// x[0..len) = x * mul + add, mul and add below 65536; returns the length.
int fl_bn_muladd(int *x, int len, int mul, int add) {
  int i = 0;
  int carry = add;
  int t;
  while (i < len) {
    t = x[i] * mul + carry;
    x[i] = t & 65535;
    carry = t >> 16;
    i += 1;
  }
  while (carry != 0 && len < FL_BN) {
    x[len] = carry & 65535;
    carry = carry >> 16;
    len += 1;
  }
  return len;
}

int fl_bn_bitlen(int *x, int len) {
  int b;
  int v;
  while (len > 0 && x[len - 1] == 0) len -= 1;
  if (len == 0) return 0;
  v = x[len - 1];
  b = (len - 1) * 16;
  while (v != 0) { b += 1; v = v >> 1; }
  return b;
}

int fl_bn_bit(int *x, int len, int k) {
  if (k < 0 || k / 16 >= len) return 0;
  return (x[k / 16] >> (k % 16)) & 1;
}

// Whether any of the bits below position k is set.
int fl_bn_any_below(int *x, int len, int k) {
  int i = 0;
  if (k <= 0) return 0;
  while (i < len && i < k / 16) {
    if (x[i] != 0) return 1;
    i += 1;
  }
  if (i < len && k % 16 != 0 && (x[i] & ((1 << (k % 16)) - 1)) != 0) return 1;
  return 0;
}

// x <<= s, in place; returns the new length.
int fl_bn_shl(int *x, int len, int s) {
  int limbs = s / 16;
  int bits = s % 16;
  int i;
  int nlen;
  int hi;
  int lo;
  if (len == 0) return 0;
  nlen = len + limbs + 1;
  if (nlen > FL_BN) nlen = FL_BN;
  i = nlen - 1;
  while (i >= 0) {
    hi = 0;
    lo = 0;
    if (i - limbs >= 0 && i - limbs < len) hi = x[i - limbs];
    if (i - limbs - 1 >= 0 && i - limbs - 1 < len) lo = x[i - limbs - 1];
    if (bits == 0) x[i] = hi;
    else x[i] = ((hi << bits) | (lo >> (16 - bits))) & 65535;
    i -= 1;
  }
  while (nlen > 0 && x[nlen - 1] == 0) nlen -= 1;
  return nlen;
}

// x >>= s, in place; returns the new length.
int fl_bn_shr(int *x, int len, int s) {
  int limbs = s / 16;
  int bits = s % 16;
  int i = 0;
  int lo;
  int hi;
  while (i < len) {
    lo = 0;
    hi = 0;
    if (i + limbs < len) lo = x[i + limbs];
    if (i + limbs + 1 < len) hi = x[i + limbs + 1];
    x[i] = ((lo >> bits) | (hi << (16 - bits))) & 65535;
    i += 1;
  }
  while (len > 0 && x[len - 1] == 0) len -= 1;
  return len;
}

int fl_bn_ge(int *a, int alen, int *b, int blen) {
  int i;
  while (alen > 0 && a[alen - 1] == 0) alen -= 1;
  while (blen > 0 && b[blen - 1] == 0) blen -= 1;
  if (alen != blen) return alen > blen;
  i = alen - 1;
  while (i >= 0) {
    if (a[i] != b[i]) return a[i] > b[i];
    i -= 1;
  }
  return 1;
}

// a -= b, where a >= b.
void fl_bn_sub(int *a, int alen, int *b, int blen) {
  int i = 0;
  int borrow = 0;
  int t;
  while (i < alen) {
    t = a[i] - borrow;
    if (i < blen) t -= b[i];
    if (t < 0) { t += 65536; borrow = 1; } else { borrow = 0; }
    a[i] = t;
    i += 1;
  }
}

void fl_set_bits(int b0, int b1, int b2, int b3) {
  fl_bits[0] = b0;
  fl_bits[1] = b1;
  fl_bits[2] = b2;
  fl_bits[3] = b3;
}

// Round x * 2^e to a double (sticky: nonzero bits were already lost below
// x) and store its bit pattern, with sign neg, in fl_bits.
void fl_round(int *x, int xlen, int e, int sticky, int neg) {
  int len = fl_bn_bitlen(x, xlen);
  int biased;
  int drop;
  int rnd = 0;
  int m0;
  int m1;
  int m2;
  int m3;
  int sign = 0;
  if (neg) sign = 32768;
  if (len == 0) { fl_set_bits(0, 0, 0, sign); return; }
  biased = len - 1 + e + 1023;
  if (biased >= 1) drop = len - 53;
  else drop = -(e + 1074);
  if (drop > 0) {
    rnd = fl_bn_bit(x, xlen, drop - 1);
    if (fl_bn_any_below(x, xlen, drop - 1)) sticky = 1;
    xlen = fl_bn_shr(x, xlen, drop);
  } else if (drop < 0) {
    xlen = fl_bn_shl(x, xlen, -drop);
  }
  if (biased < 1) biased = 0;
  m0 = 0; m1 = 0; m2 = 0; m3 = 0;
  if (xlen > 0) m0 = x[0];
  if (xlen > 1) m1 = x[1];
  if (xlen > 2) m2 = x[2];
  if (xlen > 3) m3 = x[3];
  if (rnd && (sticky || (m0 & 1))) {
    m0 += 1;
    if (m0 == 65536) { m0 = 0; m1 += 1; }
    if (m1 == 65536) { m1 = 0; m2 += 1; }
    if (m2 == 65536) { m2 = 0; m3 += 1; }
  }
  if (biased == 0) {
    // subnormal: reaching 2^52 makes it the smallest normal number
    if (m3 >= 16) { biased = 1; m3 -= 16; }
  } else {
    if (m3 >= 32) { m3 = 16; biased += 1; } // rounded up to 2^53
    m3 -= 16;                               // the implicit bit
  }
  if (biased >= 2047) { fl_set_bits(0, 0, 0, sign | 32752); return; }
  fl_set_bits(m0, m1, m2, sign | (biased << 4) | m3);
}

// Convert digits[0..nd) * 10^exp10 (digits are values 0-9; sticky: nonzero
// digits were dropped after them) with sign neg; the result is in fl_bits.
void fl_convert(char *digits, int nd, int exp10, int sticky, int neg) {
  int nlen = 0;
  int mlen;
  int qlen;
  int i;
  int k;
  int bl;
  int s;
  while (nd > 0 && digits[0] == 0) { digits += 1; nd -= 1; }
  while (nd > 0 && digits[nd - 1] == 0) { nd -= 1; exp10 += 1; }
  if (nd == 0) { fl_round(fl_bn_n, 0, 0, 0, neg); return; }
  if (nd + exp10 > 310) { // at least 10^310: infinity
    if (neg) fl_set_bits(0, 0, 0, 65520); else fl_set_bits(0, 0, 0, 32752);
    return;
  }
  if (nd + exp10 < -324) { // below 10^-324: zero
    fl_round(fl_bn_n, 0, 0, 0, neg);
    return;
  }
  i = 0;
  while (i < nd) {
    nlen = fl_bn_muladd(fl_bn_n, nlen, 10, digits[i]);
    i += 1;
  }
  if (sticky) { // stands for the dropped digits; only matters for ties
    nlen = fl_bn_muladd(fl_bn_n, nlen, 10, 1);
    exp10 -= 1;
  }
  if (exp10 >= 0) {
    i = 0;
    while (i < exp10) {
      nlen = fl_bn_muladd(fl_bn_n, nlen, 10, 0);
      i += 1;
    }
    fl_round(fl_bn_n, nlen, 0, 0, neg);
    return;
  }
  // N / 10^-exp10: scale N by 2^k so that the quotient has 57+ bits
  fl_bn_m[0] = 1;
  mlen = 1;
  i = 0;
  while (i < -exp10) {
    mlen = fl_bn_muladd(fl_bn_m, mlen, 10, 0);
    i += 1;
  }
  k = fl_bn_bitlen(fl_bn_m, mlen) + 57 - fl_bn_bitlen(fl_bn_n, nlen);
  if (k < 0) k = 0;
  nlen = fl_bn_shl(fl_bn_n, nlen, k);
  bl = fl_bn_bitlen(fl_bn_n, nlen) - fl_bn_bitlen(fl_bn_m, mlen);
  if (bl < 0) bl = 0;
  mlen = fl_bn_shl(fl_bn_m, mlen, bl);
  qlen = bl / 16 + 1;
  i = 0;
  while (i < qlen) { fl_bn_q[i] = 0; i += 1; }
  s = bl;
  while (s >= 0) { // binary long division, one quotient bit at a time
    if (fl_bn_ge(fl_bn_n, nlen, fl_bn_m, mlen)) {
      fl_bn_sub(fl_bn_n, nlen, fl_bn_m, mlen);
      fl_bn_q[s / 16] = fl_bn_q[s / 16] | (1 << (s % 16));
    }
    mlen = fl_bn_shr(fl_bn_m, mlen, 1);
    s -= 1;
  }
  fl_round(fl_bn_q, qlen, -k, fl_bn_bitlen(fl_bn_n, nlen) != 0, neg);
}

// Lexer support: the digits of a literal are collected as it is read.

int fl_lit_ready = 0;

// pnut-sh does not zero global arrays, and bash and ksh reject reading an
// element that was never set, so the arrays are cleared before first use.
void fl_lit_init() {
  int i = 0;
  fl_lit_ready = 1;
  while (i < FL_BN) {
    fl_bn_n[i] = 0;
    fl_bn_m[i] = 0;
    fl_bn_q[i] = 0;
    i += 1;
  }
  i = 0;
  while (i < FL_MAX_DIGITS) {
    fl_digits[i] = 0;
    i += 1;
  }
  i = 0;
  while (i < 4) {
    fl_bits[i] = 0;
    i += 1;
  }
}

void fl_lex_begin() {
  if (!fl_lit_ready) fl_lit_init();
  fl_nd = 0;
  fl_exp = 0;
  fl_sticky = 0;
  fl_ovf = 0;
}

// A digit before the decimal point.
void fl_lex_digit(int d) {
  if (fl_nd == 0 && d == 0) return;
  if (fl_nd < FL_MAX_DIGITS) {
    fl_digits[fl_nd] = d;
    fl_nd += 1;
  } else {
    fl_exp += 1;
    if (d != 0) fl_sticky = 1;
  }
}

// A digit after the decimal point.
void fl_lex_frac_digit(int d) {
  if (fl_nd == 0 && d == 0) {
    fl_exp -= 1;
  } else if (fl_nd < FL_MAX_DIGITS) {
    fl_digits[fl_nd] = d;
    fl_nd += 1;
    fl_exp -= 1;
  } else if (d != 0) {
    fl_sticky = 1;
  }
}

// Reads the digits after the decimal point (already skipped), an optional
// exponent and suffix, and returns the literal's bits as a heap object.
int fl_lex_rest() {
  int esign = 1;
  int e = 0;
  int obj;
  while ('0' <= ch && ch <= '9') {
    fl_lex_frac_digit(ch - '0');
    get_ch();
  }
  if (ch == 'e' || ch == 'E') {
    get_ch();
    if (ch == '+') {
      get_ch();
    } else if (ch == '-') {
      esign = -1;
      get_ch();
    }
    if (ch < '0' || ch > '9') syntax_error("invalid floating-point exponent");
    while ('0' <= ch && ch <= '9') {
      if (e < 100000) e = e * 10 + ch - '0';
      get_ch();
    }
  }
  if (ch == 'f' || ch == 'F' || ch == 'l' || ch == 'L') get_ch();
  fl_convert(fl_digits, fl_nd, fl_exp + esign * e, fl_sticky, 0);
  obj = alloc_obj(4);
  heap[obj] = fl_bits[0];
  heap[obj + 1] = fl_bits[1];
  heap[obj + 2] = fl_bits[2];
  heap[obj + 3] = fl_bits[3];
  return obj;
}
