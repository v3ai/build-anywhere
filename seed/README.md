# seed/

What the bootstrap and shell tiers start from. Nothing here is a binary:
every file is shell script or C source.

| File | What it is |
|---|---|
| `pnut-sh.sh` | pnut, a C compiler, compiled to a POSIX shell script. Generated from `pnut/` by `tools/vendor-seed.sh`. |
| `pnut/` | pnut's C sources (BSD 2-Clause). |
| `tcc/` | TinyCC 0.9.27, trimmed to x86/x86_64 Linux and patched (LGPL 2.1+). |
| `musl/` | musl 1.2.5, the C library of programs built by the bootstrap tier: trimmed to i386/x86_64 and patched for TinyCC (MIT). |
| `linux-headers/` | 134 Linux kernel headers (`<linux/*.h>`, `<asm/*.h>`) for those programs, from sabotage-linux's sanitized copy (GPL-2.0 WITH Linux-syscall-note). |
| `bootstrap-tcc.sh` | Builds TinyCC from `pnut-sh.sh` and a shell, then musl with that TinyCC (bootstrap tier). |
| `build-musl.sh` | Builds musl with TinyCC, without make (called by `bootstrap-tcc.sh`). |
| `cc-pnut.sh` | A cc-like front end for `pnut-sh.sh` (shell tier). |
| `pnut-libc/` | The C library for programs compiled by the shell tier (MIT). |

## Provenance

| Component | Source | Version |
|---|---|---|
| pnut | https://github.com/udem-dlteam/pnut | commit `1193e7ece69d530383a8bac093b179887488858f` (2026-10-22) |
| TinyCC | `kit/tcc-0.9.27.tar.gz` in that pnut commit | 0.9.27, sha256 `db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d` |
| musl | https://musl.libc.org/releases/musl-1.2.5.tar.gz | 1.2.5, sha256 `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4` |
| Linux headers | https://github.com/sabotage-linux/kernel-headers/archive/refs/tags/v6.12.77.tar.gz | 6.12.77, sha256 `cd70720ccdae889ffb4c4e7764f11b8c26add20d6bde78c0012225d52d38d3cb` |

Every change to the upstream code is in `tools/patches/` (plus the pnut
kit's TinyCC patches) and is applied by the vendor scripts. To regenerate
(maintainers only):

    git clone https://github.com/udem-dlteam/pnut /tmp/pnut
    git -C /tmp/pnut checkout 1193e7ece69d530383a8bac093b179887488858f
    tools/vendor-seed.sh /tmp/pnut seed
    tools/vendor-musl.sh musl-1.2.5.tar.gz kernel-headers-6.12.77.tar.gz seed
