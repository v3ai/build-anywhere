#!/bin/sh
# tests/run.sh: test build-anywhere's tiers.
#
#   tests/run.sh [SHELL...]
#
# Runs the driver under each SHELL given (default: every one of sh, dash,
# bash, ksh, mksh, yash and busybox sh that is installed). The slow and
# networked tests are opt-in:
#
#   BA_TEST_DOWNLOAD=1   download Zig for real (needs network, ~55 MB)
#   BA_TEST_BOOTSTRAP=1  bootstrap TinyCC from the shell (x86/x86_64 Linux,
#                        about 5 minutes)
#   BA_TEST_SHELL_TIER=1 compile with the shell tier under every SHELL
#                        (a few seconds per shell)
set -u

cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
BA=$ROOT/build-anywhere
T=${TMPDIR:-/tmp}/ba-tests.$$
rm -rf "$T"
mkdir -p "$T" || exit 1
trap 'rm -rf "$T"' EXIT

pass=0 fail=0 skip=0
ok()   { pass=$((pass + 1)); printf 'ok    %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n' "$*"; }
skip() { skip=$((skip + 1)); printf 'skip  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# expect NAME EXPECTED-OUTPUT COMMAND...: run COMMAND, compare its stdout.
expect() {
    e_name=$1 e_want=$2
    shift 2
    if e_got=$("$@" 2>"$T/stderr"); then
        if [ "$e_got" = "$e_want" ]; then ok "$e_name"; return 0; fi
        bad "$e_name: printed '$e_got', expected '$e_want'"
    else
        bad "$e_name: exit status $?"
    fi
    sed 's/^/      /' "$T/stderr" | tail -n 15
    return 1
}

if [ $# -gt 0 ]; then
    shells="$*"
else
    shells=
    for s in sh dash bash ksh mksh yash; do
        have "$s" && shells="$shells $(command -v "$s")"
    done
    have busybox && shells="$shells busybox"
fi

# Runs the driver under shell $1 ("busybox" means "busybox sh").
run_ba() {
    rb_sh=$1
    shift
    if [ "$rb_sh" = busybox ]; then busybox sh "$BA" "$@"; else "$rb_sh" "$BA" "$@"; fi
}

hello=$ROOT/examples/hello/hello.c
uni="$ROOT/examples/universal/main.c $ROOT/examples/universal/p_util.c"

# ---- static checks -----------------------------------------------------
for f in build-anywhere seed/bootstrap-tcc.sh seed/cc-pnut.sh tools/vendor-seed.sh \
         tests/run.sh tests/libc/run.sh; do
    if sh -n "$f"; then ok "syntax: $f"; else bad "syntax: $f"; fi
done

# ---- system tier and the driver, under every shell -------------------------
for s in $shells; do
    c=$T/cache-sys
    expect "[$s] --version" "build-anywhere $(sed -n 's/^BA_VERSION=//p' "$BA")" run_ba "$s" --version
    if run_ba "$s" --doctor --cache="$c" >"$T/doctor" 2>&1 && grep -q '^system:' "$T/doctor"; then
        ok "[$s] --doctor"
    else
        bad "[$s] --doctor"; sed 's/^/      /' "$T/doctor"
    fi
    if run_ba "$s" --tiers=system --cache="$c" --cc >/dev/null 2>&1; then
        rm -f "$T/hello"
        run_ba "$s" --tiers=system --cache="$c" -o "$T/hello" "$hello" 2>"$T/stderr"
        expect "[$s] system: hello" "hello, tiers" "$T/hello" tiers
        rm -f "$T/uni"
        # shellcheck disable=SC2086
        run_ba "$s" --tiers=system --cache="$c" -o "$T/uni" $uni 2>"$T/stderr"
        expect "[$s] system: universal C" "universal: ok" "$T/uni"
    else
        skip "[$s] system: no compiler installed"
    fi
    # Arguments with spaces and quotes reach the compiler intact.
    if run_ba "$s" --tiers=system --cache="$c" --cc >/dev/null 2>&1; then
        mkdir -p "$T/dir with 'quotes'"
        cp "$hello" "$T/dir with 'quotes'/hello world.c"
        run_ba "$s" --tiers=system --cache="$c" -DGREETING='"x y"' \
            -o "$T/dir with 'quotes'/out file" "$T/dir with 'quotes'/hello world.c" 2>"$T/stderr"
        expect "[$s] quoting of paths" "hello, q" "$T/dir with 'quotes'/out file" q
    fi
    # No tier works: a clear failure, not a hang or a crash.
    if run_ba "$s" --tiers=bogus --cache="$c" "$hello" >"$T/out" 2>&1; then
        bad "[$s] unknown tier is rejected"
    else
        grep -q "unknown tier" "$T/out" && ok "[$s] unknown tier is rejected" ||
            bad "[$s] unknown tier message"
    fi
done

# ---- download tier: a corrupted archive must be rejected ---------------
if have curl; then
    m=$T/mirror
    mkdir -p "$m"
    plat=$(sh "$BA" --doctor --cache="$T/c" 2>/dev/null | sed -n 's/^build-anywhere [^ ]* on \([^ ]*\) \([^ ]*\)$/\1-\2/p')
    ver=$(sed -n 's/^BA_ZIG_VERSION=//p' "$BA")
    echo "not zig" >"$m/zig-$plat-$ver.tar.xz"
    if BA_TEST_MIRRORS="file://$m" sh "$BA" --tiers=download --cache="$T/cache-bad" \
        -o "$T/x" "$hello" >"$T/out" 2>&1; then
        bad "download: corrupted archive was accepted"
    elif grep -q "checksum mismatch" "$T/out" && [ ! -e "$T/cache-bad/zig-$plat-$ver" ]; then
        ok "download: corrupted archive is rejected"
    else
        bad "download: corrupted archive (unexpected output)"
        sed 's/^/      /' "$T/out"
    fi
else
    skip "download: checksum test needs curl"
fi

if [ "${BA_TEST_DOWNLOAD:-0}" = 1 ]; then
    rm -f "$T/hello"
    sh "$BA" --tiers=download --cache="$T/cache-dl" -o "$T/hello" "$hello" 2>"$T/stderr"
    expect "download: hello" "hello, zig" "$T/hello" zig
    rm -f "$T/uni"
    # shellcheck disable=SC2086
    sh "$BA" --tiers=download --cache="$T/cache-dl" -o "$T/uni" $uni 2>"$T/stderr"
    expect "download: universal C" "universal: ok" "$T/uni"
else
    skip "download: real download (set BA_TEST_DOWNLOAD=1)"
fi

# ---- bootstrap tier ------------------------------------------------------
if [ "${BA_TEST_BOOTSTRAP:-0}" = 1 ]; then
    c=${BA_TEST_CACHE:-$T/cache-boot}
    rm -f "$T/hello"
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/hello" "$hello" 2>"$T/stderr" ||
        sed 's/^/      /' "$T/stderr" | tail -n 30
    expect "bootstrap: hello" "hello, tcc" "$T/hello" tcc
    rm -f "$T/uni"
    # shellcheck disable=SC2086
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/uni" $uni 2>"$T/stderr"
    expect "bootstrap: universal C" "universal: ok" "$T/uni"
    rm -f "$T/smoke"
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/smoke" tests/libc/smoke.c 2>"$T/stderr"
    expect "bootstrap: libc smoke test" "smoke: ok" "$T/smoke"
    # The libc's math and number formatting must give the same bits on every
    # architecture (on i386 that needs the x87 set to double precision).
    rm -f "$T/mathcmp"
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/mathcmp" tests/libc/mathcmp.c 2>"$T/stderr"
    if "$T/mathcmp" >"$T/mathcmp.out" 2>&1 && cmp -s "$T/mathcmp.out" tests/libc/mathcmp.golden; then
        ok "bootstrap: math output matches the golden file"
    else
        bad "bootstrap: math output differs from tests/libc/mathcmp.golden"
        diff "$T/mathcmp.out" tests/libc/mathcmp.golden | head -n 6
    fi
else
    skip "bootstrap: (set BA_TEST_BOOTSTRAP=1; about 5 minutes)"
fi

# ---- shell tier --------------------------------------------------------
shell_tier() { # SHELL
    st_sh=$1
    if [ "$st_sh" = busybox ]; then   # BA_SHELL is one command: use a link named sh
        mkdir -p "$T/busybox"
        ln -sf "$(command -v busybox)" "$T/busybox/sh"
        st_sh=$T/busybox/sh
    fi
    rm -f "$T/hello.sh"
    BA_SHELL=$st_sh sh "$BA" --tiers=shell --cache="$T/cache-sh" -o "$T/hello.sh" "$hello" 2>"$T/stderr"
    expect "[$1] shell: hello" "hello, pnut" "$st_sh" "$T/hello.sh" pnut
}
if [ "${BA_TEST_SHELL_TIER:-0}" = 1 ]; then
    for s in $shells; do shell_tier "$s"; done
else
    shell_tier sh
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
