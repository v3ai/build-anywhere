#!/bin/sh
# vendor-musl.sh: (re)create seed/musl and seed/linux-headers from upstream
# tarballs. Maintainers only; users never run this.
#
#   tools/vendor-musl.sh MUSL_TARBALL KERNEL_HEADERS_TARBALL OUT_DIR
#
#   MUSL_TARBALL            https://musl.libc.org/releases/musl-1.2.5.tar.gz
#   KERNEL_HEADERS_TARBALL  https://github.com/sabotage-linux/kernel-headers/
#                           archive/refs/tags/v6.12.77.tar.gz
#
# (the SHA-256 of each is checked below). Needs tar, gzip, patch, sed and
# sha256sum (or shasum). Writes:
#
#   OUT_DIR/musl/           musl 1.2.5 for i386 and x86_64, patched so that
#                           TinyCC 0.9.27 builds it (tools/patches/)
#   OUT_DIR/linux-headers/  the Linux UAPI headers in tools/linux-headers.list,
#                           with everything they include, for x86
set -eu

[ $# -eq 3 ] || { echo "usage: $0 MUSL_TARBALL KERNEL_HEADERS_TARBALL OUT_DIR" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
MUSL_TGZ=$1
KH_TGZ=$2
mkdir -p "$3"
OUT=$(cd "$3" && pwd)
TMP=$OUT/.vendor-musl-tmp

MUSL_SHA=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
KH_SHA=cd70720ccdae889ffb4c4e7764f11b8c26add20d6bde78c0012225d52d38d3cb

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi |
        sed 's/ .*//'
}
[ "$(sha256 "$MUSL_TGZ")" = "$MUSL_SHA" ] || { echo "$MUSL_TGZ: wrong SHA-256" >&2; exit 1; }
[ "$(sha256 "$KH_TGZ")" = "$KH_SHA" ] || { echo "$KH_TGZ: wrong SHA-256" >&2; exit 1; }

rm -rf "$TMP" "$OUT/musl" "$OUT/linux-headers"
mkdir -p "$TMP"

# ---- musl -----------------------------------------------------------------
echo "musl: unpacking 1.2.5"
gzip -dc "$MUSL_TGZ" | (cd "$TMP" && tar -xf -)
M=$TMP/musl-1.2.5
cd "$M"
# Only static i386 and x86_64 libraries are built, by seed/build-musl.sh.
rm -rf .gitignore Makefile configure INSTALL dist dynamic.list ldso compat \
    tools/*.sh tools/*.in tools/*.mak tools/add-cfi.*
for a in arch/*; do
    case ${a##*/} in generic|i386|x86_64) ;; *) rm -rf "$a" ;; esac
done
for a in aarch64 arm loongarch64 m68k microblaze mips mips64 mipsn32 or1k \
         powerpc powerpc64 riscv32 riscv64 s390x sh x32; do
    find src crt -mindepth 1 -type d -name "$a" -prune -exec rm -rf {} +
done
# mallocng is the default allocator; TinyCC has no complex types.
rm -rf src/malloc/oldmalloc src/complex
# These maths files are inline assembly with x87/SSE operand constraints that
# TinyCC does not have; musl's portable C versions are used instead.
(cd src/math/x86_64 && rm -f fabs.c fabsf.c fabsl.c fmodl.c llrint.c llrintf.c \
    llrintl.c lrint.c lrintf.c lrintl.c remainderl.c remquol.c rintl.c sqrt.c \
    sqrtf.c sqrtl.c)
(cd src/math/i386 && rm -f fabs.c fabsf.c fabsl.c fmod.c fmodf.c fmodl.c llrint.c \
    llrintf.c llrintl.c lrint.c lrintf.c lrintl.c remainder.c remainderf.c \
    remainderl.c rint.c rintf.c rintl.c sqrt.c sqrtf.c sqrtl.c)
echo "musl: applying tools/patches/musl-1.2.5-tcc.patch"
patch -s -p1 <"$HERE/patches/musl-1.2.5-tcc.patch"
find . -name '*.orig' -exec rm -f {} +
cd "$OUT"
mv "$M" "$OUT/musl"

# ---- Linux headers --------------------------------------------------------
echo "linux-headers: unpacking 6.12.77"
gzip -dc "$KH_TGZ" | (cd "$TMP" && tar -xf -)
K=$TMP/kernel-headers-6.12.77
find_header() { # NAME: print its path (architecture first), or nothing
    for d in "$K/arch/x86/include" "$K/generic/include"; do
        if [ -f "$d/$1" ]; then printf '%s\n' "$d/$1"; return 0; fi
    done
    return 0
}
todo=$(sed -e 's/#.*//' "$HERE/linux-headers.list")
done_list=" "
while [ -n "$(printf '%s' "$todo" | tr -d ' \n')" ]; do
    next=
    for h in $todo; do
        case $done_list in *" $h "*) continue ;; esac
        done_list="$done_list$h "
        p=$(find_header "$h")
        [ -n "$p" ] || continue     # a libc header (<stdint.h>, <sys/ioctl.h>, ...)
        mkdir -p "$OUT/linux-headers/$(dirname "$h")"
        cp "$p" "$OUT/linux-headers/$h"
        next="$next $(sed -n 's/^[[:space:]]*#[[:space:]]*include[[:space:]]*<\([^>]*\)>.*/\1/p' "$p")"
    done
    todo=$next
done
cp "$K/README.md" "$OUT/linux-headers/README.sabotage.md"

rm -rf "$TMP"
echo "done: $OUT/musl $OUT/linux-headers ($(find "$OUT/linux-headers" -name '*.h' | wc -l) headers)"
