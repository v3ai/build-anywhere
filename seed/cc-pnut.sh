#!/bin/sh
# cc-pnut.sh: a cc-like front end that compiles C to a POSIX shell script
# with pnut-sh.sh. The "executable" it writes is a shell script.
#
#   cc-pnut.sh [-o OUT] [-I DIR]... [-D NAME[=VALUE]]... [-U NAME]... FILE.c...
#
# Flags that only matter to native compilers (-O, -g, -W, -std=, -l, ...)
# are accepted and ignored. Several .c files are compiled as one unit.
# Only a subset of C works: no unsigned arithmetic, no variadic functions
# besides printf, no local arrays or struct values; see seed/pnut-libc/ for
# the library. float and double work (computed in software, see
# seed/pnut-libc/float.c) and then need a shell with 64-bit arithmetic;
# <termios.h> and sockets work through stty and nc (term.c, net.c).
# Set BA_SHELL to choose the shell that runs pnut-sh.sh.
set -eu

SEED=$(cd "$(dirname "$0")" && pwd)
SH=${BA_SHELL:-/bin/sh}
die() { printf 'cc-pnut: %s\n' "$*" >&2; exit 1; }

out=a.out
defs=
incs=
srcs=
nl='
'
while [ $# -gt 0 ]; do
    case $1 in
        -o) [ $# -ge 2 ] || die "-o needs a file name"; out=$2; shift ;;
        -o*) out=${1#-o} ;;
        -I) [ $# -ge 2 ] || die "-I needs a directory"; incs="$incs$2$nl"; shift ;;
        -I*) incs="$incs${1#-I}$nl" ;;
        -D|-U) [ $# -ge 2 ] || die "$1 needs a name"; defs="$defs$1$2$nl"; shift ;;
        -D*|-U*) defs="$defs$1$nl" ;;
        -c|-S|-E|-shared) die "$1 is not supported: pnut builds whole programs only" ;;
        -L|-x) shift ;;
        -O*|-g*|-W*|-w|-std=*|-ansi|-pedantic*|-f*|-m*|-l*|-L*|-static|-pipe|-s|-v) ;;
        -*) die "unknown option: $1" ;;
        *.c) [ -f "$1" ] || die "no such file: $1"; srcs="$srcs$1$nl" ;;
        *) die "cannot use $1: only .c files can be compiled to shell" ;;
    esac
    shift
done
[ -n "$srcs" ] || die "no .c files given"

tmp=${TMPDIR:-/tmp}/cc-pnut.$$
rm -rf "$tmp"
(umask 077 && mkdir "$tmp") || die "cannot create $tmp"
trap 'rm -rf "$tmp"' EXIT
trap 'rm -rf "$tmp"; exit 130' INT TERM

# pnut takes a single include directory and resolves "quoted" includes next
# to the including file only. Merge everything into one directory: the
# shell-tier standard headers, then the -I directories (the first one wins)
# and the directories of the sources (which win over -I, as in C).
inc=$tmp/inc
mkdir "$inc"
cp -R "$SEED"/pnut-libc/include/. "$inc/"
copy_tree() { # DIR: copy its C sources and headers into $inc
    (cd "$1" && find . -name .git -prune -o -type f \
        \( -name '*.h' -o -name '*.c' -o -name '*.inc' -o -name '*.def' \) -print) |
    while IFS= read -r f; do
        mkdir -p "$inc/$(dirname "$f")"
        cp "$1/$f" "$inc/$f"
    done
}
dirs=
oldifs=$IFS
IFS=$nl
for d in $incs; do dirs="$d$nl$dirs"; done         # reverse: first -I wins
for f in $srcs; do dirs="$dirs$(dirname "$f")$nl"; done
for d in $dirs; do
    [ -d "$d" ] || die "no such directory: $d"
    copy_tree "$d"
done
set -- -I "$inc/" "$SEED/pnut-libc/libc.c"
# uses REGEX: whether a C file of the program matches REGEX (grep -E)
uses() {
    for d in $dirs; do
        if (cd "$d" && find . -name .git -prune -o -type f \( -name '*.h' -o -name '*.c' -o -name '*.inc' \) -print) |
            while IFS= read -r f; do
                if grep -E "$1" "$d/$f" >/dev/null 2>&1; then
                    echo yes
                    break
                fi
            done | grep yes >/dev/null; then
            return 0
        fi
    done
    return 1
}
# The floating-point library only when the program uses floating point (it
# makes every script larger and needs 64-bit shell arithmetic), and terminal
# control and sockets only when the program includes their headers.
if uses '(^|[^A-Za-z0-9_])(float|double|atof|strtod)([^A-Za-z0-9_]|$)|<(math|float)\.h>'; then
    set -- "$@" "$SEED/pnut-libc/float.c"
fi
if uses '<(termios|sys/ioctl)\.h>'; then
    set -- "$@" "$SEED/pnut-libc/term.c"
fi
if uses '<(sys/socket|netinet/in|arpa/inet|netdb)\.h>'; then
    set -- "$@" "$SEED/pnut-libc/net.c"
fi
for d in $defs; do set -- "$@" "$d"; done
for f in $srcs; do set -- "$@" "$inc/$(basename "$f")"; done
IFS=$oldifs

# pnut writes its error messages at the end of its output.
if ! "$SH" "$SEED/pnut-sh.sh" "$@" >"$tmp/out.sh"; then
    tail -n 3 "$tmp/out.sh" | sed "s|$inc/||g" >&2
    die "pnut could not compile the program"
fi
case $(sed -n 1p "$tmp/out.sh") in
    '#!'*) ;;
    *) tail -n 3 "$tmp/out.sh" >&2; die "pnut could not compile the program" ;;
esac
chmod 755 "$tmp/out.sh"
mv -f "$tmp/out.sh" "$out"
