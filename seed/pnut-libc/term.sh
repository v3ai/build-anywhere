# build-anywhere: terminal control for the shell tier (term.c), with stty.
# pnut's scripts run with set -e: commands that may fail end with || :.
# The flags, in the order of their bits in termios.h:
__ba_tc_flags="icanon echo echoe echok echonl isig iexten noflsh tostop icrnl inlcr igncr ixon ixoff brkint inpck istrip ignbrk parmrk ixany opost onlcr parenb parodd cstopb cread clocal hupcl"
__ba_raw_fd=-1  # the fd read byte by byte (non-canonical mode), or -1

# $2: fd. Returns the flags, or -1 when the fd is not a terminal; sets
# _ba_tty_min, _ba_tty_time and _ba_tty_speed.
_ba_sh_tcget() {
  # (fd 1 is a pipe inside $(...): pass the terminal on fd 3)
  { __ba_s=$(stty -a <&3 2>/dev/null); } 3<&$2 || { : $(($1 = -1)); return; }
  __ba_s=" $(printf '%s\n' "$__ba_s" | tr '\n;' '  ') "
  __ba_m=0; __ba_b=0
  for __ba_f in $__ba_tc_flags; do
    case "$__ba_s" in *" $__ba_f "*) : $((__ba_m |= 1 << __ba_b)) ;; esac
    : $((__ba_b += 1))
  done
  case "$__ba_s" in
    *" cs5 "*) ;;
    *" cs6 "*) : $((__ba_m |= 1 << 28)) ;;
    *" cs7 "*) : $((__ba_m |= 2 << 28)) ;;
    *) : $((__ba_m |= 3 << 28)) ;;
  esac
  _ba_tty_min=1; _ba_tty_time=0; _ba_tty_speed=38400
  case "$__ba_s" in *" min = "[0-9]*) __ba_t=${__ba_s#*" min = "}; _ba_tty_min=${__ba_t%%[!0-9]*} ;; esac
  case "$__ba_s" in *" time = "[0-9]*) __ba_t=${__ba_s#*" time = "}; _ba_tty_time=${__ba_t%%[!0-9]*} ;; esac
  case "$__ba_s" in *" speed "[0-9]*) __ba_t=${__ba_s#*" speed "}; _ba_tty_speed=${__ba_t%%[!0-9]*} ;; esac
  : $(($1 = __ba_m))
}

# $2: fd, $3: flags, $4: VMIN, $5: VTIME. Returns 0, or -1 on failure.
_ba_sh_tcset() {
  __ba_a=; __ba_b=0
  for __ba_f in $__ba_tc_flags; do
    if [ $((($3 >> __ba_b) & 1)) = 1 ]; then __ba_a="$__ba_a $__ba_f"; else __ba_a="$__ba_a -$__ba_f"; fi
    : $((__ba_b += 1))
  done
  __ba_a="$__ba_a cs$((5 + (($3 >> 28) & 3)))"
  __ba_a="$__ba_a min $4 time $5"
  if ! stty $__ba_a <&$2 2>/dev/null; then
    [ -t $2 ] || { : $(($1 = -1)); return; }
    # This stty lacks a flag: apply them one by one.
    for __ba_f in $__ba_a; do
      case $__ba_f in min|time|[0-9]*) ;; *) stty $__ba_f <&$2 2>/dev/null || : ;; esac
    done
    stty min $4 time $5 <&$2 2>/dev/null || :
  fi
  if [ $(($3 & 1)) = 0 ]; then
    __ba_raw_fd=$2
    [ $2 != 1 ] && [ $2 != 2 ] || __ba_raw_fd=0
  else
    __ba_raw_fd=-1
  fi
  : $(($1 = 0))
}

# $2: fd. Returns rows * 65536 + columns, or -1.
_ba_sh_winsize() {
  { __ba_s=$(stty size <&3 2>/dev/null); } 3<&$2 || __ba_s=
  case "$__ba_s" in
    [0-9]*" "[0-9]*) : $(($1 = ${__ba_s% *} * 65536 + ${__ba_s#* })) ;;
    *) if [ -n "${LINES-}" ] && [ -n "${COLUMNS-}" ]; then : $(($1 = LINES * 65536 + COLUMNS)); else : $(($1 = -1)); fi ;;
  esac
}

# One byte from fd $2 without waiting for a line (non-canonical mode), or -1
# when there is none (end of file, or VTIME expired).
__ba_rawbyte() {
  # (the last field of od's first line, whether or not it prints an offset)
  __ba_c=$(dd bs=1 count=1 2>/dev/null <&$2 | od -A n -t u1 | awk 'NR == 1 { print $NF + 0 }')
  case "$__ba_c" in *[0-9]*) : $(($1 = __ba_c)) ;; *) : $(($1 = -1)) ;; esac
}
