# seed/

What the bootstrap and shell tiers start from. Nothing here is a binary:
every file is shell script or C source.

| File | What it is |
|---|---|
| `pnut-sh.sh` | pnut, a C compiler, compiled to a POSIX shell script. Generated from `pnut/` by `tools/vendor-seed.sh`. |
| `pnut/` | pnut's C sources (BSD 2-Clause). |
| `tcc/` | TinyCC 0.9.27, trimmed to x86/x86_64 Linux and patched (LGPL 2.1+). |
| `bootstrap-tcc.sh` | Builds TinyCC from `pnut-sh.sh` and a shell (bootstrap tier). |
| `cc-pnut.sh` | A cc-like front end for `pnut-sh.sh` (shell tier). |
| `pnut-libc/` | The C library for programs compiled by the shell tier (MIT). |

## Provenance

| Component | Source | Version |
|---|---|---|
| pnut | https://github.com/udem-dlteam/pnut | commit `1193e7ece69d530383a8bac093b179887488858f` (2026-10-22) |
| TinyCC | `kit/tcc-0.9.27.tar.gz` in that pnut commit | 0.9.27, sha256 `db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d` |

To regenerate (maintainers only):

    git clone https://github.com/udem-dlteam/pnut /tmp/pnut
    git -C /tmp/pnut checkout 1193e7ece69d530383a8bac093b179887488858f
    tools/vendor-seed.sh /tmp/pnut seed
