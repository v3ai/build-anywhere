#!/bin/sh
# Compile libc/ba_*.c with the host compiler, rename every function they
# define to ba_<name> (objcopy --redefine-syms), and compare them with the
# host C library. Needs cc, objcopy and glibc.
#
# LIBC_CC=COMMAND compiles libc/ba_*.c with another compiler (for example
# the TinyCC that build-anywhere bootstraps), still against glibc's headers,
# to check that compiler's code generation too.
set -e
cd "$(dirname "$0")/../.."
CC=${CC:-cc}
LIBC_CC=${LIBC_CC:-}
LIBC_LIBS=${LIBC_LIBS:-}   # extra libraries for LIBC_CC objects (libtcc1.a)
OBJCOPY=${OBJCOPY:-objcopy}
out=${TMPDIR:-/tmp}/ba-libc-test.$$
mkdir -p "$out"
trap 'rm -rf "$out"' EXIT

for f in libc/ba_math.c libc/ba_fmt.c libc/ba_time.c libc/ba_misc.c; do
    o=$out/$(basename "$f" .c).o
    if [ -n "$LIBC_CC" ]; then
        $LIBC_CC -Ilibc -c "$f" -o "$o"
    else
        $CC -std=gnu99 -O1 -fno-builtin -U_FORTIFY_SOURCE -Wall -Wextra -Werror \
            -Ilibc -c "$f" -o "$o"
    fi
    $OBJCOPY --redefine-syms=tests/libc/rename.syms "$o"
done
if [ -n "$LIBC_CC" ]; then   # TinyCC's va_arg support lives in our libc
    $LIBC_CC -c libc/ba_va.c -o "$out/ba_va.o"
fi
$CC -std=gnu99 -O1 -fno-builtin -Wall -Wno-format-truncation -Wno-format-overflow \
    -c tests/libc/test_libc.c -o "$out/test_libc.o"
$CC -o "$out/test_libc" "$out"/*.o $LIBC_LIBS -lm
"$out/test_libc"
