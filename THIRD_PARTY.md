# Third-party code

Everything in this repository is MIT-licensed (see `LICENSE`) except the
vendored sources under `seed/pnut/`, `seed/pnut-sh.sh` and `seed/tcc/`.

| Path | Project | License | Ends up in your programs? |
|---|---|---|---|
| `seed/pnut/`, `seed/pnut-sh.sh` | [pnut](https://github.com/udem-dlteam/pnut), a C compiler that emits POSIX shell or x86 machine code | BSD 2-Clause (`seed/pnut/LICENSE`) | Shell tier only: the shell script pnut generates contains pnut's small runtime |
| `seed/tcc/` | [TinyCC](https://repo.or.cz/tinycc.git) 0.9.27 | LGPL 2.1 or later (`seed/tcc/COPYING`); most authors have also agreed to MIT (`seed/tcc/RELICENSING`) | See below |

## What a program built by each tier contains

- **system** and **package**: whatever that compiler and its C library
  normally put in a program. build-anywhere adds nothing.
- **download**: the downloaded gcc links programs statically with
  [musl](https://musl.libc.org) (MIT) and gcc's `libgcc` (GPL with the GCC
  runtime-library exception, which puts no conditions on your program).
  The toolchains come from [musl.cc](https://musl.cc) and
  [cross-tools/musl-cross](https://github.com/cross-tools/musl-cross);
  they are downloaded, never stored in this repository.
- **bootstrap**: the program is linked statically with
  - the build-anywhere libc (`libc/`, MIT), written for this project;
  - TinyCC's `lib/libtcc1.c` (helpers for `long long` and float
    conversions), which is under the GPL with the GCC runtime-library
    exception: linking it into a program puts no conditions on that program;
  - TinyCC's `stdarg.h`, `float.h`, `stdbool.h` and `varargs.h` headers,
    which only contain macros and type definitions.

  TinyCC's own `lib/va_list.c` is not used; `libc/ba_va.c` replaces it.
  The TinyCC compiler itself (LGPL) is a tool that is run, not a part of
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
- In `lib/libtcc1.c` the floating-point literal 2^64 is replaced by a
  function that builds the same value from its bits, because the first
  TinyCC of the bootstrap is compiled by pnut, which has no floating point.
- `seed/pnut-sh.sh` is pnut compiled to shell by pnut itself
  (`pnut.c -Dtarget_sh -DNICE_UX`).
