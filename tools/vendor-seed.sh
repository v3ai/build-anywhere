#!/bin/sh
# vendor-seed.sh: (re)create seed/ from upstream sources. Maintainers only;
# users never run this.
#
#   tools/vendor-seed.sh PNUT_CHECKOUT OUT_DIR
#
# PNUT_CHECKOUT is a clone of https://github.com/udem-dlteam/pnut at the
# commit recorded in seed/README.md (it carries the TCC tarball and the TCC
# patches that pnut's own bootstrap kit uses). Needs a C compiler, tar, gzip,
# awk and patch. Writes:
#
#   OUT_DIR/pnut-sh.sh   pnut's C-to-POSIX-shell compiler, as a shell script
#   OUT_DIR/pnut/        pnut's C sources (pnut-sh.sh is generated from these)
#   OUT_DIR/tcc/         TinyCC 0.9.27, trimmed to x86/x86_64 Linux, with the
#                        pnut kit's patches and tools/patches/ applied
#
# seed/musl and seed/linux-headers come from tools/vendor-musl.sh.
set -eu

[ $# -eq 2 ] || { echo "usage: $0 PNUT_CHECKOUT OUT_DIR" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
PNUT=$(cd "$1" && pwd)
OUT=$2
CC=${CC:-cc}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TMP=$OUT/.vendor-tmp
rm -rf "$TMP" "$OUT/pnut" "$OUT/tcc"
mkdir -p "$TMP" "$OUT/pnut" "$OUT/tcc"

# Replace the text of BEFORE with the text of AFTER in FILE; the text must
# occur exactly as given (the format of pnut's kit/tcc-patches).
simple_patch() { # FILE BEFORE AFTER
    awk -v bf="$2" -v af="$3" '
        BEGIN { RS = "\001"; getline b < bf; getline a < af }
        {
            n = index($0, b)
            if (n == 0) { print "patch does not apply: " bf > "/dev/stderr"; exit 1 }
            printf "%s%s%s", substr($0, 1, n - 1), a, substr($0, n + length(b))
        }' "$1" >"$1.new"
    mv "$1.new" "$1"
}

echo "pnut: generating pnut-sh.sh"
$CC -std=c99 -O2 -w -Dtarget_sh -DNICE_UX "$PNUT/pnut.c" -o "$TMP/pnut-sh"
"$TMP/pnut-sh" -Dtarget_sh -DNICE_UX "$PNUT/pnut.c" >"$OUT/pnut-sh.sh"
chmod 755 "$OUT/pnut-sh.sh"

echo "pnut: copying sources"
for f in pnut.c env.c exe.c x86.c elf.c arith64.c sh.c sh-runtime.c glo_decls.c \
         text.c LICENSE README.md; do
    cp "$PNUT/$f" "$OUT/pnut/$f"
done
cp -R "$PNUT/portable_libc" "$OUT/pnut/portable_libc"
rm -f "$OUT/pnut/portable_libc/makefile" "$OUT/pnut/portable_libc/test-libc.c"

echo "tcc: unpacking and patching 0.9.27"
(cd "$TMP" && gzip -dc "$PNUT/kit/tcc-0.9.27.tar.gz" | tar -xf -)
T=$TMP/tcc-0.9.27
for f in COPYING RELICENSING README VERSION \
         tcc.c tcc.h libtcc.c libtcc.h tccpp.c tccgen.c tccelf.c tccasm.c tccrun.c \
         tcctools.c tcctok.h elf.h stab.h stab.def \
         i386-gen.c i386-link.c i386-asm.c i386-asm.h i386-tok.h \
         x86_64-gen.c x86_64-link.c x86_64-asm.h; do
    cp "$T/$f" "$OUT/tcc/$f"
done
mkdir -p "$OUT/tcc/include" "$OUT/tcc/lib"
cp "$T"/include/*.h "$OUT/tcc/include/"
cp "$T/lib/libtcc1.c" "$OUT/tcc/lib/"
cp "$PNUT/kit/config.h" "$OUT/tcc/config.h"

P=$PNUT/kit/tcc-patches/0.9.27
while read -r file patch; do
    [ -n "$file" ] || continue
    simple_patch "$OUT/tcc/$file" "$P/$patch.before" "$P/$patch.after"
done <<'EOF'
tccpp.c       array_sizeof
tcc.h         attribute
tcc.h         bitfields
tccgen.c      float_negation
tccgen.c      float_zero_division_check
tccgen.c      long_double_codegen
tccpp.c       scientific-notation-parser
libtcc.c      sscanf_TCC_VERSION
x86_64-gen.c  x86_64_va_arg_local_enum
x86_64-gen.c  x86_64_gfunc_call_vla
tccelf.c      x86_64_static_plt_call
tccelf.c      x86_64_static_got_reloc
EOF

# build-anywhere's own fixes, each backported from later TinyCC: index weak
# symbols in archives (musl needs it), negated float compares with a NaN on
# x86_64, and a register allocation bug after (int) of a double on i386.
(cd "$OUT/tcc" && patch -s -p1 <"$HERE/patches/tcc-0.9.27-build-anywhere.patch")

# The first TinyCC of the bootstrap is compiled by pnut, which has no floating
# point, and cannot read the literal 2^64 in libtcc1.c: build it from its bits.
awk '
    /^float __floatundisf/ && !done {
        print "/* build-anywhere: 2^64, built from its bits so that a compiler"
        print "   that cannot read floating-point literals compiles this file. */"
        print "static double __ba_two64(void)"
        print "{"
        print "    union { unsigned long long u; double d; } v;"
        print "    v.u = 0x43F0000000000000ULL;"
        print "    return v.d;"
        print "}"
        print ""
        done = 1
    }
    { gsub(/18446744073709551616\.0/, "__ba_two64()"); print }
' "$OUT/tcc/lib/libtcc1.c" >"$OUT/tcc/lib/libtcc1.c.new"
mv "$OUT/tcc/lib/libtcc1.c.new" "$OUT/tcc/lib/libtcc1.c"
grep -q '18446744073709551616' "$OUT/tcc/lib/libtcc1.c" && { echo "libtcc1.c patch failed" >&2; exit 1; }

rm -rf "$TMP"
echo "done: $OUT"
