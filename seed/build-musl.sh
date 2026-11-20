#!/bin/sh
# build-musl.sh: build musl (a complete C library) with the bootstrapped
# TinyCC, using nothing but a POSIX shell, sed and TinyCC (no make).
#
#   build-musl.sh --arch ARCH --cc CC --src DIR --tcc DIR --balibc DIR --out DIR --work DIR
#
# ARCH is x86_64 or i386. CC is a TinyCC binary. SRC is the musl source tree
# (seed/musl), TCC the TinyCC source tree (seed/tcc, for libtcc1.c), BALIBC
# the build-anywhere libc (for its x86_64 <stdarg.h> run-time, ba_va.c).
#
# Installs into OUT, laid out the way TinyCC expects for "-B OUT":
#   OUT/crt1.o crti.o crtn.o libc.a libtcc1.a (and empty libm.a, libpthread.a,
#   ... since musl keeps all of them in libc.a), OUT/include/ (musl's headers).
# This follows musl's own Makefile: every src/*/*.c, except that a file in
# src/*/ARCH/ with the same base name replaces the generic one.
set -eu

die() { printf 'build-musl: %s\n' "$*" >&2; exit 1; }

ARCH= CC= SRC= TCC= BALIBC= OUT= WORK=
while [ $# -gt 0 ]; do
    case $1 in
        --arch) ARCH=$2 ;;
        --cc) CC=$2 ;;
        --src) SRC=$2 ;;
        --tcc) TCC=$2 ;;
        --balibc) BALIBC=$2 ;;
        --out) OUT=$2 ;;
        --work) WORK=$2 ;;
        *) die "unknown option: $1" ;;
    esac
    shift 2 || die "missing value for $1"
done
[ -n "$ARCH" ] && [ -n "$CC" ] && [ -n "$SRC" ] && [ -n "$TCC" ] && [ -n "$BALIBC" ] &&
    [ -n "$OUT" ] && [ -n "$WORK" ] ||
    die "usage: build-musl.sh --arch ARCH --cc CC --src DIR --tcc DIR --balibc DIR --out DIR --work DIR"
case $ARCH in
    x86_64) M=x86_64 ;;
    i386|x86) M=i386 ;;
    *) die "unsupported architecture: $ARCH" ;;
esac

rm -rf "$WORK"
mkdir -p "$WORK/include/bits" "$WORK/internal" "$WORK/obj"
W=$(cd "$WORK" && pwd)

# ---- generated headers (as musl's Makefile makes them) ------------------
sed -f "$SRC/tools/mkalltypes.sed" "$SRC/arch/$M/bits/alltypes.h.in" \
    "$SRC/include/alltypes.h.in" >"$W/include/bits/alltypes.h"
cp "$SRC/arch/$M/bits/syscall.h.in" "$W/include/bits/syscall.h"
sed -n -e 's/__NR_/SYS_/p' <"$SRC/arch/$M/bits/syscall.h.in" >>"$W/include/bits/syscall.h"
printf '#define VERSION "%s"\n' "$(cat "$SRC/VERSION")" >"$W/internal/version.h"

CFLAGS="-std=c99 -nostdinc -D_XOPEN_SOURCE=700
 -I$SRC/arch/$M -I$SRC/arch/generic -I$W/internal -I$SRC/src/include
 -I$SRC/src/internal -I$W/include -I$SRC/include"

# ---- compile ------------------------------------------------------------
n=0
objs=$W/objs.list
: >"$objs"
compile() { # SRCFILE
    rel=${1#"$SRC/"}
    o=$W/obj/$(printf '%s' "$rel" | sed 's|/|_|g').o
    # shellcheck disable=SC2086
    "$CC" $CFLAGS -c "$1" -o "$o" || die "failed to compile $rel"
    printf '%s\n' "$o" >>"$objs"
    n=$((n + 1))
}
for d in "$SRC"/src/* "$SRC/src/malloc/mallocng"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.c; do
        [ -f "$f" ] || continue
        b=${f##*/}
        b=${b%.c}
        if [ -f "$d/$M/$b.s" ] || [ -f "$d/$M/$b.S" ] || [ -f "$d/$M/$b.c" ]; then
            continue
        fi
        compile "$f"
    done
    for f in "$d/$M"/*.s "$d/$M"/*.S "$d/$M"/*.c; do
        [ -f "$f" ] && compile "$f"
    done
done
printf 'build-musl: compiled %s files\n' "$n" >&2

# ---- install ------------------------------------------------------------
mkdir -p "$OUT/include"
OUT=$(cd "$OUT" && pwd)
# On x86_64, TinyCC's va_start/va_arg call __va_start/__va_arg: the
# build-anywhere libc's implementation goes into libc.a (not libtcc1.a, which
# TinyCC links after libc.a, so it could not use abort()).
if [ "$M" = x86_64 ]; then
    "$CC" -nostdinc -c "$BALIBC/ba_va.c" -o "$W/obj/ba_va.o"
    printf '%s\n' "$W/obj/ba_va.o" >>"$objs"
fi
rm -f "$OUT/libc.a"
# shellcheck disable=SC2046
"$CC" -ar rc "$OUT/libc.a" $(cat "$objs")
# shellcheck disable=SC2086
"$CC" $CFLAGS -DCRT -c "$SRC/crt/crt1.c" -o "$OUT/crt1.o"
for crt in crti crtn; do
    # shellcheck disable=SC2086
    "$CC" $CFLAGS -c "$SRC/crt/$M/$crt.s" -o "$OUT/$crt.o"
done
# musl keeps the maths, threads, etc. in libc.a; -lm and friends link empty
# archives, as with musl's own install.
for l in m rt pthread crypt util xnet resolv dl; do
    printf '!<arch>\n' >"$OUT/lib$l.a"
done

# TinyCC's helpers for long long and float conversions.
"$CC" -nostdinc -c "$TCC/lib/libtcc1.c" -o "$W/libtcc1.o"
rm -f "$OUT/libtcc1.a"
"$CC" -ar rc "$OUT/libtcc1.a" "$W/libtcc1.o"

# Headers: generic, then this architecture's bits, then the generated ones.
cp -R "$SRC/include/." "$OUT/include/"
rm -f "$OUT/include/alltypes.h.in"
mkdir -p "$OUT/include/bits"
cp "$SRC/arch/generic/bits/"*.h "$OUT/include/bits/"
cp "$SRC/arch/$M/bits/"*.h "$OUT/include/bits/"
cp "$W/include/bits/alltypes.h" "$W/include/bits/syscall.h" "$OUT/include/bits/"
