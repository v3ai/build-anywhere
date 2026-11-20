# build-anywhere

Compile C on any POSIX system, even one with no C compiler, using nothing but
`/bin/sh`.

Software dies when it can no longer be built. build-anywhere is a directory
you drop into your project so that `sh build-anywhere/build-anywhere *.c`
produces a working program: today on a laptop with gcc, and in twenty years
on a stripped-down server whose package mirrors are gone. It is written for
[Universal C](https://github.com/v3ai/universal-c), the C89 dialect that
compiles everywhere, and it has no dependencies of its own. Everything it
needs is in the directory: shell scripts and C source, no binaries.

```sh
sh build-anywhere/build-anywhere -O2 -o myprog src/*.c
```

## How it gets a compiler

It tries four tiers in order and uses the first one that compiles and runs a
test program:

| Tier | What it does | Needs | First use | Output |
|---|---|---|---|---|
| **system** | Uses an installed compiler: `$CC`, `cc`, `c99`, `gcc`, `clang`, `tcc`, `pcc`, `cproc`, ... | a compiler | instant | native program |
| **download** | Downloads [Zig](https://ziglang.org) 0.17.1 and uses it as `zig cc`. The archive is checked against a pinned SHA-256 before anything in it runs. Community mirrors are tried in random order, then ziglang.org. | network, a downloader (`curl`, `wget`, `fetch` or `ftp`), a SHA-256 tool, an xz unpacker | ~10 s | native program |
| **bootstrap** | Builds TinyCC from source, starting from a C compiler written in shell. | x86 or x86_64 Linux, any POSIX shell | ~4-5 min, once | native static program |
| **shell** | Compiles your program *into a shell script* with [pnut](https://github.com/udem-dlteam/pnut). | any POSIX shell | seconds | shell script (subset of C) |

Compilers that are acquired (Zig, TinyCC) are kept in
`~/.cache/build-anywhere` and reused. Each tier behaves like `cc`, so
the flags you pass (`-o`, `-I`, `-D`, `-O2`, ...) go straight to it.

## Using it in a project

Copy the directory into your repository (it is about 2.7 MB, almost all of
it the vendored TinyCC and pnut sources), or add it as a subtree:

```sh
git subtree add --prefix build-anywhere https://github.com/v3ai/build-anywhere main --squash
```

Then build with it directly:

```sh
sh build-anywhere/build-anywhere -O2 -o myprog src/main.c src/util.c
```

or let it pick a compiler for your existing build:

```sh
CC=$(sh build-anywhere/build-anywhere --cc)
make CC="$CC"
```

`--doctor` shows what is possible on the current machine:

```
$ sh build-anywhere/build-anywhere --doctor
build-anywhere 0.1.0 on x86_64 linux
cache: /home/me/.cache/build-anywhere

system:    ok ('gcc')
download:  possible (Zig 0.17.1 for x86_64-linux, needs network)
bootstrap: possible (one-time build, several minutes, using /usr/bin/dash)
shell:     possible (C subset only, using /usr/bin/dash)
```

Options: `--tiers=system,bootstrap` restricts and orders the tiers,
`--cache=DIR` moves the cache, `-v` shows every probe and command. The
environment variables `CC`, `BA_TIERS`, `BA_CACHE`, `BA_SHELL` and
`BA_VERBOSE=1` do the same.

## The bootstrap tier

This tier needs nothing but a shell. The chain is:

1. The shell runs `seed/pnut-sh.sh`, pnut's C compiler written as a POSIX
   shell script, on pnut's own C source. The result is the same compiler,
   still a shell script, but now it emits x86 machine code. (~1 minute with dash)
2. The shell runs that script on pnut's source again and writes a native
   `pnut` executable. (~3 minutes with dash)
3. The native pnut recompiles itself with every feature on, then compiles
   TinyCC 0.9.27.
4. TinyCC rebuilds the C library and itself, four times. The last two
   compilers must be byte-identical (a *fixed point*), which shows that the
   chain converged. This takes a few seconds.

The result is a static TinyCC with its own C library in
`~/.cache/build-anywhere/tcc-x86_64-linux-0.1.0/`. The shell work is saved as it
goes, so an interrupted bootstrap resumes where it stopped. The fastest
installed shell is used (dash, ksh, mksh, yash, bash, then `/bin/sh`), and
`BA_SHELL` overrides the choice.

### The C library

Programs built by the bootstrapped TinyCC are linked statically against
`libc/`. This is a small C89 library (plus the POSIX calls that TinyCC
itself needs) written for this project under the MIT license, so your
program carries no copyleft code. Its formatting and math are checked
against glibc: `tests/libc/run.sh` runs 5.8 million comparisons, with the
library compiled by gcc and again by the bootstrapped TinyCC.

- `printf("%.17g")` and `strtod` are exact and correctly rounded (arbitrary
  precision, ties to even), including hex floats and subnormals.
- `sqrt` is correctly rounded; `exp`, `log`, `pow` and `atan` are within
  1 ULP of glibc, and the rest of `<math.h>` within 3 ULP.
- Buffered stdio, `malloc`, `qsort`, `setjmp`, `signal`, `system`, `time`,
  `strftime` and the rest of C89 are included. Local time is UTC (there is
  no time-zone database), and the only locale is `"C"`.
- On i386, programs start with the x87 FPU set to double precision (as on
  FreeBSD), so floating-point results are bit-for-bit the same as on x86_64
  (`tests/libc/mathcmp.golden` checks this). As a consequence, `long double`
  has the precision of `double` there.

## The shell tier

When nothing else works, pnut compiles your program to a POSIX shell script,
which then runs with `/bin/sh`. Only a subset of C works there: no floating
point, no unsigned arithmetic, no local arrays or structs, no variadic
functions other than `printf`, no identifiers that start with `_`, and only
the library in `seed/pnut-libc/` (`<string.h>`, `<ctype.h>`, character I/O,
`malloc`, `strtol`, ...). It is meant for small tools that must run
somewhere with nothing else, and it is much slower than a native program.

## Platforms

| | system | download | bootstrap | shell |
|---|---|---|---|---|
| Linux x86_64, x86 | yes | yes | yes | yes |
| Linux arm64, arm, riscv64, ppc64le, s390x, loongarch64 | yes | yes | - | yes |
| macOS (x86_64, arm64) | yes | yes | - | yes |
| FreeBSD, NetBSD, OpenBSD | yes | yes | - | yes |
| illumos, other POSIX systems | yes | - | - | yes |

The driver is plain POSIX `sh`. The tests run it under dash, bash,
BusyBox sh, ksh (ksh93), mksh and yash.

## Security

- No step needs root, and nothing is installed outside the cache directory.
- Downloads are accepted only if their SHA-256 matches the hash pinned in
  the `build-anywhere` script. If no SHA-256 tool is available, the
  download tier is skipped rather than trusting an unverified file.
- The bootstrap starts from source that is in this repository and can be
  read. No binary is downloaded or executed.

## Testing

```sh
sh tests/run.sh                     # every tier that is quick, under every installed shell
BA_TEST_BOOTSTRAP=1 sh tests/run.sh # also the full bootstrap (~5 minutes)
BA_TEST_DOWNLOAD=1 sh tests/run.sh  # also a real Zig download
sh tests/libc/run.sh                # the libc against glibc (needs gcc and objcopy)
```

## Prior art

build-anywhere stands on these projects:

- **[pnut](https://github.com/udem-dlteam/pnut)** (Université de Montréal):
  a C compiler that emits readable POSIX shell, and the shell-to-TinyCC
  bootstrap path. Its bootstrap kit provided the TinyCC patches and
  build order used here. build-anywhere replaces the kit's GNU Mes libc
  with an MIT library, so programs are not GPL-encumbered.
- **[TinyCC](https://repo.or.cz/tinycc.git)**: the small, fast compiler at
  the end of the bootstrap.
- **[live-bootstrap](https://github.com/fosslinux/live-bootstrap)** and
  **[stage0-posix](https://github.com/oriansj/stage0-posix)**: full-source
  bootstraps from a few hundred bytes of machine code, with GNU Mes as the
  stepping stone to TinyCC and GCC.
- **[Onramp](https://github.com/ludocode/onramp)**: C bootstrapped from
  hand-written hex through a portable virtual machine.
- **[obuild](https://github.com/alganet/obuild)**: a GCC bootstrap driven by
  only kaem and sh.
- **[bootsh](https://github.com/davidar/bootsh)**: a whole POSIX userland
  with a C99 compiler in one small executable.
- **[Zig](https://ziglang.org)**: `zig cc` is a complete, relocatable C
  toolchain in a single download, which makes it ideal for the download
  tier.

## License

MIT, see `LICENSE`. The vendored pnut (BSD 2-Clause) and TinyCC
(LGPL 2.1+) sources under `seed/` keep their licenses. `THIRD_PARTY.md`
explains what ends up in the programs you build.
