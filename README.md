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

It tries five tiers in order and uses the first one that compiles and runs a
test program:

| Tier | What it does | Needs | First use | Output |
|---|---|---|---|---|
| **system** | Uses an installed compiler: `$CC`, `cc`, `c99`, `gcc`, `clang`, `tcc`, `pcc`, `cproc`, ... | a compiler | instant | native program |
| **package** | Installs gcc (or clang, if gcc can't be installed) with the system's package manager: `apt-get`, `dnf`, `yum`, `tdnf`, `zypper`, `apk`, `pacman`, `xbps-install`, FreeBSD `pkg`, Homebrew, Nix or Termux, or the Command Line Tools on macOS. | network, and root, passwordless `sudo`/`doas`, or a terminal to type a password in (Homebrew, Nix and Termux need none) | ~10-60 s | native program |
| **download** | Downloads a prebuilt gcc for Linux (static, with musl) and keeps it in the cache. The archive is checked against a SHA-256 or SHA-512 pinned in the script before anything in it runs. | Linux on x86_64, x86, arm64, armv6/armv7 or ppc64le; network; `curl`, `wget` or BusyBox; a hash tool; about 1 GB of disk | ~30 s | native static program |
| **bootstrap** | Builds TinyCC from source, starting from a C compiler written in shell, then the musl C library with it. | x86 or x86_64 Linux, any POSIX shell | ~4-5 min, once | native static program |
| **shell** | Compiles your program *into a shell script* with [pnut](https://github.com/udem-dlteam/pnut). | any POSIX shell | seconds | shell script (subset of C) |

Compilers that build-anywhere downloads or builds (the prebuilt gcc,
TinyCC) are kept in `~/.cache/build-anywhere` and reused; packages are
installed the normal way, by the package manager. Each tier behaves like `cc`, so
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
build-anywhere 0.2.0 on x86_64 linux
cache: /home/me/.cache/build-anywhere

system:    ok (cc)
package:   possible (gcc or clang with apt-get, with sudo)
download:  possible (gcc x86_64-linux-musl, 40-90 MB, needs network)
bootstrap: possible (one-time build, several minutes, using /usr/bin/dash)
shell:     possible (C subset only, using /usr/bin/dash)
```

Options: `--tiers=system,bootstrap` restricts and orders the tiers,
`--cache=DIR` moves the cache, `-v` shows every probe and command. The
environment variables `CC`, `BA_TIERS`, `BA_CACHE`, `BA_SHELL` and
`BA_VERBOSE=1` do the same.

## The package tier

When no compiler works, build-anywhere asks the package manager for one,
without prompts (`apt-get install -y --no-install-recommends gcc libc6-dev`,
`apk add gcc musl-dev`, `dnf install -y gcc`, `brew install gcc`, ...). If
the package lists are missing, as in a fresh container, it updates them
first. It then probes again; if gcc can't be installed or doesn't work,
it tries clang.

Most package managers need root. build-anywhere uses them when it runs as
root, when `sudo -n` or `doas -n` works without a password, or when there
is a terminal on which sudo can ask for one. Otherwise it says so and moves
on to the next tier. Homebrew, Nix (`nix build nixpkgs#gcc`, which only
adds to the Nix store) and Termux need no root. To never use root, set
`BA_SUDO=never`. To skip this tier, leave it out of `--tiers`.

## The download tier

On Linux, build-anywhere can download a complete gcc that needs nothing
from the system: gcc, binutils and musl, all statically linked. It is
unpacked to the cache, and a wrapper there runs it with `-static`, so the
programs it builds are static too and run on any Linux of the same
architecture. The archive's hash is pinned in the script, and an archive
that doesn't match is deleted without being unpacked. A toolchain that is
already in the cache is used before anything is downloaded, and if a
source is down or serves a bad file, the next one is tried:

| Machine | First choice | Then |
|---|---|---|
| x86_64 | gcc 16.2 from [qbt-musl-cross-make](https://github.com/userdocs/qbt-musl-cross-make) (GitHub) | gcc 11.2 from [musl.cc](https://musl.cc) or its mirror; gcc 16.2 from [cross-tools](https://github.com/cross-tools/musl-cross) (needs glibc) |
| arm64 | gcc 16.2 from qbt-musl-cross-make | gcc 11.2 from musl.cc |
| 32-bit x86 or armv7 user space on a 64-bit kernel (containers) | the 64-bit qbt-musl-cross-make gcc that builds 32-bit programs | gcc 11.2 from musl.cc |
| x86, armv7, armv6, ppc64le | gcc 11.2 from musl.cc or its mirror | |

musl.cc does not answer some networks (GitHub's CI runners, for
example), which is why the GitHub-hosted toolchains come first where
there are some. Each toolchain listed was tested: on x86_64 and x86
natively, and on arm64, armv7, armv6 and ppc64le under qemu-user; CI also
tests the first choices natively on x86_64, x86, arm64 and armv7. The
riscv64 and s390x toolchains on musl.cc are left out because their linker
crashed in that test.

## The bootstrap tier

This tier needs nothing but a shell. The chain is:

1. The shell runs `seed/pnut-sh.sh`, pnut's C compiler written as a POSIX
   shell script, on pnut's own C source. The result is the same compiler,
   still a shell script, but now it emits x86 machine code. (~1 minute with dash)
2. The shell runs that script on pnut's source again and writes a native
   `pnut` executable. (~3 minutes with dash)
3. The native pnut recompiles itself with every feature on, then compiles
   TinyCC 0.9.27.
4. TinyCC rebuilds itself, with a small C library of its own (`libc/`), four
   times. The last two compilers must be byte-identical (a *fixed point*),
   which shows that the chain converged. This takes a few seconds.
5. The final TinyCC builds musl, a complete C library, from `seed/musl`
   (a few seconds; no `make` is needed).

The result is a static TinyCC with musl in
`~/.cache/build-anywhere/tcc-x86_64-linux-0.2.0/`. The shell work is saved as it
goes, so an interrupted bootstrap resumes where it stopped. The fastest
installed shell is used (dash, ksh, mksh, yash, bash, then `/bin/sh`), and
`BA_SHELL` overrides the choice.

### The C library

Programs built by the bootstrapped TinyCC are linked statically against
[musl](https://musl.libc.org) 1.2.5, the MIT-licensed C library of Alpine
Linux, so your program carries no copyleft code. It is the whole library,
not a subset:

- all of C89, C99 and C11 (`<math.h>`, `<fenv.h>`, `<wchar.h>`, `<stdint.h>`,
  ...), except complex numbers, which TinyCC does not support;
- POSIX: sockets (`<sys/socket.h>`, `<netdb.h>`, `<arpa/inet.h>`, ...),
  `select`/`poll`, terminals (`<termios.h>`, `openpty`), threads
  (`<pthread.h>`), processes, signals, directories, shared memory,
  `mmap`, and the rest;
- 134 Linux kernel headers (`<linux/usbdevice_fs.h>`, `<linux/serial.h>`,
  `<linux/input.h>`, `<linux/can.h>`, `<linux/netlink.h>`, ...; the list is
  in `tools/linux-headers.list`).

`seed/musl` is musl's source for i386 and x86_64 with a few changes for
TinyCC 0.9.27 (`tools/patches/musl-1.2.5-tcc.patch`): no register variables
in the system-call wrappers, some x87/SSE inline assembly replaced by musl's
portable C, and a few instructions that TinyCC's assembler lacks written as
bytes. TinyCC itself carries three fixes backported from later versions
(`tools/patches/tcc-0.9.27-build-anywhere.patch`).

The tests check musl against glibc: `printf("%.17g")` and `strtod` give
identical results, and the maths functions are within 2 ULP (i386 evaluates
in x87 extended precision, so its last bit can differ from x86_64's). As a
real-world check, [clibretune](https://github.com/v3ai/clibretune), a
221-file GUI application, builds and passes all 81 of its test programs on
x86_64 and i386 with the bootstrapped compiler and no other compiler on the
machine.

`libc/` is a small C89 library written for this project. It is only used to
build TinyCC itself during the bootstrap (musl cannot be compiled by the
first TinyCC, which pnut compiled without floating point), and on x86_64 its
`<stdarg.h>` support routine goes into musl's `libc.a`.

## The shell tier

When nothing else works, pnut compiles your program to a POSIX shell script,
which then runs with `/bin/sh`. Only a subset of C works there: no unsigned
arithmetic, no local arrays or struct values, no taking the address of a
variable (`malloc` instead), no arrays or structs inside structs, no
variadic functions other than `printf`, no identifiers that start with `_`,
and only the library in `seed/pnut-libc/`. It is meant for small tools that
must run somewhere with nothing else, and it is much slower than a native
program.

That library has `<string.h>`, `<ctype.h>`, character and file I/O,
`malloc`, `strtol`, and:

- **Floating point.** `double` and `float` work, with all of `<math.h>`,
  `<float.h>`, `strtod`, `atof` and `printf`'s `%f`, `%e` and `%g`. A
  double is kept as its IEEE-754 bit pattern in a shell integer and
  computed in software (`seed/pnut-libc/float.c`): arithmetic and `sqrt`
  are correctly rounded, conversions to and from text are exact, and the
  maths functions are within 2 ULP of glibc's, so programs print the same
  digits as when compiled by gcc. `float` is computed as `double`. It needs
  a shell with 64-bit arithmetic, as dash, bash and BusyBox sh have on
  64-bit systems (mksh's is 32-bit), which the program checks when it
  starts. In dash an addition or multiplication takes about 0.2 ms and
  `sin` about 2 ms; bash is about four times slower.
- **Terminal control** with `stty`: `<termios.h>` (`tcgetattr`,
  `tcsetattr`, `cfmakeraw`; the flags, `VMIN` and `VTIME` are applied, the
  speeds and other control characters are not) and the terminal size with
  `ioctl(fd, TIOCGWINSZ, ws)`. In non-canonical mode `getchar` and `read`
  return each key as it is pressed, read with `dd`.
- **TCP sockets** over IPv4 (`<sys/socket.h>`, `<netinet/in.h>`,
  `<arpa/inet.h>`, `<netdb.h>`). POSIX sh cannot open a socket, so the
  program borrows one: a client uses bash's or ksh93's `/dev/tcp` when it
  runs in one of those shells, and `nc` otherwise; a server always needs
  `nc`, which takes one client at a time. Data is read a line at a time,
  so protocols must be text based, and `sin_addr` is the address itself
  (`sa->sin_addr` where C has `sa.sin_addr.s_addr`).

`seed/pnut-libc/net.c` and `term.c` list the differences from C in detail;
each library is only added to programs that use it.

pnut needs a shell other than the public-domain ksh, which crashes or
hangs running it. That ksh is `/bin/ksh` on NetBSD and both `sh` and `ksh`
on OpenBSD, so there the shell tier needs dash or bash (those systems come
with a C compiler, so the system tier normally works anyway).

## Platforms

| | system | package | download | bootstrap | shell |
|---|---|---|---|---|---|
| Linux x86_64, x86 | yes | yes | yes | yes | yes |
| Linux arm64, armv6, armv7, ppc64le | yes | yes | yes | - | yes |
| Linux riscv64, s390x, other | yes | yes | - | - | yes |
| macOS (x86_64, arm64) | yes | Homebrew, Nix, Command Line Tools | - | - | yes |
| FreeBSD | yes | yes | - | - | yes |
| NetBSD, illumos, other POSIX systems | yes | Nix | - | - | yes |
| OpenBSD | yes | Nix | - | - | with dash or bash |

On NetBSD and OpenBSD the compiler and the C headers are part of the base
system's `comp` set, which no package replaces, so there is no package
tier there.

The driver is plain POSIX `sh`. The tests run it under dash, bash,
BusyBox sh, ksh93, mksh, yash and posh on Linux, and under the native
shells of macOS, FreeBSD, OpenBSD and NetBSD.

## Security

- Only the package tier uses root, only through the system's package
  manager, and only if root is already available (see above);
  `BA_SUDO=never` turns that off. Every other tier writes only to the cache
  directory.
- Downloaded toolchains are accepted only if their hash matches the one
  pinned in the `build-anywhere` script. If no tool for that hash is
  available, the download is skipped rather than trusting an unverified
  file.
- The bootstrap starts from source that is in this repository and can be
  read. No binary is downloaded or executed.

## Testing

```sh
sh tests/run.sh                     # every tier that is quick, under every installed shell
BA_TEST_BOOTSTRAP=1 sh tests/run.sh # also the full bootstrap (~5 minutes)
BA_TEST_DOWNLOAD=1 sh tests/run.sh  # also a real download of a prebuilt gcc
sh tests/libc/run.sh                # libc/ against glibc (needs gcc and objcopy)
```

## Prior art

build-anywhere stands on these projects:

- **[pnut](https://github.com/udem-dlteam/pnut)** (Université de Montréal):
  a C compiler that emits readable POSIX shell, and the shell-to-TinyCC
  bootstrap path. Its bootstrap kit provided the TinyCC patches and
  build order used here. build-anywhere replaces the kit's GNU Mes libc
  with a small MIT library for building TinyCC, and links programs with
  musl, so they are not GPL-encumbered.
- **[musl](https://musl.libc.org)**: the C library of programs built by the
  bootstrap tier. live-bootstrap's recipe for building musl with TinyCC
  showed which parts need changes.
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
- **[qbt-musl-cross-make](https://github.com/userdocs/qbt-musl-cross-make)**,
  **[musl.cc](https://musl.cc)** and
  **[cross-tools/musl-cross](https://github.com/cross-tools/musl-cross)**,
  all built with [musl-cross-make](https://github.com/richfelker/musl-cross-make)
  or crosstool-NG: static gcc toolchains that run on any Linux, used by the
  download tier.
- **[Homebrew's installer](https://github.com/Homebrew/install)**: the way
  to install the macOS Command Line Tools without a dialog.

## License

MIT, see `LICENSE`. The vendored pnut (BSD 2-Clause) and TinyCC
(LGPL 2.1+) sources under `seed/` keep their licenses. `THIRD_PARTY.md`
explains what ends up in the programs you build.
