# Third-party code

Everything in this repository is MIT-licensed (see `LICENSE`) except the
vendored sources under `seed/pnut/`, `seed/pnut-sh.sh`, `seed/tcc/`,
`seed/musl/` and `seed/linux-headers/`.

| Path | Project | License | Ends up in your programs? |
|---|---|---|---|
| `seed/pnut/`, `seed/pnut-sh.sh` | [pnut](https://github.com/udem-dlteam/pnut), a C compiler that emits POSIX shell or x86 machine code | BSD 2-Clause (`seed/pnut/LICENSE`) | Shell tier only: the shell script pnut generates contains pnut's small runtime |
| `seed/tcc/` | [TinyCC](https://repo.or.cz/tinycc.git) 0.9.27 | LGPL 2.1 or later (`seed/tcc/COPYING`); most authors have also agreed to MIT (`seed/tcc/RELICENSING`) | See below |
| `seed/musl/` | [musl](https://musl.libc.org) 1.2.5 | MIT (`seed/musl/COPYRIGHT`) | Bootstrap tier: yes, it is the C library |
| `seed/linux-headers/` | Linux 6.12 UAPI headers, as sanitized by [sabotage-linux/kernel-headers](https://github.com/sabotage-linux/kernel-headers) | GPL-2.0 WITH Linux-syscall-note: using them in a program does not make it a derived work of Linux | Only declarations and macros, if your program includes them |

## What a program built by each tier contains

- **system** and **package**: whatever that compiler and its C library
  normally put in a program. build-anywhere adds nothing.
- **download**: the downloaded gcc links programs statically with
  [musl](https://musl.libc.org) (MIT) and gcc's `libgcc` (GPL with the GCC
  runtime-library exception, which puts no conditions on your program).
  The toolchains come from
  [qbt-musl-cross-make](https://github.com/userdocs/qbt-musl-cross-make),
  [musl.cc](https://musl.cc) and
  [cross-tools/musl-cross](https://github.com/cross-tools/musl-cross);
  they are downloaded, never stored in this repository.
- **bootstrap**: the program is linked statically with
  - musl (`seed/musl/`, MIT; keep its copyright notice if you distribute
    the program, as the MIT license asks);
  - TinyCC's `lib/libtcc1.c` (helpers for `long long` and float
    conversions), which is under the GPL with the GCC runtime-library
    exception: linking it into a program puts no conditions on that program;
  - on x86_64, `libc/ba_va.c` (MIT, part of build-anywhere), the run-time
    side of TinyCC's `<stdarg.h>`.

  The build-anywhere libc (`libc/`, MIT) is only used to build TinyCC
  itself. The TinyCC compiler (LGPL) is a tool that is run, not a part of
  your program.
- **shell**: the generated script contains pnut's runtime (BSD 2-Clause:
  keep its notice if you redistribute generated scripts) and
  `seed/pnut-libc/libc.c` (MIT).

## Changes made to the vendored code

`tools/vendor-seed.sh` regenerates `seed/` from a pnut checkout and records
every change:

- TinyCC is trimmed to the files that the x86 and x86_64 Linux compiler
  needs, and patched with the patches from pnut's bootstrap kit
  (`kit/tcc-patches/0.9.27`), which let pnut compile TinyCC and backport a
  fix for static x86_64 executables.
- `tools/patches/tcc-0.9.27-build-anywhere.patch` backports three fixes
  from later TinyCC: weak symbols in `tcc -ar` archive indexes, negated
  floating-point comparisons with a NaN on x86_64, and a register allocation
  error after converting a double to `int` on i386.
- In `lib/libtcc1.c` the floating-point literal 2^64 is replaced by a
  function that builds the same value from its bits, because the first
  TinyCC of the bootstrap is compiled by pnut, which has no floating point.
- `seed/pnut-sh.sh` is pnut compiled to shell by pnut itself
  (`pnut.c -Dtarget_sh -DNICE_UX`).
- `tools/vendor-musl.sh` regenerates `seed/musl/` and
  `seed/linux-headers/`: musl is trimmed to i386 and x86_64 (static library
  only), its complex-number functions and the old allocator are removed,
  inline-assembly maths files that TinyCC cannot compile are replaced by
  musl's own portable C versions, and `tools/patches/musl-1.2.5-tcc.patch`
  adapts the rest to TinyCC (system calls, `va_list`, assembler syntax). The
  kernel headers are the files in `tools/linux-headers.list` and everything
  they include.
