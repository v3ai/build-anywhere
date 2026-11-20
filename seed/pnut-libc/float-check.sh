# build-anywhere: floating point needs exact 64-bit shell arithmetic
# (float.c). Some shells compute in floating point (ksh93 where long double
# is a double) and lose the low bits of large integers.
if [ "$(( ((1 << 62) + 1) & 3 ))" != 1 ] || [ "$((1 << 53))" != 9007199254740992 ]; then
  echo "this program needs a shell with 64-bit integer arithmetic for floating point" >&2
  exit 1
fi
