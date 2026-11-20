# build-anywhere: TCP sockets for the shell tier (net.c). POSIX sh has no
# sockets. A client connection is bash's or ksh93's /dev/tcp when the program
# runs in one of them, otherwise nc(1) through two named pipes; a server
# always uses nc. Such a socket reads on one fd and writes on another,
# __ba_wfdN, which pnut's write and close use (see sh-runtime.c).
# pnut's scripts run with set -e: commands that may fail end with || :.
__ba_net=1
__ba_net_dir=
__ba_net_n=0

# A free fd of pnut's runtime (3 to 9) in __ba_fd, set up as _open does.
__ba_net_slot() {
  __ba_fd=3
  while [ $__ba_fd -lt 10 ]; do
    [ $((__state_fd$__ba_fd)) -lt 0 ] && break
    : $((__ba_fd += 1))
  done
  [ $__ba_fd -lt 10 ] || return 1
  _malloc __ba_addr 128     # (pnut's read_byte grows it for longer lines)
  : $((_$__ba_addr = 0))
  : $((__buffer_fd$__ba_fd = __ba_addr))
  : $((__cursor_fd$__ba_fd = 0))
  : $((__buflen_fd$__ba_fd = 128))
  : $((__state_fd$__ba_fd = 2))
}

# Returns a new socket's fd (not yet connected), or -1.
_ba_sh_socket() {
  if __ba_net_slot; then : $(($1 = __ba_fd)); else : $(($1 = -1)); fi
}

# The host name or dotted address of address $1 in __ba_host.
__ba_net_host() {
  if [ $((($1 >> 24) & 255)) = 240 ]; then
    eval "__ba_host=\$__ba_host$(($1 & 16777215))"
  else
    __ba_host="$((($1 >> 24) & 255)).$((($1 >> 16) & 255)).$((($1 >> 8) & 255)).$(($1 & 255))"
  fi
}

# Run nc with arguments "$@" for socket fd $__ba_sock, through named pipes:
# nc's output is read on $__ba_sock, its input written on another fd.
# Returns non-zero on failure.
__ba_net_nc() {
  command -v nc >/dev/null 2>&1 || return 1
  if [ -z "$__ba_net_dir" ]; then
    __ba_net_dir=$(mktemp -d 2>/dev/null) || {
      __ba_net_dir=${TMPDIR:-/tmp}/ba-net.$$
      mkdir -m 700 "$__ba_net_dir" || return 1
    }
    trap '__ba_net_exit' EXIT
    trap '__ba_net_exit; exit 130' INT TERM
  fi
  __ba_net_slot || return 1
  __ba_w=$__ba_fd
  __ba_p="${__ba_net_dir:?}/$__ba_sock"
  rm -f "$__ba_p.in" "$__ba_p.out" || :
  mkfifo "$__ba_p.in" "$__ba_p.out" || return 1
  nc "$@" <"$__ba_p.in" >"$__ba_p.out" 2>/dev/null &
  eval "__ba_pid$__ba_sock=\$!"
  eval "exec $__ba_w>\"\$__ba_p.in\" $__ba_sock<\"\$__ba_p.out\""
  eval "__ba_wfd$__ba_sock=$__ba_w"
}

# Which nc this is, in __ba_nc_l: bsd (nc -l PORT, has -4) or trad
# (nc -l -p PORT).
__ba_nc_kind() {
  if [ -z "${__ba_nc_l-}" ]; then
    case "$(nc -h 2>&1)" in
      *OpenBSD*|*"nc [-46"*) __ba_nc_l=bsd ;;
      *) __ba_nc_l=trad ;;
    esac
  fi
}

# $2: socket fd, $3: address, $4: port. Returns 0, or -1.
_ba_sh_connect() {
  __ba_net_host $3
  if [ -n "${BASH_VERSION-}" ] || case "${KSH_VERSION-}" in *93*) true ;; *) false ;; esac; then
    if eval "command exec $2<>/dev/tcp/\$__ba_host/$4" 2>/dev/null; then
      : $(($1 = 0))
    else
      : $(($1 = -1))
    fi
    return
  fi
  __ba_sock=$2
  __ba_nc_kind
  if [ $__ba_nc_l = bsd ]; then
    __ba_net_nc -4 "$__ba_host" $4 && { : $(($1 = 0)); return; }
  else
    __ba_net_nc "$__ba_host" $4 && { : $(($1 = 0)); return; }
  fi
  : $(($1 = -1))
}

# A new socket listening with nc -l on port $1 in __ba_sock, or failure.
__ba_net_listen() {
  __ba_nc_kind
  __ba_net_slot || return 1
  __ba_sock=$__ba_fd
  if [ $__ba_nc_l = bsd ]; then
    __ba_net_nc -4 -l $1 && return 0
  else
    __ba_net_nc -l -p $1 && return 0
  fi
  _close __ $__ba_sock
  return 1
}

# $2: listening socket fd, $3: port. Starts the nc -l that will take the
# first connection. Returns 0, or -1.
_ba_sh_listen() {
  if __ba_net_listen $3; then
    eval "__ba_pend$2=$__ba_sock __ba_port$2=$3"
    : $(($1 = 0))
  else
    : $(($1 = -1))
  fi
}

# $2: listening socket fd, $3: port. Returns the fd of the connection (which
# the client may not have made yet), or -1. nc -l takes a single connection
# and two of them cannot listen on one port, so the next one starts when
# this connection is closed.
_ba_sh_accept() {
  eval "__ba_c=\${__ba_pend$2-}"
  if [ -z "$__ba_c" ]; then
    if __ba_net_listen $3; then __ba_c=$__ba_sock; else : $(($1 = -1)); return; fi
  fi
  unset __ba_pend$2
  eval "__ba_from$__ba_c=$2"
  : $(($1 = __ba_c))
}

# Close the writing side of socket $2 (shutdown with SHUT_WR).
_ba_sh_shutdown() {
  eval "__ba_w=\${__ba_wfd$2-}"
  if [ -n "$__ba_w" ]; then
    eval "exec $__ba_w>&-"
    _free __ $((__buffer_fd$__ba_w))
    : $((__state_fd$__ba_w = -1))
    unset __ba_wfd$2
  fi
  : $(($1 = 0))
}

# Called by pnut's close: the writing side and the nc process of socket $1,
# and the pending connection of a listening socket.
__ba_net_close() {
  eval "__ba_c=\${__ba_pend$1-}"
  if [ -n "$__ba_c" ]; then
    unset __ba_pend$1 __ba_port$1
    _close __ $__ba_c
  fi
  _ba_sh_shutdown __ $1
  eval "__ba_p=\${__ba_pid$1-}"
  if [ -n "$__ba_p" ]; then
    kill $__ba_p 2>/dev/null || :
    unset __ba_pid$1
    rm -f "${__ba_net_dir:?}/$1.in" "${__ba_net_dir:?}/$1.out" || :
  fi
  # An accepted connection: its listening socket listens again
  eval "__ba_l=\${__ba_from$1-}"
  if [ -n "$__ba_l" ]; then
    unset __ba_from$1
    eval "__ba_c=\${__ba_pend$__ba_l-} __ba_lp=\${__ba_port$__ba_l-}"
    if [ -z "$__ba_c" ] && [ -n "$__ba_lp" ] && __ba_net_listen $__ba_lp; then
      eval "__ba_pend$__ba_l=$__ba_sock"
    fi
  fi
}

__ba_net_exit() {
  __ba_s=3
  while [ $__ba_s -lt 10 ]; do
    eval "__ba_p=\${__ba_pid$__ba_s-}"
    [ -z "$__ba_p" ] || kill $__ba_p 2>/dev/null || :
    : $((__ba_s += 1))
  done
  [ -z "$__ba_net_dir" ] || rm -rf "${__ba_net_dir:?}" || :
}

# $2: host name (a C string). Returns an address in 240.0.0.0/8 that stands
# for it; nc or /dev/tcp resolve the name when connecting.
_ba_sh_resolve() {
  : $((__ba_net_n += 1))
  eval "__ba_host$__ba_net_n=\$(_put_pstr __ $2)"
  : $(($1 = (240 << 24) + __ba_net_n))
}
