# build-anywhere: floating point needs exact 64-bit shell arithmetic
# (float.c). mksh's arithmetic is 32-bit, and ksh93 keeps the result of an
# arithmetic assignment with only 18 significant digits.
__ba_t=0
: $((__ba_t = (1 << 31) * (1 << 31) + 1))
if [ "$__ba_t" != 4611686018427387905 ] || [ "$((1 << 53))" != 9007199254740992 ]; then
  echo "this program needs a shell with exact 64-bit arithmetic for floating point (dash, bash, BusyBox sh, ...)" >&2
  exit 1
fi
