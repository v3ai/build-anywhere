#!/bin/sh
# tests/run.sh: test build-anywhere's tiers.
#
#   tests/run.sh [SHELL...]
#
# Runs the driver under each SHELL given (default: every one of sh, dash,
# bash, ksh, mksh, yash, posh and busybox sh that is installed). The slow and
# networked tests are opt-in:
#
#   BA_TEST_DOWNLOAD=1   download a prebuilt gcc for real (needs network, ~90 MB)
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
    for s in sh dash bash ksh mksh yash posh; do
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
# Whether this machine has a compiler is decided once, with sh: under every
# other shell, the system tier must then find it too.
has_cc=0
sh "$BA" --tiers=system --cache="$T/cache-sys" --cc >/dev/null 2>&1 && has_cc=1
for s in $shells; do
    c=$T/cache-sys
    expect "[$s] --version" "build-anywhere $(sed -n 's/^BA_VERSION=//p' "$BA")" run_ba "$s" --version
    if run_ba "$s" --doctor --cache="$c" >"$T/doctor" 2>&1 && grep -q '^system:' "$T/doctor"; then
        ok "[$s] --doctor"
    else
        bad "[$s] --doctor"; sed 's/^/      /' "$T/doctor"
    fi
    if [ "$has_cc" = 1 ]; then
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
    if [ "$has_cc" = 1 ]; then
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

# ---- package tier, with stand-in package managers --------------------------
# PATH is replaced by $T/stub (the stand-ins) and $T/nocc: every command of
# the real PATH except compilers, package managers, sudo and doas. A
# stand-in "installs" gcc or clang as a script that runs the host compiler.
realcc=
for c in cc gcc clang; do have "$c" && { realcc=$(command -v "$c"); break; }; done

mk_nocc() {
    mkdir -p "$T/nocc"
    mn_ifs=$IFS; IFS=:
    for mn_d in $PATH; do
        IFS=$mn_ifs
        for mn_f in "$mn_d"/*; do
            mn_n=${mn_f##*/}
            case $mn_n in
            cc|c89|c99|c++|g++|gcc|gcc-*|gcc[0-9]*|clang|clang-*|clang[0-9]*|clang++*|cpp|\
            tcc|pcc|cproc|icx|suncc|*-gcc|*-gcc-*|*-cc|*-clang|*-clang-*|\
            apt|apt-get|dnf|yum|microdnf|zypper|apk|pacman|xbps-install|pkg|brew|nix|\
            sudo|doas|softwareupdate|id) continue ;;
            esac
            [ -x "$mn_f" ] && [ ! -d "$mn_f" ] && [ ! -e "$T/nocc/$mn_n" ] &&
                ln -s "$mn_f" "$T/nocc/$mn_n"
        done
    done
    IFS=$mn_ifs
}

# stub NAME BODY: write the stand-in command $T/stub/NAME.
stub() {
    { echo '#!/bin/sh'; echo "S=$T/stub"; printf '%s\n' "$2"; } >"$T/stub/$1"
    chmod 755 "$T/stub/$1"
}

# A fresh set of stand-ins. STUB_UID is what id -u prints; STUB_SUDO=ok
# makes "sudo -n true" succeed. A package manager logs each call in
# $T/pm.log and installs the compiler named in its arguments into
# $STUB_TO (default $T/stub, which is in PATH) as $STUB_NAME (default: the
# compiler's name). STUB_FAIL names a compiler it refuses to install, and
# STUB_BROKEN one it installs broken.
pm_body='echo "${0##*/} $*" >>"$S/../pm.log"
case " $* " in *" update "*|*" -Sy "*) touch "$S/../synced"; exit 0 ;; esac
[ -n "${STUB_NEEDSYNC:-}" ] && [ ! -e "$S/../synced" ] && exit 100
c=
for a in "$@"; do case $a in gcc|nixpkgs#gcc) c=gcc ;; clang|llvm|nixpkgs#clang) c=clang ;; esac; done
[ -n "$c" ] || exit 1
if [ "$c" = "${STUB_FAIL:-}" ]; then echo "No match for argument: $c" >&2; exit 1; fi
to=${STUB_TO:-$S}
mkdir -p "$to"
n=${STUB_NAME:-$c}
if [ "$c" = "${STUB_BROKEN:-}" ]; then
    printf "#!/bin/sh\necho broken >&2\nexit 1\n" >"$to/$n"
else
    printf "#!/bin/sh\nexec %s \"\$@\"\n" "$REALCC" >"$to/$n"
fi
chmod 755 "$to/$n"'

pkg_setup() {
    rm -rf "$T/stub" "$T/pm.log" "$T/synced" "$T/brew" "$T/nixstore"
    mkdir -p "$T/stub"
    : >"$T/pm.log"
    stub id 'case $1 in -u) echo "${STUB_UID:-1000}" ;; *) echo "uid=${STUB_UID:-1000}" ;; esac'
    stub sudo '[ "${STUB_SUDO:-}" = ok ] || exit 1
[ "$1" = -n ] && shift
echo "sudo $*" >>"$S/../pm.log"
exec "$@"'
    for pm in ${1+"$@"}; do
        case $pm in
        brew) stub brew 'case $1 in
--prefix) if [ $# -eq 1 ]; then echo "$S/../brew"; else echo "$S/../brew/opt/$2"; fi; exit 0 ;;
esac
STUB_TO=$S/../brew/opt/gcc/bin STUB_NAME=gcc-15
'"$pm_body" ;;
        nix) stub nix 'STUB_TO=$S/../nixstore/abc-gcc/bin
'"$pm_body"'
echo "$S/../nixstore/abc-gcc"' ;;
        *) stub "$pm" "$pm_body" ;;
        esac
    done
}

# pkg_ba [VAR=VALUE...] COMMAND...: run COMMAND with only the stand-ins and
# $T/nocc in PATH.
pkg_ba() {
    env PATH="$T/stub:$T/nocc" REALCC="$realcc" "$@"
}

if [ -n "$realcc" ]; then
    mk_nocc
    pc=$T/cache-pkg
    for s in $shells; do
        if [ "$s" = busybox ]; then sh_cmd="$(command -v busybox) sh"; else sh_cmd=$s; fi
        # Not root, passwordless sudo, apt-get without package lists yet.
        pkg_setup apt-get
        rm -f "$T/hello"
        pkg_ba STUB_SUDO=ok STUB_NEEDSYNC=1 $sh_cmd "$BA" --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
        if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] &&
           grep -q "installing gcc with apt-get with sudo" "$T/err" &&
           grep -q "^apt-get update" "$T/pm.log" &&
           grep -q "^sudo env DEBIAN_FRONTEND=noninteractive apt-get install" "$T/pm.log" &&
           grep -q "^apt-get install -y -q --no-install-recommends gcc libc6-dev" "$T/pm.log"; then
            ok "[$s] package: apt-get via sudo, after updating the package lists"
        else
            bad "[$s] package: apt-get via sudo"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
        fi
    done

    # Root (a container), gcc cannot be installed: clang is.
    pkg_setup dnf
    rm -f "$T/hello"
    pkg_ba STUB_UID=0 STUB_FAIL=gcc sh "$BA" --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "clang from dnf" "$T/err" &&
       grep -q "could not install gcc" "$T/err" && grep -q "^    No match for argument: gcc" "$T/err" &&
       ! grep -q "^sudo" "$T/pm.log"; then
        ok "package: dnf as root, falls back to clang"
    else
        bad "package: dnf as root, clang fallback"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
    fi

    # The installed gcc does not work: clang is tried next.
    pkg_setup pacman
    rm -f "$T/hello"
    pkg_ba STUB_UID=0 STUB_BROKEN=gcc STUB_NEEDSYNC=1 sh "$BA" --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "clang from pacman" "$T/err" &&
       grep -q "installed gcc, but it does not compile" "$T/err" && grep -q "^pacman -Sy" "$T/pm.log"; then
        ok "package: pacman, broken gcc, then clang"
    else
        bad "package: pacman, broken gcc"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
    fi

    # Not root, no sudo: nothing is run, and the reason is given.
    for v in "STUB_SUDO=" "BA_SUDO=never"; do
        pkg_setup apk
        if pkg_ba STUB_SUDO=ok "$v" sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"; then
            bad "package: no root ($v) should fail"
        elif grep -q "apk could install a compiler, but needs root" "$T/err" && [ ! -s "$T/pm.log" ]; then
            ok "package: no root ($v): nothing installed, reason given"
        else
            bad "package: no root ($v)"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
        fi
    done

    # Homebrew (no root) puts gcc-15 in a directory that is not in PATH.
    pkg_setup brew
    rm -f "$T/hello"
    pkg_ba sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "gcc from brew: .*brew/opt/gcc/bin/gcc-15" "$T/err" &&
       grep -q "installing gcc with brew (no root needed)" "$T/err"; then
        ok "package: Homebrew, compiler outside PATH"
    else
        bad "package: Homebrew"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
    fi

    # Nix (no root): the compiler is found in the store path it prints.
    pkg_setup nix
    rm -f "$T/hello"
    pkg_ba sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "gcc from nix: .*nixstore/abc-gcc/bin/gcc" "$T/err"; then
        ok "package: Nix, compiler in the store"
    else
        bad "package: Nix"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
    fi

    # --cc after installing gives a working compiler command.
    pkg_setup zypper
    if ccmd=$(pkg_ba STUB_UID=0 sh "$BA" --cc --cache="$pc" 2>"$T/err") &&
       grep -q "^zypper --non-interactive install --no-recommends gcc glibc-devel" "$T/pm.log" &&
       pkg_ba $ccmd -o "$T/hello" "$hello" && [ "$("$T/hello" cc)" = "hello, cc" ]; then
        ok "package: zypper, --cc"
    else
        bad "package: zypper, --cc"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 20
    fi

    # The compiler that was just installed is used, not an older one.
    pkg_setup apt-get
    printf '#!/bin/sh\nexec %s "$@"\n' "$realcc" >"$T/stub/cc"
    chmod 755 "$T/stub/cc"
    rm -f "$T/hello"
    pkg_ba STUB_UID=0 sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "gcc from apt-get: 'gcc'" "$T/err"; then
        ok "package: the new compiler is preferred"
    else
        bad "package: the new compiler is preferred"; sed 's/^/      /' "$T/err" | tail -n 10
    fi

    # FreeBSD-style versioned name (gcc13) in PATH, from a directory with a
    # space in its name.
    pkg_setup dnf
    mkdir -p "$T/stub dir"
    rm -f "$T/hello"
    pkg_ba STUB_UID=0 STUB_NAME=gcc13 STUB_TO="$T/stub dir" PATH="$T/stub:$T/stub dir:$T/nocc" \
        sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] && grep -q "gcc from dnf: 'gcc13'" "$T/err"; then
        ok "package: versioned compiler name (gcc13)"
    else
        bad "package: versioned compiler name"; sed 's/^/      /' "$T/err" | tail -n 10
    fi

    # tdnf (Photon OS, Azure Linux) needs the C headers and binutils named.
    pkg_setup tdnf
    rm -f "$T/hello"
    pkg_ba STUB_UID=0 sh "$BA" --tiers=package --cache="$pc" -o "$T/hello" "$hello" 2>"$T/err"
    if [ "$("$T/hello" pkg 2>/dev/null)" = "hello, pkg" ] &&
       grep -q "^tdnf install -y gcc glibc-devel binutils" "$T/pm.log" &&
       grep -q "^tdnf install -y linux-api-headers" "$T/pm.log"; then
        ok "package: tdnf"
    else
        bad "package: tdnf"; sed 's/^/      /' "$T/err" "$T/pm.log" | tail -n 10
    fi

    # No package manager at all: the tier fails quietly.
    pkg_setup
    if pkg_ba STUB_UID=0 sh "$BA" --tiers=package --cache="$pc" "$hello" >/dev/null 2>"$T/err"; then
        bad "package: no package manager should fail"
    elif grep -q "no way to get a C compiler" "$T/err"; then
        ok "package: no package manager"
    else
        bad "package: no package manager"; sed 's/^/      /' "$T/err" | tail -n 10
    fi
else
    skip "package: needs a host compiler for the stand-ins"
fi

# ---- download tier -------------------------------------------------------
# The prebuilt toolchains for this machine, if any.
dl_files=$(sh "$BA" --doctor --cache="$T/c" 2>/dev/null | grep -q '^download: *unavailable (no prebuilt' ||
           sed -n "/^BA_TOOLCHAINS='/,/^'/p" "$BA" | awk 'NF > 4 { print $4 }')
if [ -z "$dl_files" ]; then
    skip "download: no prebuilt toolchain for this machine"
elif ! have curl; then
    skip "download: the checksum test needs curl (for file:// URLs)"
else
    # A corrupted archive must be rejected before anything in it runs.
    m=$T/mirror
    mkdir -p "$m"
    for f in $dl_files; do echo "not a toolchain" >"$m/$f"; done
    if BA_TEST_URLS="file://$m" sh "$BA" --tiers=download --cache="$T/cache-bad" \
        -o "$T/x" "$hello" >"$T/out" 2>&1; then
        bad "download: corrupted archive was accepted"
    elif grep -q "checksum mismatch" "$T/out" && ! ls -d "$T/cache-bad"/toolchain-* >/dev/null 2>&1; then
        ok "download: corrupted archive is rejected"
    else
        bad "download: corrupted archive (unexpected output)"
        sed 's/^/      /' "$T/out"
    fi
fi

# A toolchain already in the cache is used before anything is downloaded,
# even if it is not the first choice. A fake one (the host compiler) is put
# in the cache for the last toolchain listed for this machine.
arch=$(sh "$BA" --doctor --cache="$T/c" 2>/dev/null | sed -n 's/^build-anywhere [^ ]* on \([^ ]*\) .*/\1/p')
last=$(sed -n "/^BA_TOOLCHAINS='/,/^'/p" "$BA" | awk -v a="$arch" 'NF > 4 && ($1 == a || index($1, a "/") == 1) { l = $5 " " $6 } END { print l }')
if [ -n "$dl_files" ] && [ -n "$last" ] && [ -n "$realcc" ]; then
    set -- $last
    mkdir -p "$T/cache-fake/toolchain-$1/${2%/*}"
    printf '#!/bin/sh\nfor a; do shift; [ "$a" = -static ] || set -- "$@" "$a"; done\nexec %s "$@"\n' \
        "$realcc" >"$T/cache-fake/toolchain-$1/$2"
    chmod 755 "$T/cache-fake/toolchain-$1/$2"
    rm -f "$T/hello"
    BA_TEST_URLS="file://$T/nonexistent" sh "$BA" --tiers=download --cache="$T/cache-fake" \
        -o "$T/hello" "$hello" 2>"$T/stderr"
    if [ "$("$T/hello" c 2>/dev/null)" = "hello, c" ] && ! grep -q downloading "$T/stderr"; then
        ok "download: a cached toolchain is used first"
    else
        bad "download: a cached toolchain is used first"; sed 's/^/      /' "$T/stderr"
    fi
fi

if [ "${BA_TEST_DOWNLOAD:-0}" = 1 ] && [ -n "$dl_files" ]; then
    # The corrupted copy is tried first, then the real source.
    mkdir -p "$T/mirror"
    for f in $dl_files; do echo "not a toolchain" >"$T/mirror/$f"; done
    rm -f "$T/hello"
    # (file:// needs curl; without it, only the real source is used.)
    urls=default
    have curl && urls="file://$T/mirror default"
    BA_TEST_URLS=$urls sh "$BA" --tiers=download --cache="$T/cache-dl" \
        -o "$T/hello" "$hello" 2>"$T/dl-err"
    expect "download: hello" "hello, gcc" "$T/hello" gcc || sed 's/^/      /' "$T/dl-err"
    if have curl; then
        if grep -q "checksum mismatch" "$T/dl-err"; then
            ok "download: the corrupted copy was tried first, then rejected"
        else
            bad "download: the corrupted copy was not tried first"; sed 's/^/      /' "$T/dl-err"
        fi
    fi
    rm -f "$T/uni"
    # shellcheck disable=SC2086
    sh "$BA" --tiers=download --cache="$T/cache-dl" -O2 -o "$T/uni" $uni 2>"$T/stderr"
    expect "download: universal C" "universal: ok" "$T/uni"
    # A second use downloads nothing.
    if sh "$BA" --tiers=download --cache="$T/cache-dl" --cc 2>"$T/stderr" | grep -q "cc-" &&
       ! grep -q downloading "$T/stderr"; then
        ok "download: the toolchain is reused from the cache"
    else
        bad "download: cache reuse"; sed 's/^/      /' "$T/stderr"
    fi
else
    skip "download: real download (set BA_TEST_DOWNLOAD=1; about 90 MB)"
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
    # musl: sockets, select, termios, fork, directories, <linux/*.h>.
    rm -f "$T/posix"
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/posix" tests/libc/posix.c 2>"$T/stderr" ||
        sed 's/^/      /' "$T/stderr" | tail -n 10
    expect "bootstrap: POSIX interfaces (musl)" "posix: ok" "$T/posix"
    # musl's math within 2 ULP of glibc, printf and strtod exactly the same.
    rm -f "$T/mathcmp"
    sh "$BA" --tiers=bootstrap --cache="$c" -o "$T/mathcmp" tests/libc/mathcmp.c 2>"$T/stderr"
    expect "bootstrap: math and number formatting match glibc" "mathcmp: ok" \
        "$T/mathcmp" tests/libc/mathcmp.golden
else
    skip "bootstrap: (set BA_TEST_BOOTSTRAP=1; about 5 minutes)"
fi

# ---- shell tier --------------------------------------------------------
# pnut cannot run under posh or the public-domain ksh (see pick_shell in
# build-anywhere).
pnut_shell() { # SHELL
    case $1 in *posh) return 1 ;; busybox) return 0 ;; esac
    case $("$1" -c 'echo "${KSH_VERSION:-}"' 2>/dev/null) in *"PD KSH"*) return 1 ;; esac
    return 0
}
shell_tier() { # SHELL ("" for the driver's choice)
    st_sh=$1
    if [ "$st_sh" = busybox ]; then   # BA_SHELL is one command: use a link named sh
        mkdir -p "$T/busybox"
        ln -sf "$(command -v busybox)" "$T/busybox/sh"
        st_sh=$T/busybox/sh
    fi
    rm -f "$T/hello.sh"
    BA_SHELL=$st_sh sh "$BA" --tiers=shell --cache="$T/cache-sh" -o "$T/hello.sh" "$hello" 2>"$T/stderr"
    expect "[${1:-default}] shell: hello" "hello, pnut" "${st_sh:-sh}" "$T/hello.sh" pnut
}
if [ "${BA_TEST_SHELL_TIER:-0}" = 1 ]; then
    for s in $shells; do
        if pnut_shell "$s"; then shell_tier "$s"; else skip "[$s] shell: pnut does not run under it"; fi
    done
elif sh "$BA" --doctor --cache="$T/c" 2>/dev/null | grep -q '^shell: *possible'; then
    shell_tier ""
else
    skip "shell: $(sh "$BA" --doctor --cache="$T/c" 2>/dev/null | sed -n 's/^shell: *//p')"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
