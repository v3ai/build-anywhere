/* main.c: exercises Universal C's port.h and p_util.c (copied verbatim from
   https://github.com/v3ai/universal-c, UNIVERSAL_C.md sections 4 and 5).
   The output is the same on every tier and every platform. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "p_util.h"

static int failures = 0;

static void check(int ok, const char *what)
{
    if (!ok) {
        failures++;
        printf("FAIL: %s\n", what);
    }
}

int main(void)
{
    int r;
    size_t z;
    char small[6];
    unsigned char bytes[4];
#if P_HAS_64
    char dec[32];
#endif

    check(p_add_int(INT_MAX - 1, 1, &r) && r == INT_MAX, "p_add_int fits");
    check(!p_add_int(INT_MAX, 1, &r), "p_add_int overflow");
    check(p_mul_int(-46341, 46340, &r) && r == -2147441940L, "p_mul_int fits");
    check(!p_mul_int(46341, 46341, &r), "p_mul_int overflow");
    check(p_mul_size(1000, 1000, &z) && z == 1000000, "p_mul_size");
    check(p_strlcpy(small, "universal", sizeof small) == 9 && strcmp(small, "unive") == 0,
          "p_strlcpy truncates");
    p_store_u32le(bytes, (p_u32)0x12345678UL);
    check(bytes[0] == 0x78 && bytes[3] == 0x12, "p_store_u32le");
    check(p_load_u32be(bytes) == (p_u32)0x78563412UL, "p_load_u32be");
    check(p_rotl32((p_u32)0x80000001UL, 1) == (p_u32)0x00000003UL, "p_rotl32");
#if P_HAS_64
    check(strcmp(p_u64_to_dec(dec, P_U64_C(18446744073709551615)), "18446744073709551615") == 0, "p_u64_to_dec");
#endif
    printf("universal: %s\n", failures == 0 ? "ok" : "FAILED");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
