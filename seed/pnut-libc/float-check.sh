# build-anywhere: floating point needs 64-bit shell arithmetic (float.c).
if [ "$((1 << 53))" != 9007199254740992 ]; then
  echo "this program needs a shell with 64-bit arithmetic for floating point" >&2
  exit 1
fi
