#!/bin/sh
# bootstrap-tcc.sh: build a C compiler from nothing but a POSIX shell.
#
#   bootstrap-tcc.sh --arch ARCH --shell SH --seed DIR --libc DIR --out DIR --work DIR
#
# ARCH is x86_64 or i386 (Linux only). The chain is:
#
#   1. SH runs pnut-sh.sh (pnut's C compiler, itself a shell script) on
#      pnut's C source and gets pnut-exe.sh: the same compiler, emitting
#      x86 machine code, still as a shell script.            (~1 minute)
#   2. SH runs pnut-exe.sh on pnut's source: a native pnut-exe. (~3 minutes)
#   3. That pnut-exe recompiles pnut with every feature on (twice: the
#      minimal pnut ignores -D values such as the heap size).
#   4. pnut-exe compiles TinyCC 0.9.27 (with pnut's small libc): tcc-pnut.
#   5. Each TinyCC compiles the build-anywhere libc (LIBC, a small C library
#      that is enough for TinyCC itself) and the next TinyCC:
#      tcc-pnut -> boot0 -> boot1 -> boot2 -> boot3. boot2 and boot3 must be
#      byte-identical (a fixed point), which shows the chain converged.
#   6. The final TinyCC builds musl (SEED/musl), a complete C library, for
#      the programs it compiles; SEED/linux-headers adds <linux/*.h>.
#
# Installs OUT/bin/tcc, OUT/lib (crt files, libc.a, libtcc1.a, include/)
# and OUT/bin/cc, a cc-compatible wrapper. Steps 1-4 are kept in WORK, so
# an interrupted run resumes after the last finished step.
set -eu

die() { printf 'bootstrap-tcc: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-anywhere: bootstrap: %s\n' "$*" >&2; }
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

ARCH= SH= SEED= LIBC= OUT= WORK=
while [ $# -gt 0 ]; do
    case $1 in
        --arch) ARCH=$2 ;;
        --shell) SH=$2 ;;
        --seed) SEED=$2 ;;
        --libc) LIBC=$2 ;;
        --out) OUT=$2 ;;
        --work) WORK=$2 ;;
        *) die "unknown option: $1" ;;
    esac
    shift 2 || die "missing value for $1"
done
[ -n "$ARCH" ] && [ -n "$SH" ] && [ -n "$SEED" ] && [ -n "$LIBC" ] && [ -n "$OUT" ] && [ -n "$WORK" ] ||
    die "usage: bootstrap-tcc.sh --arch ARCH --shell SH --seed DIR --libc DIR --out DIR --work DIR"

case $ARCH in
    x86_64)
        PNUT_ARCH=x86_64_linux TCC_ARCH=X86_64 RT=
        # TinyCC's x86_64 backend needs more room than pnut's defaults.
        SIZES="-DHEAP_SIZE=2048000 -DMAX_CODE_SIZE=2048000 -DPROGRAM_SIZE=2048000" ;;
    i386|x86)
        PNUT_ARCH=i386_linux TCC_ARCH=I386 RT="-rt $SEED/pnut/arith64.c"
        SIZES="-DSUPPORT_EMULATED_INT64" ;;
    *) die "unsupported architecture: $ARCH (x86_64 and i386 only)" ;;
esac

mkdir -p "$WORK" "$OUT"
WORK=$(cd "$WORK" && pwd)
OUT=$(cd "$OUT" && pwd)
cd "$WORK"

P=$SEED/pnut
T=$SEED/tcc
PNUT_OPTS="-Dtarget_$PNUT_ARCH -DONE_PASS_GENERATOR"
PNUT_FULL="$PNUT_OPTS -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT -DNO_BUILTIN_LIBC $SIZES"

# ---- 1-3: pnut ----------------------------------------------------------
if [ ! -f step1.done ]; then
    say "[1/6] compiling pnut to x86 with pnut-sh.sh, in $SH (about 1 minute)"
    "$SH" "$SEED/pnut-sh.sh" "$P/pnut.c" $PNUT_OPTS -DPNUT_BOOTSTRAP >pnut-exe.sh.tmp
    mv pnut-exe.sh.tmp pnut-exe.sh
    : >step1.done
fi
if [ ! -f step2.done ]; then
    say "[2/6] running pnut-exe.sh to make a native pnut (about 3 minutes)"
    rm -f pnut-exe-min
    # pnut-exe.sh cannot set the execute bit itself: create the file first.
    : >pnut-exe-min
    chmod 755 pnut-exe-min
    "$SH" pnut-exe.sh "$P/pnut.c" $PNUT_OPTS -DPNUT_BOOTSTRAP -o pnut-exe-min
    : >step2.done
fi
if [ ! -f step3.done ]; then
    say "[3/6] rebuilding pnut with all features"
    # The minimal pnut ignores -D values, so the heap sizes only take effect
    # when the full pnut compiles itself once more.
    ./pnut-exe-min "$P/pnut.c" $PNUT_FULL -o pnut-exe0
    ./pnut-exe0 "$P/pnut.c" $PNUT_FULL $RT \
        -I "$P/portable_libc/include/" "$P/portable_libc/libc.c" -o pnut-exe
    : >step3.done
fi

# ---- 4: TinyCC built by pnut --------------------------------------------
TCC_CONFIG="-DTCC_TARGET_$TCC_ARCH=1 -DBOOTSTRAP=1 -DHAVE_LONG_LONG=1 -DONE_SOURCE=1
 -DCONFIG_TCCBOOT=1 -DCONFIG_TCC_STATIC=1 -DCONFIG_USE_LIBGCC=1"
# Every path is relative to -B, so the compilers do not depend on where they
# are installed and successive stages can be compared byte for byte.
set -- \
    -DTCC_VERSION='"0.9.27"' \
    -DCONFIG_SYSROOT='""' \
    -DCONFIG_TCCDIR='"/nonexistent/build-anywhere-needs-B"' \
    -DCONFIG_TCC_CRTPREFIX='"{B}"' \
    -DCONFIG_TCC_LIBPATHS='"{B}"' \
    -DCONFIG_TCC_SYSINCLUDEPATHS='"{B}/include"' \
    -DCONFIG_TCC_ELFINTERP='"/nonexistent/ld.so"' \
    -DTCC_LIBGCC='"/nonexistent/libgcc.a"' \
    -DTCC_LIBTCC1='"libtcc1.a"'

if [ ! -x tcc-pnut ]; then
    say "[4/6] compiling TinyCC with pnut"
    ./pnut-exe "$T/tcc.c" $TCC_CONFIG -DPNUT_CC=1 -D__intptr_t_defined=1 "$@" \
        $RT -I "$P/portable_libc/include/" "$P/portable_libc/libc.c" -o tcc-pnut.tmp
    chmod 755 tcc-pnut.tmp
    mv tcc-pnut.tmp tcc-pnut
fi

# ---- 5: TinyCC built by TinyCC ------------------------------------------
stage() { # PREV_CC NAME
    prev=$1 name=$2 lib=$WORK/$2-lib
    shift 2
    rm -rf "$lib"
    mkdir -p "$lib/include/sys" "$lib/obj"
    cp "$LIBC"/include/*.h "$lib/include/"
    cp "$LIBC"/include/sys/*.h "$lib/include/sys/"
    for h in stdarg.h float.h stdbool.h varargs.h; do
        cp "$T/include/$h" "$lib/include/$h"
    done
    : >"$lib/obj/empty.c"
    "$prev" -B "$lib" -c "$lib/obj/empty.c" -o "$lib/crti.o"
    "$prev" -B "$lib" -c "$lib/obj/empty.c" -o "$lib/crtn.o"
    "$prev" -B "$lib" -c "$LIBC/crt1.c" -o "$lib/crt1.o"
    objs=
    for src in "$LIBC"/ba_*.c; do
        # tcc-pnut cannot read floating-point literals (pnut has no floating
        # point), so boot0's libc goes without <math.h>; TinyCC needs none of
        # it. Later stages build the whole libc.
        if [ "$prev" = ./tcc-pnut ] && [ "${src##*/}" = ba_math.c ]; then
            continue
        fi
        o=$lib/obj/$(basename "$src" .c).o
        "$prev" -B "$lib" -c "$src" -o "$o"
        objs="$objs $o"
    done
    "$prev" -ar rc "$lib/libc.a" $objs
    # libtcc1 (TinyCC's helpers for long long and float conversions). The
    # x86_64 va_list support is in the build-anywhere libc (ba_va.c).
    "$prev" -B "$lib" -c "$T/lib/libtcc1.c" -o "$lib/obj/libtcc1.o"
    "$prev" -ar rc "$lib/libtcc1.a" "$lib/obj/libtcc1.o"
    "$prev" -B "$lib" -static $TCC_CONFIG -DHAVE_FLOAT=1 -DHAVE_BITFIELD=1 -DHAVE_SETJMP=1 \
        "$@" "$T/tcc.c" -o "tcc-$name"
}

say "[5/6] rebuilding TinyCC with itself until it reaches a fixed point"
prev=./tcc-pnut
for s in boot0 boot1 boot2 boot3; do
    stage "$prev" "$s" "$@"
    prev=./tcc-$s
done
cmp tcc-boot2 tcc-boot3 >/dev/null ||
    die "TinyCC did not reach a fixed point (tcc-boot2 and tcc-boot3 differ)"
./tcc-boot3 -v >/dev/null 2>&1 || die "the final TinyCC does not run"

# ---- 6: musl -----------------------------------------------------------
say "[6/6] building the C library (musl) with TinyCC"
rm -rf musl-lib
"$SH" "$SEED/build-musl.sh" --arch "$ARCH" --cc ./tcc-boot3 --src "$SEED/musl" \
    --tcc "$T" --balibc "$LIBC" --out musl-lib --work musl-work >/dev/null
cp -R "$SEED/linux-headers/." musl-lib/include/
rm -f musl-lib/include/README.sabotage.md
rm -rf musl-work
printf '#include <stdio.h>\n#include <math.h>\nint main(void){printf("%%.3f\\n",sqrt(2.0));return 0;}\n' >musl-check.c
./tcc-boot3 -B musl-lib -static musl-check.c -o musl-check ||
    die "TinyCC cannot link a program with musl"
[ "$(./musl-check)" = 1.414 ] || die "a program linked with musl does not run"

# ---- install ------------------------------------------------------------
rm -rf "$OUT/bin" "$OUT/lib"
mkdir -p "$OUT/bin"
cp tcc-boot3 "$OUT/bin/tcc"
cp -R musl-lib "$OUT/lib"
{
    echo '#!/bin/sh'
    echo '# cc wrapper for TinyCC built by build-anywhere (static, musl).'
    echo "exec $(q "$OUT/bin/tcc") -B $(q "$OUT/lib") -static \"\$@\""
} >"$OUT/bin/cc.tmp"
chmod 755 "$OUT/bin/cc.tmp"
mv "$OUT/bin/cc.tmp" "$OUT/bin/cc"
say "done: $OUT/bin/cc"
