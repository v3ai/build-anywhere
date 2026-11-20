#!/bin/sh
# Run in a fresh distribution container, as root, with the repository in
# the current directory: build-anywhere must install a compiler with the
# package manager and build the examples with it.
set -eux
if command -v cc || command -v gcc || command -v clang; then
    echo "this image already has a C compiler" >&2
    exit 1
fi
sh build-anywhere --doctor
sh build-anywhere -o /tmp/hello examples/hello/hello.c 2>/tmp/err || { cat /tmp/err; exit 1; }
cat /tmp/err
grep -q "installing gcc with" /tmp/err
grep -q "compiling with gcc from" /tmp/err
out=$(/tmp/hello pkg)
test "$out" = "hello, pkg"
# The second build finds the installed compiler with the system tier.
sh build-anywhere -O2 -o /tmp/uni examples/universal/main.c examples/universal/p_util.c 2>/tmp/err || { cat /tmp/err; exit 1; }
cat /tmp/err
grep -q "system compiler" /tmp/err
out=$(/tmp/uni)
test "$out" = "universal: ok"
echo "package tier: ok"
