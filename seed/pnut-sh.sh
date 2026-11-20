#!/bin/sh
set -e -u -f
LC_ALL=C

_fd=-1
_fd_filepath=0
_fd_dirname=0
_include_search_path=0
_output_fd=1
_line_number=1
_column_number=0
_last_tok_line_number=1
_last_tok_column_number=0
_include_stack=0
_include_stack_top=0
: $((str = 0))
_putstr() { let str $2
  while [ $((_$str)) != 0 ]; do
    printf %b \\0$(((_$str)/64))$(((_$str)/8%8))$(((_$str)%8))
    : $((str += 1))
  done
  endlet $1 str
}

: $((__t1 = color = 0))
_change_color() { let color $2
  let __t1
  if _isatty __t1 1; [ $__t1 != 0 ] ; then
    _put_pstr __ $color
  fi
  endlet $1 __t1 color
}

: $((token = error_msg = error_prefix = 0))
_source_code_error() { let error_prefix $2; let error_msg $3; let token $4
  defstr __str_0 "[31m"
  _change_color __ $__str_0
  _put_pstr __ $error_prefix
  printf "\n"
  printf "  Reason: "
  defstr __str_1 "[33m"
  _change_color __ $__str_1
  _put_pstr __ $error_msg
  printf "\n"
  defstr __str_2 "[0m"
  _change_color __ $__str_2
  if [ $token != 0 ] ; then
    printf "  Offending token: "
    defstr __str_1 "[33m"
    _change_color __ $__str_1
    _print_tok_type __ $token
    defstr __str_2 "[0m"
    _change_color __ $__str_2
    printf "\n"
  fi
  if [ $_fd_filepath != 0 ] ; then
    printf "  Location: "
    defstr __str_3 "[32m"
    _change_color __ $__str_3
    _put_pstr __ $_fd_filepath
    printf ":%d:%d\n" $_last_tok_line_number $_last_tok_column_number
    defstr __str_2 "[0m"
    _change_color __ $__str_2
  fi
  exit 1
  endlet $1 token error_msg error_prefix
}

_fatal_error() { # msg: $2
  if [ $_fd_filepath != 0 ] ; then
    _put_pstr __ $_fd_filepath
    printf ":%d:%d: " $_last_tok_line_number $_last_tok_column_number
  fi
  _putstr __ $2
  printf "\n"
  exit 1
}

_syntax_error() { # msg: $2
  defstr __str_4 "Syntax error: "
  _source_code_error __ $__str_4 $2 0
}

_parse_error() { # msg: $2, tok_: $3
  defstr __str_5 "Parse error: "
  _source_code_error __ $__str_5 $2 $3
}

_save_include_context() {
  if [ $_include_stack_top -ge $((10 * 5)) ] ; then
    defstr __str_6 "Include stack overflow"
    _fatal_error __ $__str_6
  fi
  if [ $_fd != -1 ] ; then
    : $((_$((_include_stack + _include_stack_top)) = _fd))
    : $((_$((_include_stack + _include_stack_top + 1)) = _fd_filepath))
    : $((_$((_include_stack + _include_stack_top + 2)) = _fd_dirname))
    : $((_$((_include_stack + _include_stack_top + 3)) = _line_number))
    : $((_$((_include_stack + _include_stack_top + 4)) = _column_number))
    _include_stack_top=$((_include_stack_top + 5))
  fi
}

_restore_include_context() {
  if [ $_include_stack_top = 0 ] ; then
    defstr __str_7 "Include stack is empty"
    _fatal_error __ $__str_7
  fi
  _close __ $_fd
  if [ $_fd_dirname != 0 ] ; then
    _free __ $_fd_dirname
  fi
  _include_stack_top=$((_include_stack_top - 5))
  _fd=$((_$((_include_stack + _include_stack_top))))
  _fd_filepath=$((_$((_include_stack + _include_stack_top + 1))))
  _fd_dirname=$((_$((_include_stack + _include_stack_top + 2))))
  _line_number=$((_$((_include_stack + _include_stack_top + 3))))
  _column_number=$((_$((_include_stack + _include_stack_top + 4))))
}

#_ TOKEN enum declaration
readonly _KEYWORDS_START=300
readonly _BREAK_KW=301
readonly _CASE_KW=302
readonly _CONTINUE_KW=303
readonly _DEFAULT_KW=304
readonly _DO_KW=305
readonly _ELSE_KW=306
readonly _FOR_KW=307
readonly _IF_KW=308
readonly _RETURN_KW=309
readonly _SIZEOF_KW=310
readonly _SWITCH_KW=311
readonly _WHILE_KW=312
readonly _CONST_KW=313
readonly _AUTO_KW=314
readonly _EXTERN_KW=315
readonly _INLINE_KW=316
readonly _REGISTER_KW=317
readonly _STATIC_KW=318
readonly _TYPEDEF_KW=319
readonly _VOLATILE_KW=320
readonly _CHAR_KW=321
readonly _DOUBLE_KW=322
readonly _ENUM_KW=323
readonly _FLOAT_KW=324
readonly _INT_KW=325
readonly _LONG_KW=326
readonly _SHORT_KW=327
readonly _SIGNED_KW=328
readonly _UNSIGNED_KW=329
readonly _VOID_KW=330
readonly _GOTO_KW=331
readonly _STRUCT_KW=332
readonly _UNION_KW=333
readonly _KEYWORDS_END=334
readonly _INTEGER=401
readonly _INTEGER_HEX=402
readonly _INTEGER_OCT=403
readonly _CHARACTER=410
readonly _STRING=411
readonly _AMP_AMP=450
readonly _AMP_EQ=451
readonly _ARROW=452
readonly _BAR_BAR=453
readonly _BAR_EQ=454
readonly _CARET_EQ=455
readonly _EQ_EQ=456
readonly _GT_EQ=457
readonly _LSHIFT_EQ=458
readonly _LSHIFT=459
readonly _LT_EQ=460
readonly _MINUS_EQ=461
readonly _MINUS_MINUS=462
readonly _EXCL_EQ=463
readonly _PERCENT_EQ=464
readonly _PLUS_EQ=465
readonly _PLUS_PLUS=466
readonly _RSHIFT_EQ=467
readonly _RSHIFT=468
readonly _SLASH_EQ=469
readonly _STAR_EQ=470
readonly _HASH_HASH=471
readonly _PLUS_PLUS_PRE=472
readonly _MINUS_MINUS_PRE=473
readonly _PLUS_PLUS_POST=474
readonly _MINUS_MINUS_POST=475
readonly _ELLIPSIS=476
readonly _INITIALIZER_LIST=477
readonly _DECL=478
readonly _DECLS=479
readonly _FUN_DECL=480
readonly _CAST=481
readonly _MACRO_ARG=499
readonly _IDENTIFIER=500
readonly _TYPE=501
readonly _MACRO=502
readonly _LIST=600
_ch=0
_tok=0
_val=0
_string_pool=0
_string_pool_alloc=0
_string_start=0
_hash=0
_heap=0
_heap_alloc=1009
_alloc_obj() { # size: $2
  if [ $((_heap_alloc = _heap_alloc + $2)) -gt 786432 ] ; then
    defstr __str_8 "heap overflow"
    _fatal_error __ $__str_8
  fi
  : $(($1 = _heap_alloc - $2))
}

_get_op() { # node: $2
  : $(($1 = _$((_heap + $2)) & 1023))
}

_get_nb_children() { # node: $2
  : $(($1 = _$((_heap + $2)) >> 10))
}

_get_val() { # node: $2
  : $(($1 = _$((_heap + $2 + 1))))
}

_set_val() { # node: $2, val: $3
  : $((_$((_heap + $2 + 1)) = $3))
}

_get_child() { # node: $2, i: $3
  : $(($1 = _$((_heap + $2 + $3 + 1))))
}

_set_child() { # node: $2, i: $3, child: $4
  : $((_$((_heap + $2 + $3 + 1)) = $4))
}

_ast_result=0
_new_ast0() { # op: $2, val: $3
  _alloc_obj _ast_result 2
  : $((_$((_heap + _ast_result)) = $2))
  _set_val __ $_ast_result $3
  : $(($1 = _ast_result))
}

_new_ast1() { # op: $2, child0: $3
  _alloc_obj _ast_result 2
  : $((_$((_heap + _ast_result)) = $2 + 1024))
  _set_child __ $_ast_result 0 $3
  : $(($1 = _ast_result))
}

_new_ast2() { # op: $2, child0: $3, child1: $4
  _alloc_obj _ast_result 3
  : $((_$((_heap + _ast_result)) = $2 + 2048))
  _set_child __ $_ast_result 0 $3
  _set_child __ $_ast_result 1 $4
  : $(($1 = _ast_result))
}

_new_ast3() { # op: $2, child0: $3, child1: $4, child2: $5
  _alloc_obj _ast_result 4
  : $((_$((_heap + _ast_result)) = $2 + 3072))
  _set_child __ $_ast_result 0 $3
  _set_child __ $_ast_result 1 $4
  _set_child __ $_ast_result 2 $5
  : $(($1 = _ast_result))
}

_new_ast4() { # op: $2, child0: $3, child1: $4, child2: $5, child3: $6
  _alloc_obj _ast_result 5
  : $((_$((_heap + _ast_result)) = $2 + 4096))
  _set_child __ $_ast_result 0 $3
  _set_child __ $_ast_result 1 $4
  _set_child __ $_ast_result 2 $5
  _set_child __ $_ast_result 3 $6
  : $(($1 = _ast_result))
}

_cons() { # child0: $2, child1: $3
  _new_ast2 $1 $_LIST $2 $3
}

_car() { # pair: $2
  _get_child $1 $2 0
}

_cdr() { # pair: $2
  _get_child $1 $2 1
}

_set_car() { # pair: $2, value: $3
  _set_child $1 $2 0 $3
}

_set_cdr() { # pair: $2, value: $3
  _set_child $1 $2 1 $3
}

: $((__t1 = 0))
_list_singleton() { # list: $2
  let __t1
  if [ $2 != 0 ] && { _cdr __t1 $2; [ $__t1 = 0 ]; } ; then
    _car $1 $2
  else
    : $(($1 = 0))
  fi
  endlet $1 __t1
}

_symbol_buf() { # symbol: $2
  : $(($1 = _string_pool + _$((_heap + $2 + 1))))
}

_symbol_len() { # symbol: $2
  : $(($1 = _$((_heap + $2 + 2))))
}

_symbol_buf_end() { # symbol: $2
  : $(($1 = _string_pool + _$((_heap + $2 + 1)) + _$((_heap + $2 + 2))))
}

_symbol_type() { # symbol: $2
  : $(($1 = _$((_heap + $2 + 3))))
}

_set_symbol_type() { # symbol: $2, type: $3
  : $((_$((_heap + $2 + 3)) = $3))
}

_symbol_tag() { # symbol: $2
  : $(($1 = _$((_heap + $2 + 4))))
}

_set_symbol_tag() { # symbol: $2, tag: $3
  : $((_$((_heap + $2 + 4)) = $3))
}

_symbol_defstr_index() { # symbol: $2
  : $(($1 = _$((_heap + $2 + 5))))
}

_set_symbol_defstr_index() { # symbol: $2, index: $3
  : $((_$((_heap + $2 + 5)) = $3))
}

_begin_symbol() {
  _string_start=$_string_pool_alloc
  _hash=0
}

_accum_symbol_char() { # c: $2
  _hash=$((($2 + (_hash ^ 1026)) % 1009))
  : $((_$((_string_pool + _string_pool_alloc)) = $2))
  : $((_string_pool_alloc += 1))
  if [ $_string_pool_alloc -ge 250000 ] ; then
    defstr __str_9 "string pool overflow"
    _fatal_error __ $__str_9
  fi
}

: $((__t1 = string_end = string_start = 0))
_accum_symbol_string() { # string_symbol: $2
  let string_start; let string_end; let __t1
  _symbol_buf string_start $2
  _symbol_len __t1 $2
  string_end=$((string_start + __t1))
  while [ $string_start -lt $string_end ]; do
    _accum_symbol_char __ $((_$string_start))
    : $((string_start += 1))
  done
  endlet $1 __t1 string_end string_start
}

: $((n = 0))
_accum_symbol_integer() { let n $2
  if [ $n -lt 0 ] ; then
    _accum_symbol_char __ $__MINUS__
    _accum_symbol_integer __ $((- n))
  else
    if [ $n -gt 9 ] ; then
      _accum_symbol_integer __ $((n / 10))
    fi
    _accum_symbol_char __ $((__0__ + (n % 10)))
  fi
  endlet $1 n
}

_symbol=0
_symbol_end=0
_c1=0
_c2=0
_end_symbol_len=0
_curr_symbol=0
_end_symbol() {
  _end_symbol_len=$((_string_pool_alloc - _string_start))
  : $((_$((_string_pool + _string_pool_alloc)) = 0))
  : $((_string_pool_alloc += 1))
  _curr_symbol=$_hash
  while [ $((_symbol = _$((_heap + _curr_symbol)))) != 0 ]; do
    if [ $_end_symbol_len != $((_$((_heap + _symbol + 2)))) ] ; then
      _curr_symbol=$_symbol
      continue
    fi
    _c1=$((_string_pool + _string_start))
    _c2=$((_string_pool + _$((_heap + _symbol + 1))))
    _symbol_end=$((_c1 + _end_symbol_len))
    while [ $_c1 -lt $_symbol_end ] && [ $((_$_c1)) = $((_$_c2)) ]; do
      : $((_c1 += 1))
      : $((_c2 += 1))
    done
    if [ $_c1 = $_symbol_end ] ; then
      _string_pool_alloc=$_string_start
      : $(($1 = _symbol))
      return
    fi
    _curr_symbol=$_symbol
  done
  _alloc_obj _symbol 6
  : $((_$((_heap + _curr_symbol)) = _symbol))
  : $((_$((_heap + _symbol)) = 0))
  : $((_$((_heap + _symbol + 1)) = _string_start))
  : $((_$((_heap + _symbol + 2)) = _end_symbol_len))
  : $((_$((_heap + _symbol + 3)) = _IDENTIFIER))
  : $((_$((_heap + _symbol + 4)) = 0))
  : $((_$((_heap + _symbol + 5)) = 0))
  : $(($1 = _symbol))
}

_if_macro_stack=0
_if_macro_stack_ix=0
_if_macro_mask=1
_if_macro_executed=0
_expand_macro=1
_expand_macro_arg=1
_skip_newlines=1
_macro_stack=0
_macro_stack_ix=0
_macro_tok_lst=0
_macro_args=0
_macro_ident=0
_macro_args_count=0
_paste_last_token=0
_prev_macro_mask() {
  : $(($1 = (_if_macro_stack_ix == 0) || _$((_if_macro_stack + (_if_macro_stack_ix - 2)))))
}

: $((new_mask = 0))
_push_if_macro_mask() { let new_mask $2
  if [ $_if_macro_stack_ix -ge 20 ] ; then
    defstr __str_10 "Too many nested #ifdef/#ifndef directives. Maximum supported is 20."
    _fatal_error __ $__str_10
  fi
  : $((_$((_if_macro_stack + _if_macro_stack_ix)) = _if_macro_mask))
  : $((_$((_if_macro_stack + _if_macro_stack_ix + 1)) = _if_macro_executed))
  _if_macro_stack_ix=$((_if_macro_stack_ix + 2))
  new_mask=$((_if_macro_mask & new_mask))
  : $((_if_macro_mask = _if_macro_executed = new_mask))
  endlet $1 new_mask
}

_pop_if_macro_mask() {
  if [ $_if_macro_stack_ix = 0 ] ; then
    defstr __str_11 "Unbalanced #ifdef/#ifndef/#else/#endif directives."
    _fatal_error __ $__str_11
  fi
  _if_macro_stack_ix=$((_if_macro_stack_ix - 2))
  _if_macro_mask=$((_$((_if_macro_stack + _if_macro_stack_ix))))
  _if_macro_executed=$((_$((_if_macro_stack + _if_macro_stack_ix + 1))))
}

_io_buf=0
: $((__t1 = 0))
_read_char() { # fd: $2
  let __t1
  if _read __t1 $2 $_io_buf 1; [ $__t1 = 1 ] ; then
    : $(($1 = _$((_io_buf + 0)) & 0xff))
    endlet $1 __t1
    return
  fi
  : $(($1 = -1))
  endlet $1 __t1
}

_get_ch() {
  _read_char _ch $_fd
  if [ $_ch = -1 ] ; then
    if [ $_include_stack_top != 0 ] ; then
      _restore_include_context __
      _ch=$__LF__
    fi
  elif [ $_ch = $__LF__ ] ; then
    : $((_line_number += 1))
    _column_number=0
  else
    : $((_column_number += 1))
  fi
}

_skip_to_end_of_line() {
  while [ $_ch != $__LF__ ] && [ $_ch != -1 ]; do
    _get_ch __
  done
}

_skip_inactive_line() {
  while [ 0 -le $_ch ] && [ $_ch -le $__SPACE__ ]; do
    _get_ch __
  done
  if [ $_ch = $__HASH__ ] || [ $_ch = -1 ] ; then
    : $(($1 = 1))
  else
    _skip_to_end_of_line __
    : $(($1 = 0))
  fi
}

: $((i = str = 0))
_strlen() { let str $2
  let i
  i=0
  while [ $((_$((str + i)))) != $__NUL__ ]; do
    : $((i += 1))
  done
  : $(($1 = i))
  endlet $1 i str
}

: $((n = src = dest = 0))
_memcpy() { let dest $2; let src $3; let n $4
  while [ $n -gt 0 ]; do
    : $((_$dest = _$src))
    : $((dest += 1))
    : $((src += 1))
    : $((n -= 1))
  done
  endlet $1 n src dest
}

: $((last = c = str = 0))
_strrchr() { let str $2; let c $3
  let last
  last=0
  while [ $((_$str)) != $__NUL__ ]; do
    if [ $((_$str)) = $c ] ; then
      last=$str
    fi
    : $((str += 1))
  done
  : $(($1 = last))
  endlet $1 last c str
}

: $((s2 = s1 = 0))
_strcmp() { let s1 $2; let s2 $3
  while [ $((_$s1)) != $__NUL__ ] && [ $((_$s2)) != $__NUL__ ]; do
    if [ $((_$s1)) != $((_$s2)) ] ; then
      break
    fi
    : $((s1 += 1))
    : $((s2 += 1))
  done
  : $(($1 = _$s1 - _$s2))
  endlet $1 s2 s1
}

: $((temp = str = 0))
_substr() { let str $2 # len: $3
  let temp
  _malloc temp $(($3 + 1))
  _memcpy __ $temp $str $3
  : $((_$((temp + $3)) = __NUL__))
  : $(($1 = temp))
  endlet $1 temp str
}

: $((temp = s2_len = s1_len = s2 = s1 = 0))
_str_concat() { let s1 $2; let s2 $3
  let s1_len; let s2_len; let temp
  _strlen s1_len $s1
  _strlen s2_len $s2
  _malloc temp $((s1_len + s2_len + 1))
  _memcpy __ $temp $s1 $s1_len
  _memcpy __ $((temp + s1_len)) $s2 $s2_len
  : $((_$((temp + s1_len + s2_len)) = __NUL__))
  : $(($1 = temp))
  endlet $1 temp s2_len s1_len s2 s1
}

: $((last_slash = path = 0))
_file_parent_directory() { let path $2
  let last_slash
  _strrchr last_slash $path $__SLASH__
  if [ $last_slash = 0 ] ; then
    : $(($1 = 0))
  else
    _substr $1 $path $(((last_slash - path) + 1))
  fi
  endlet $1 last_slash path
}

: $((relative_to = file_name = 0))
_include_file() { let file_name $2; let relative_to $3
  _save_include_context __
  _fd_filepath=$file_name
  if [ $relative_to != 0 ] ; then
    _str_concat _fd_filepath $relative_to $_fd_filepath
  fi
  _open _fd $_fd_filepath 0 0
  if [ $_fd -lt 0 ] ; then
    defstr __str_12 "Could not open file"
    _fatal_error __ $__str_12
  fi
  _file_parent_directory _fd_dirname $_fd_filepath
  _line_number=1
  _column_number=0
  endlet $1 relative_to file_name
}

: $((limit = MININT = digit = base = 0))
_accum_digit() { let base $2
  let digit; let MININT; let limit
  digit=99
  MININT=-2147483648
  if [ $__0__ -le $_ch ] && [ $_ch -le $__9__ ] ; then
    digit=$((_ch - __0__))
  elif [ $__A__ -le $_ch ] && [ $_ch -le $__Z__ ] ; then
    digit=$(((_ch - __A__) + 10))
  elif [ $__a__ -le $_ch ] && [ $_ch -le $__z__ ] ; then
    digit=$(((_ch - __a__) + 10))
  fi
  if [ $digit -ge $base ] ; then
    : $(($1 = 0))
  else
    limit=$((MININT / base))
    if [ $base = 10 ] && [ $_if_macro_mask != 0 ] && { [ $_val -lt $limit ] || { [ $_val = $limit ] && [ $digit -gt $(((limit * base) - MININT)) ]; }; } ; then
      defstr __str_13 "literal integer overflow"
      _syntax_error __ $__str_13
    fi
    _val=$(((_val * base) - digit))
    _get_ch __
    : $(($1 = 1))
  fi
  endlet $1 limit MININT digit base
}

: $((__t1 = 0))
_get_string_char() {
  let __t1
  _val=$_ch
  _get_ch __
  if [ $_val = $__BACKSLASH__ ] ; then
    if [ $__0__ -le $_ch ] && [ $_ch -le $__7__ ] ; then
      _val=0
      _accum_digit __ 8
      _accum_digit __ 8
      _accum_digit __ 8
      _val=$((- _val % 256))
    elif [ $_ch = $__x__ ] || [ $_ch = $__X__ ] ; then
      _get_ch __
      _val=0
      if _accum_digit __t1 16; [ $__t1 != 0 ] ; then
        _accum_digit __ 16
      else
        defstr __str_14 "invalid hex escape -- it must have at least one digit"
        _syntax_error __ $__str_14
      fi
      _val=$((- _val % 256))
    else
      if [ $_ch = $__a__ ] ; then
        _val=7
      elif [ $_ch = $__b__ ] ; then
        _val=8
      elif [ $_ch = $__f__ ] ; then
        _val=12
      elif [ $_ch = $__n__ ] ; then
        _val=10
      elif [ $_ch = $__r__ ] ; then
        _val=13
      elif [ $_ch = $__t__ ] ; then
        _val=9
      elif [ $_ch = $__v__ ] ; then
        _val=11
      elif [ $_ch = $__BACKSLASH__ ] || [ $_ch = $__QUOTE__ ] || [ $_ch = $__DQUOTE__ ] ; then
        _val=$_ch
      else
        defstr __str_15 "unimplemented string character escape"
        _syntax_error __ $__str_15
      fi
      _get_ch __
    fi
  fi
  endlet $1 __t1
}

: $((end = 0))
_accum_string_until() { let end $2
  while [ $_ch != $end ] && [ $_ch != -1 ]; do
    _get_string_char __
    _accum_symbol_char __ $_val
  done
  if [ $_ch != $end ] ; then
    defstr __str_16 "unterminated string literal"
    _syntax_error __ $__str_16
  fi
  _get_ch __
  endlet $1 end
}

_IFDEF_ID=0
_IFNDEF_ID=0
_ELIF_ID=0
_ENDIF_ID=0
_DEFINE_ID=0
_UNDEF_ID=0
_INCLUDE_ID=0
_DEFINED_ID=0
_WARNING_ID=0
_ERROR_ID=0
_NOT_SUPPORTED_ID=0
_MAIN_ID=0
_PUTCHAR_ID=0
_GETCHAR_ID=0
_EXIT_ID=0
_MALLOC_ID=0
_FREE_ID=0
_PRINTF_ID=0
_FOPEN_ID=0
_FCLOSE_ID=0
_FGETC_ID=0
_PUTSTR_ID=0
_PUTS_ID=0
_READ_ID=0
_WRITE_ID=0
_OPEN_ID=0
_CLOSE_ID=0
_ISATTY_ID=0
_ARGV__ID=0
_ARGV_ID=0
_ENV_ID=0
_HOME_ID=0
_IFS_ID=0
_LANG_ID=0
_LC_ALL_ID=0
_LC_COLLATE_ID=0
_LC_CTYPE_ID=0
_LC_MESSAGES_ID=0
_LINENO_ID=0
_NLSPATH_ID=0
_PATH_ID=0
_PPID_ID=0
_PS1_ID=0
_PS4_ID=0
_PWD_ID=0
_FILE__ID=0
_LINE__ID=0
: $((skip_newlines_prev = prev_macro_mask = prev_expand_macro = force_newlines = 0))
_get_tok_macro() { let force_newlines $2
  let prev_expand_macro; let prev_macro_mask; let skip_newlines_prev
  prev_expand_macro=$_expand_macro
  prev_macro_mask=$_if_macro_mask
  skip_newlines_prev=$_skip_newlines
  _expand_macro=0
  _if_macro_mask=1
  if [ $force_newlines != 0 ] ; then
    _skip_newlines=0
  fi
  _get_tok __
  _expand_macro=$prev_expand_macro
  _if_macro_mask=$prev_macro_mask
  _skip_newlines=$skip_newlines_prev
  endlet $1 skip_newlines_prev prev_macro_mask prev_expand_macro force_newlines
}

: $((__t1 = ix = val = tok = args = 0))
_lookup_macro_token() { let args $2; let tok $3; let val $4
  let ix; let __t1
  ix=0
  if [ $tok -lt $_IDENTIFIER ] ; then
    _cons $1 $tok $val
    endlet $1 __t1 ix val tok args
    return
  fi
  while [ $args != 0 ]; do
    if _car __t1 $args; [ $__t1 = $val ] ; then
      break
    fi
    _cdr args $args
    : $((ix += 1))
  done
  if [ $args = 0 ] ; then
    _cons $1 $tok $val
  else
    _cons $1 $_MACRO_ARG $ix
  fi
  endlet $1 __t1 ix val tok args
}

: $((__t1 = rest = toks = args = 0))
_read_macro_tokens() { let args $2
  let toks; let rest; let __t1
  toks=0
  if [ $_tok != $__LF__ ] && [ $_tok != -1 ] ; then
    _lookup_macro_token __t1 $args $_tok $_val
    _cons toks $__t1 0
    rest=$toks
    _get_tok_macro __ 1
    while [ $_tok != $__LF__ ] && [ $_tok != -1 ]; do
      _lookup_macro_token __t1 $args $_tok $_val
      _cons __t1 $__t1 0
      _set_cdr __ $rest $__t1
      _cdr rest $rest
      _get_tok_macro __ 1
    done
    if { _car __t1 $toks; _car __t1 $__t1; [ $__t1 = $_HASH_HASH ]; } || { _car __t1 $rest; _car __t1 $__t1; [ $__t1 = $_HASH_HASH ]; } ; then
      defstr __str_17 "'##' cannot appear at either end of a macro expansion"
      _syntax_error __ $__str_17
    fi
  fi
  : $(($1 = toks))
  endlet $1 __t1 rest toks args
}

: $((__t1 = args_count = args = macro = 0))
_handle_define() {
  let macro; let args; let args_count; let __t1
  args=0
  args_count=-1
  if [ $_tok != $_IDENTIFIER ] && [ $_tok != $_MACRO ] && { [ $_tok -lt $_KEYWORDS_START ] || [ $_tok -gt $_KEYWORDS_END ]; } ; then
    defstr __str_18 "#define directive can only be followed by a identifier"
    _syntax_error __ $__str_18
  fi
  _set_symbol_type __ $_val $_MACRO
  macro=$_val
  if [ $_ch = $__LPAREN__ ] ; then
    args_count=0
    _get_tok_macro __ 1
    _get_tok_macro __ 1
    while [ $_tok != $__LF__ ] && [ $_tok != -1 ]; do
      if [ $_tok = $__COMMA__ ] ; then
        _get_tok_macro __ 1
        continue
      elif [ $_tok = $__RPAREN__ ] ; then
        _get_tok_macro __ 1
        break
      fi
      _get_tok_macro __ 1
      _cons args $_val $args
      : $((args_count += 1))
    done
  else
    _get_tok_macro __ 1
  fi
  _read_macro_tokens __t1 $args
  _cons __t1 $__t1 $args_count
  _set_symbol_tag __ $macro $__t1
  endlet $1 __t1 args_count args macro
}

: $((__t1 = val1 = val0 = op = if_macro = expr = 0))
_compute_constant() { let expr $2; let if_macro $3
  let op; let val0; let val1; let __t1
  _get_op op $expr
  if [ $op != $__QUESTION__ ] && [ $op != $_AMP_AMP ] && [ $op != $_BAR_BAR ] && [ $op != $__LPAREN__ ] ; then
    if _get_nb_children __t1 $expr; [ $__t1 -ge 1 ] ; then
      _get_child __t1 $expr 0
      _compute_constant val0 $__t1 $if_macro
    fi
    if _get_nb_children __t1 $expr; [ $__t1 -ge 2 ] ; then
      _get_child __t1 $expr 1
      _compute_constant val1 $__t1 $if_macro
    fi
  fi
  if [ $op = $_INTEGER ] || [ $op = $_INTEGER_HEX ] || [ $op = $_INTEGER_OCT ] ; then
    _get_val __t1 $expr
    : $(($1 = -__t1))
  elif [ $op = $_CHARACTER ] ; then
    _get_val $1 $expr
  elif [ $op = $__TILDE__ ] ; then
    : $(($1 = ~ val0))
  elif [ $op = $__EXCL__ ] ; then
    : $(($1 = ! val0))
  elif [ $op = $__STAR__ ] ; then
    : $(($1 = val0 * val1))
  elif [ $op = $__SLASH__ ] ; then
    : $(($1 = val0 / val1))
  elif [ $op = $__PERCENT__ ] ; then
    : $(($1 = val0 % val1))
  elif [ $op = $__AMP__ ] ; then
    : $(($1 = val0 & val1))
  elif [ $op = $__BAR__ ] ; then
    : $(($1 = val0 | val1))
  elif [ $op = $__CARET__ ] ; then
    : $(($1 = val0 ^ val1))
  elif [ $op = $_LSHIFT ] ; then
    : $(($1 = val0 << val1))
  elif [ $op = $_RSHIFT ] ; then
    : $(($1 = val0 >> val1))
  elif [ $op = $_EQ_EQ ] ; then
    : $(($1 = val0 == val1))
  elif [ $op = $_EXCL_EQ ] ; then
    : $(($1 = val0 != val1))
  elif [ $op = $_LT_EQ ] ; then
    : $(($1 = val0 <= val1))
  elif [ $op = $_GT_EQ ] ; then
    : $(($1 = val0 >= val1))
  elif [ $op = $__LT__ ] ; then
    : $(($1 = val0 < val1))
  elif [ $op = $__GT__ ] ; then
    : $(($1 = val0 > val1))
  elif [ $op = $__MINUS__ ] || [ $op = $__PLUS__ ] ; then
    if _get_nb_children __t1 $expr; [ $__t1 = 1 ] ; then
      : $(($1 = (op == __MINUS__) ? - val0 : val0))
    else
      : $(($1 = (op == __MINUS__) ? (val0 - val1) : (val0 + val1)))
    fi
  elif [ $op = $__QUESTION__ ] ; then
    _get_child __t1 $expr 0
    _compute_constant val0 $__t1 $if_macro
    if [ $val0 != 0 ] ; then
      _get_child __t1 $expr 1
      _compute_constant $1 $__t1 $if_macro
    else
      _get_child __t1 $expr 2
      _compute_constant $1 $__t1 $if_macro
    fi
  elif [ $op = $_AMP_AMP ] || [ $op = $_BAR_BAR ] ; then
    _get_child __t1 $expr 0
    _compute_constant val0 $__t1 $if_macro
    if [ $op = $_AMP_AMP ] && [ $((! val0)) != 0 ] ; then
      : $(($1 = 0))
    elif [ $op = $_BAR_BAR ] && [ $val0 != 0 ] ; then
      : $(($1 = 1))
    else
      _get_child __t1 $expr 1
      _compute_constant $1 $__t1 $if_macro
    fi
  elif [ $op = $__LPAREN__ ] ; then
    if [ $if_macro != 0 ] && { _get_child __t1 $expr 0; _get_val __t1 $__t1; [ $__t1 = $_DEFINED_ID ]; } ; then
      _get_child __t1 $expr 1
      : $(($1 = __t1 == _MACRO))
    else
      defstr __str_19 "unknown function call in constant expressions"
      _syntax_error __ $__str_19
      : $(($1 = 0))
    fi
  elif [ $op = $_IDENTIFIER ] ; then
    if [ $((! if_macro)) != 0 ] ; then
      defstr __str_20 "identifiers are not allowed in constant expression"
      _syntax_error __ $__str_20
    fi
    : $(($1 = 0))
  else
    defstr __str_21 "unsupported operator in constant expression"
    _syntax_error __ $__str_21
    : $(($1 = 0))
  fi
  endlet $1 __t1 val1 val0 op if_macro expr
}

: $((expr = previous_mask = prev_skip_newlines = 0))
_compute_if_condition() {
  let prev_skip_newlines; let previous_mask; let expr
  prev_skip_newlines=$_skip_newlines
  previous_mask=$_if_macro_mask
  _if_macro_mask=1
  _skip_newlines=0
  _get_tok __
  _parse_constant_expression expr
  _if_macro_mask=$previous_mask
  _skip_newlines=$prev_skip_newlines
  _compute_constant $1 $expr 1
  endlet $1 expr previous_mask prev_skip_newlines
}

: $((__t1 = ext = buf = 0))
_handle_include() {
  let buf; let ext; let __t1
  if [ $_tok = $_STRING ] ; then
    _symbol_buf buf $_val
    _skip_to_end_of_line __
    _include_file __ $buf $_fd_dirname
    _strrchr ext $buf $__PERIOD__
    defstr __str_22 ".sh"
    if [ $ext != 0 ] && { _strcmp __t1 $ext $__str_22; [ $__t1 = 0 ]; } ; then
      _handle_shell_include __
    fi
    _tok=$__LF__
    : $(($1 = 0))
  elif [ $_tok = $__LT__ ] ; then
    _accum_string_until __ $__GT__
    _end_symbol _val
    if [ $_include_search_path != 0 ] ; then
      _symbol_buf buf $_val
      _skip_to_end_of_line __
      _include_file __ $buf $_include_search_path
    else
      _skip_to_end_of_line __
    fi
    _tok=$__LF__
    : $(($1 = 1))
  else
    defstr __str_23 "expected string to #include directive"
    _syntax_error __ $__str_23
    : $(($1 = 0))
  fi
  endlet $1 __t1 ext buf
}

: $((__t1 = temp = 0))
_handle_preprocessor_directive() {
  let temp; let __t1
  while [ 1 != 0 ]; do
    _get_tok_macro __ 1
    _get_tok_macro __ 1
    if [ $_tok = $_IDENTIFIER ] && { [ $_val = $_IFDEF_ID ] || [ $_val = $_IFNDEF_ID ]; } ; then
      temp=$_val
      _get_tok_macro __ 1
      _push_if_macro_mask __ $(((temp == _IFDEF_ID) ? (_tok == _MACRO) : (_tok != _MACRO)))
      _get_tok_macro __ 1
    elif [ $_tok = $_IF_KW ] ; then
      _compute_if_condition temp
      _push_if_macro_mask __ $((temp != 0))
    elif [ $_tok = $_IDENTIFIER ] && [ $_val = $_ELIF_ID ] ; then
      _compute_if_condition temp
      if { _prev_macro_mask __t1; [ $__t1 != 0 ]; } && [ $((! _if_macro_executed)) != 0 ] ; then
        _if_macro_mask=$((temp != 0))
        _if_macro_executed=$((_if_macro_executed | _if_macro_mask))
      else
        _if_macro_mask=0
      fi
    elif [ $_tok = $_ELSE_KW ] ; then
      if _prev_macro_mask __t1; [ $__t1 != 0 ] ; then
        _if_macro_mask=$((! _if_macro_executed))
        _if_macro_executed=1
      else
        _if_macro_mask=0
      fi
      _get_tok_macro __ 1
    elif [ $_tok = $_IDENTIFIER ] && [ $_val = $_ENDIF_ID ] ; then
      _pop_if_macro_mask __
      _get_tok_macro __ 1
    elif [ $_if_macro_mask != 0 ] ; then
      if [ $_tok = $_IDENTIFIER ] && [ $_val = $_INCLUDE_ID ] ; then
        _get_tok_macro __ 1
        _handle_include __
      elif [ $_tok = $_IDENTIFIER ] && [ $_val = $_UNDEF_ID ] ; then
        _get_tok_macro __ 1
        if [ $_tok = $_IDENTIFIER ] || [ $_tok = $_MACRO ] ; then
          _set_symbol_type __ $_val $_IDENTIFIER
          _get_tok_macro __ 1
        else
          defstr __str_24 "#undef directive can only be followed by a identifier"
          _syntax_error __ $__str_24
        fi
      elif [ $_tok = $_IDENTIFIER ] && [ $_val = $_DEFINE_ID ] ; then
        _get_tok_macro __ 1
        _handle_define __
      elif [ $_tok = $_IDENTIFIER ] && { [ $_val = $_WARNING_ID ] || [ $_val = $_ERROR_ID ]; } ; then
        temp=$_val
        defstr __str_25 "warning: "
        defstr __str_26 "error: "
        _putstr __ $(((temp == _WARNING_ID) ? __str_25 : __str_26))
        while [ $_ch != $__LF__ ] && [ $_ch != -1 ]; do
          printf %b \\0$((_ch/64))$((_ch/8%8))$((_ch%8))
          _get_ch __
        done
        printf "\n"
        _tok=$__LF__
        if [ $temp = $_ERROR_ID ] ; then
          exit 1
        fi
      else
        defstr __str_27 "unsupported preprocessor directive"
        _syntax_error __ $__str_27
      fi
    else
      while [ $_tok != $__LF__ ] && [ $_tok != -1 ]; do
        _get_tok_macro __ 1
      done
    fi
    if [ $_tok != $__LF__ ] && [ $_tok != -1 ] ; then
      if [ $_tok = $_IDENTIFIER ] || [ $_tok = $_MACRO ] ; then
        :
      fi
      defstr __str_28 "preprocessor expected end of line"
      _syntax_error __ $__str_28
    fi
    if [ $((! _if_macro_mask)) != 0 ] ; then
      while _skip_inactive_line __t1; [ $((!__t1)) != 0 ]; do
        :
      done
      if [ $_ch = -1 ] ; then
        endlet $1 __t1 temp
        return
      fi
      _tok=$__HASH__
    else
      break
    fi
  done
  endlet $1 __t1 temp
}

_get_ident() {
  _begin_symbol __
  while { [ $__A__ -le $_ch ] && [ $_ch -le $__Z__ ]; } || { [ $__a__ -le $_ch ] && [ $_ch -le $__z__ ]; } || { [ $__0__ -le $_ch ] && [ $_ch -le $__9__ ]; } || [ $_ch = $__UNDERSCORE__ ]; do
    _accum_symbol_char __ $_ch
    _get_ch __
  done
  _end_symbol _val
  _symbol_type _tok $_val
}

: $((name = 0))
_intern_str() { let name $2
  _begin_symbol __
  while [ $((_$name)) != 0 ]; do
    _accum_symbol_char __ $((_$name))
    : $((name += 1))
  done
  _end_symbol $1
  endlet $1 name
}

: $((i = 0))
_init_ident() { # tok: $2, name: $3
  let i
  _intern_str i $3
  _set_symbol_type __ $i $2
  : $(($1 = i))
  endlet $1 i
}

: $((i = 0))
_init_ident_table() {
  let i
  i=0
  while [ $i -lt 1009 ]; do
    : $((_$((_heap + i)) = 0))
    : $((i += 1))
  done
  defstr __str_29 "break"
  _init_ident __ $_BREAK_KW $__str_29
  defstr __str_30 "case"
  _init_ident __ $_CASE_KW $__str_30
  defstr __str_31 "continue"
  _init_ident __ $_CONTINUE_KW $__str_31
  defstr __str_32 "default"
  _init_ident __ $_DEFAULT_KW $__str_32
  defstr __str_33 "do"
  _init_ident __ $_DO_KW $__str_33
  defstr __str_34 "else"
  _init_ident __ $_ELSE_KW $__str_34
  defstr __str_35 "for"
  _init_ident __ $_FOR_KW $__str_35
  defstr __str_36 "if"
  _init_ident __ $_IF_KW $__str_36
  defstr __str_37 "return"
  _init_ident __ $_RETURN_KW $__str_37
  defstr __str_38 "sizeof"
  _init_ident __ $_SIZEOF_KW $__str_38
  defstr __str_39 "switch"
  _init_ident __ $_SWITCH_KW $__str_39
  defstr __str_40 "while"
  _init_ident __ $_WHILE_KW $__str_40
  defstr __str_41 "char"
  _init_ident __ $_CHAR_KW $__str_41
  defstr __str_42 "double"
  _init_ident __ $_DOUBLE_KW $__str_42
  defstr __str_43 "enum"
  _init_ident __ $_ENUM_KW $__str_43
  defstr __str_44 "float"
  _init_ident __ $_FLOAT_KW $__str_44
  defstr __str_45 "int"
  _init_ident __ $_INT_KW $__str_45
  defstr __str_46 "long"
  _init_ident __ $_LONG_KW $__str_46
  defstr __str_47 "short"
  _init_ident __ $_SHORT_KW $__str_47
  defstr __str_48 "signed"
  _init_ident __ $_SIGNED_KW $__str_48
  defstr __str_49 "unsigned"
  _init_ident __ $_UNSIGNED_KW $__str_49
  defstr __str_50 "void"
  _init_ident __ $_VOID_KW $__str_50
  defstr __str_51 "const"
  _init_ident __ $_CONST_KW $__str_51
  defstr __str_52 "auto"
  _init_ident __ $_AUTO_KW $__str_52
  defstr __str_53 "extern"
  _init_ident __ $_EXTERN_KW $__str_53
  defstr __str_54 "inline"
  _init_ident __ $_INLINE_KW $__str_54
  defstr __str_55 "register"
  _init_ident __ $_REGISTER_KW $__str_55
  defstr __str_56 "static"
  _init_ident __ $_STATIC_KW $__str_56
  defstr __str_57 "typedef"
  _init_ident __ $_TYPEDEF_KW $__str_57
  defstr __str_58 "volatile"
  _init_ident __ $_VOLATILE_KW $__str_58
  defstr __str_59 "goto"
  _init_ident __ $_GOTO_KW $__str_59
  defstr __str_60 "struct"
  _init_ident __ $_STRUCT_KW $__str_60
  defstr __str_61 "union"
  _init_ident __ $_UNION_KW $__str_61
  defstr __str_62 "ifdef"
  _init_ident _IFDEF_ID $_IDENTIFIER $__str_62
  defstr __str_63 "ifndef"
  _init_ident _IFNDEF_ID $_IDENTIFIER $__str_63
  defstr __str_64 "elif"
  _init_ident _ELIF_ID $_IDENTIFIER $__str_64
  defstr __str_65 "endif"
  _init_ident _ENDIF_ID $_IDENTIFIER $__str_65
  defstr __str_66 "define"
  _init_ident _DEFINE_ID $_IDENTIFIER $__str_66
  defstr __str_67 "undef"
  _init_ident _UNDEF_ID $_IDENTIFIER $__str_67
  defstr __str_68 "include"
  _init_ident _INCLUDE_ID $_IDENTIFIER $__str_68
  defstr __str_69 "defined"
  _init_ident _DEFINED_ID $_IDENTIFIER $__str_69
  defstr __str_70 "main"
  _init_ident _MAIN_ID $_IDENTIFIER $__str_70
  defstr __str_71 "putchar"
  _init_ident _PUTCHAR_ID $_IDENTIFIER $__str_71
  defstr __str_72 "exit"
  _init_ident _EXIT_ID $_IDENTIFIER $__str_72
  defstr __str_73 "malloc"
  _init_ident _MALLOC_ID $_IDENTIFIER $__str_73
  defstr __str_74 "free"
  _init_ident _FREE_ID $_IDENTIFIER $__str_74
  defstr __str_75 "printf"
  _init_ident _PRINTF_ID $_IDENTIFIER $__str_75
  defstr __str_76 "putstr"
  _init_ident _PUTSTR_ID $_IDENTIFIER $__str_76
  defstr __str_77 "puts"
  _init_ident _PUTS_ID $_IDENTIFIER $__str_77
  defstr __str_78 "read"
  _init_ident _READ_ID $_IDENTIFIER $__str_78
  defstr __str_79 "write"
  _init_ident _WRITE_ID $_IDENTIFIER $__str_79
  defstr __str_80 "open"
  _init_ident _OPEN_ID $_IDENTIFIER $__str_80
  defstr __str_81 "close"
  _init_ident _CLOSE_ID $_IDENTIFIER $__str_81
  defstr __str_82 "getchar"
  _init_ident _GETCHAR_ID $_IDENTIFIER $__str_82
  defstr __str_83 "fopen"
  _init_ident _FOPEN_ID $_IDENTIFIER $__str_83
  defstr __str_84 "fclose"
  _init_ident _FCLOSE_ID $_IDENTIFIER $__str_84
  defstr __str_85 "fgetc"
  _init_ident _FGETC_ID $_IDENTIFIER $__str_85
  defstr __str_86 "isatty"
  _init_ident _ISATTY_ID $_IDENTIFIER $__str_86
  defstr __str_87 "argv"
  _init_ident _ARGV_ID $_IDENTIFIER $__str_87
  defstr __str_88 "argv_"
  _init_ident _ARGV__ID $_IDENTIFIER $__str_88
  defstr __str_89 "ENV"
  _init_ident _ENV_ID $_IDENTIFIER $__str_89
  defstr __str_90 "HOME"
  _init_ident _HOME_ID $_IDENTIFIER $__str_90
  defstr __str_91 "IFS"
  _init_ident _IFS_ID $_IDENTIFIER $__str_91
  defstr __str_92 "LANG"
  _init_ident _LANG_ID $_IDENTIFIER $__str_92
  defstr __str_93 "LC_ALL"
  _init_ident _LC_ALL_ID $_IDENTIFIER $__str_93
  defstr __str_94 "LC_COLLATE"
  _init_ident _LC_COLLATE_ID $_IDENTIFIER $__str_94
  defstr __str_95 "LC_CTYPE"
  _init_ident _LC_CTYPE_ID $_IDENTIFIER $__str_95
  defstr __str_96 "LC_MESSAGES"
  _init_ident _LC_MESSAGES_ID $_IDENTIFIER $__str_96
  defstr __str_97 "LINENO"
  _init_ident _LINENO_ID $_IDENTIFIER $__str_97
  defstr __str_98 "NLSPATH"
  _init_ident _NLSPATH_ID $_IDENTIFIER $__str_98
  defstr __str_99 "PATH"
  _init_ident _PATH_ID $_IDENTIFIER $__str_99
  defstr __str_100 "PPID"
  _init_ident _PPID_ID $_IDENTIFIER $__str_100
  defstr __str_101 "PS1"
  _init_ident _PS1_ID $_IDENTIFIER $__str_101
  defstr __str_102 "PS4"
  _init_ident _PS4_ID $_IDENTIFIER $__str_102
  defstr __str_103 "PWD"
  _init_ident _PWD_ID $_IDENTIFIER $__str_103
  defstr __str_104 "warning"
  _init_ident _WARNING_ID $_IDENTIFIER $__str_104
  defstr __str_105 "error"
  _init_ident _ERROR_ID $_IDENTIFIER $__str_105
  defstr __str_106 "NOT_SUPPORTED"
  _init_ident _NOT_SUPPORTED_ID $_IDENTIFIER $__str_106
  endlet $1 i
}

: $((__t1 = value_symb = macro_id = 0))
_set_builtin_string_macro() { let macro_id $2; let value_symb $3
  let __t1
  _cons __t1 $_STRING $value_symb
  _cons __t1 $__t1 0
  _cons __t1 $__t1 -1
  _set_symbol_tag __ $macro_id $__t1
  : $(($1 = macro_id))
  endlet $1 __t1 value_symb macro_id
}

: $((__t2 = __t1 = value = macro_str = 0))
_init_builtin_string_macro() { let macro_str $2; let value $3
  let __t1; let __t2
  _init_ident __t1 $_MACRO $macro_str
  _intern_str __t2 $value
  _set_builtin_string_macro $1 $__t1 $__t2
  endlet $1 __t2 __t1 value macro_str
}

: $((__t1 = value = macro_id = 0))
_set_builtin_int_macro() { let macro_id $2; let value $3
  let __t1
  _cons __t1 $_INTEGER $((- value))
  _cons __t1 $__t1 0
  _cons __t1 $__t1 -1
  _set_symbol_tag __ $macro_id $__t1
  : $(($1 = macro_id))
  endlet $1 __t1 value macro_id
}

: $((__t1 = value = macro_str = 0))
_init_builtin_int_macro() { let macro_str $2; let value $3
  let __t1
  _init_ident __t1 $_MACRO $macro_str
  _set_builtin_int_macro $1 $__t1 $value
  endlet $1 __t1 value macro_str
}

: $((__t1 = macro_id = 0))
_set_builtin_empty_macro() { let macro_id $2
  let __t1
  _cons __t1 0 -1
  _set_symbol_tag __ $macro_id $__t1
  : $(($1 = macro_id))
  endlet $1 __t1 macro_id
}

_init_pnut_macros() {
  defstr __str_107 "PNUT_CC"
  _init_builtin_int_macro __ $__str_107 1
  defstr __str_108 "__DATE__"
  defstr __str_109 "Jan  1 1970"
  _init_builtin_string_macro __ $__str_108 $__str_109
  defstr __str_110 "__TIME__"
  defstr __str_111 "00:00:00"
  _init_builtin_string_macro __ $__str_110 $__str_111
  defstr __str_112 "__TIMESTAMP__"
  defstr __str_113 "Jan  1 1970 00:00:00"
  _init_builtin_string_macro __ $__str_112 $__str_113
  defstr __str_114 "__FILE__"
  defstr __str_115 "<unknown>"
  _init_builtin_string_macro _FILE__ID $__str_114 $__str_115
  defstr __str_116 "__LINE__"
  _init_builtin_int_macro _LINE__ID $__str_116 0
  defstr __str_117 "PNUT_SH"
  _init_builtin_int_macro __ $__str_117 1
}

: $((__t1 = rest = parens_depth = arg_tokens = 0))
_macro_parse_argument() {
  let arg_tokens; let parens_depth; let rest; let __t1
  arg_tokens=0
  parens_depth=0
  while { [ $parens_depth -gt 0 ] || { [ $_tok != $__COMMA__ ] && [ $_tok != $__RPAREN__ ]; }; } && [ $_tok != -1 ]; do
    parens_depth=$(((parens_depth + (_tok == __LPAREN__)) - (_tok == __RPAREN__)))
    if [ $arg_tokens = 0 ] ; then
      _cons __t1 $_tok $_val
      _cons arg_tokens $__t1 0
      rest=$arg_tokens
    else
      _cons __t1 $_tok $_val
      _cons __t1 $__t1 0
      _set_cdr __ $rest $__t1
      _cdr rest $rest
    fi
    _get_tok_macro __ 0
  done
  : $(($1 = arg_tokens))
  endlet $1 __t1 rest parens_depth arg_tokens
}

: $((__t1 = expected_argc = macro = macro_args_count = 0))
_check_macro_arity() { let macro_args_count $2; let macro $3
  let expected_argc; let __t1
  _symbol_tag __t1 $macro
  _cdr expected_argc $__t1
  if [ $macro_args_count != $expected_argc ] ; then
    defstr __str_118 "macro argument count mismatch"
    _syntax_error __ $__str_118
  fi
  endlet $1 __t1 expected_argc macro macro_args_count
}

: $((__t1 = prev_is_comma = macro_args_count = args = macro = 0))
_get_macro_args_toks() { let macro $2
  let args; let macro_args_count; let prev_is_comma; let __t1
  args=0
  macro_args_count=0
  prev_is_comma=$((_tok == __COMMA__))
  _get_tok_macro __ 0
  while [ $_tok != $__RPAREN__ ] && [ $_tok != -1 ]; do
    if [ $_tok = $__COMMA__ ] ; then
      _get_tok_macro __ 0
      if [ $prev_is_comma != 0 ] ; then
        _cons args 0 $args
        : $((macro_args_count += 1))
      fi
      prev_is_comma=1
      continue
    else
      prev_is_comma=0
    fi
    _macro_parse_argument __t1
    _cons args $__t1 $args
    : $((macro_args_count += 1))
  done
  if [ $_tok != $__RPAREN__ ] ; then
    defstr __str_119 "unterminated macro argument list"
    _parse_error __ $__str_119 $_tok
  fi
  if [ $prev_is_comma != 0 ] ; then
    _cons args 0 $args
    : $((macro_args_count += 1))
  fi
  _check_macro_arity __ $macro_args_count $macro
  : $(($1 = args))
  endlet $1 __t1 prev_is_comma macro_args_count args macro
}

: $((arg = ix = 0))
_get_macro_arg() { let ix $2
  let arg
  arg=$_macro_args
  while [ $ix -gt 0 ]; do
    if [ $arg = 0 ] ; then
      defstr __str_120 "get_macro_arg: argument index out of range"
      _fatal_error __ $__str_120
    fi
    _cdr arg $arg
    : $((ix -= 1))
  done
  _car $1 $arg
  endlet $1 arg ix
}

_return_to_parent_macro() {
  if [ $_macro_stack_ix = 0 ] ; then
    defstr __str_121 "return_to_parent_macro: no parent macro"
    _fatal_error __ $__str_121
  fi
  _macro_stack_ix=$((_macro_stack_ix - 3))
  _macro_tok_lst=$((_$((_macro_stack + _macro_stack_ix))))
  _macro_args=$((_$((_macro_stack + _macro_stack_ix + 1))))
  _macro_ident=$((_$((_macro_stack + _macro_stack_ix + 2))))
}

: $((args = tokens = ident = 0))
_begin_macro_expansion() { let ident $2; let tokens $3; let args $4
  if [ $((_macro_stack_ix + 3)) -ge 180 ] ; then
    defstr __str_122 "Macro recursion depth exceeded."
    _fatal_error __ $__str_122
  fi
  : $((_$((_macro_stack + _macro_stack_ix)) = _macro_tok_lst))
  : $((_$((_macro_stack + _macro_stack_ix + 1)) = _macro_args))
  : $((_$((_macro_stack + _macro_stack_ix + 2)) = _macro_ident))
  _macro_stack_ix=$((_macro_stack_ix + 3))
  _macro_ident=$ident
  _macro_tok_lst=$tokens
  _macro_args=$args
  endlet $1 args tokens ident
}

: $((i = ident = 0))
_macro_is_already_expanding() { let ident $2
  let i
  i=$_macro_stack_ix
  if [ $ident = 0 ] || [ $_macro_ident = 0 ] ; then
    : $(($1 = 0))
    endlet $1 i ident
    return
  fi
  if [ $ident = $_macro_ident ] ; then
    : $(($1 = 1))
    endlet $1 i ident
    return
  fi
  while [ $i -gt 0 ]; do
    i=$((i - 3))
    if [ $((_$((_macro_stack + i + 2)))) = $ident ] ; then
      : $(($1 = 1))
      endlet $1 i ident
      return
    fi
  done
  : $(($1 = 0))
  endlet $1 i ident
}

: $((__t1 = prev_val = prev_tok = 0))
_undo_token() { let prev_tok $2; let prev_val $3
  let __t1
  _cons __t1 $_tok $_val
  _cons __t1 $__t1 0
  _begin_macro_expansion __ 0 $__t1 0
  _tok=$prev_tok
  _val=$prev_val
  endlet $1 __t1 prev_val prev_tok
}

: $((__t1 = tokens = macro = 0))
_attempt_macro_expansion() { let macro $2
  let tokens; let __t1
  _symbol_tag __t1 $macro
  _car tokens $__t1
  if _macro_is_already_expanding __t1 $macro; [ $__t1 != 0 ] ; then
    _tok=$_IDENTIFIER
    _val=$macro
    : $(($1 = 0))
  elif _symbol_tag __t1 $macro; _cdr __t1 $__t1; [ $__t1 = -1 ] ; then
    if [ $macro = $_FILE__ID ] ; then
      _intern_str __t1 $_fd_filepath
      _cons __t1 $_STRING $__t1
      _cons tokens $__t1 0
    elif [ $macro = $_LINE__ID ] ; then
      _cons __t1 $_INTEGER $((- _line_number))
      _cons tokens $__t1 0
    fi
    _begin_macro_expansion __ $macro $tokens 0
    : $(($1 = 1))
  else
    _get_tok __
    if [ $_tok = $__LPAREN__ ] ; then
      _get_macro_args_toks __t1 $macro
      _begin_macro_expansion __ $macro $tokens $__t1
      : $(($1 = 1))
    else
      _undo_token __ $_IDENTIFIER $macro
      : $(($1 = 0))
    fi
  fi
  endlet $1 __t1 tokens macro
}

: $((__t1 = arg = 0))
_stringify() {
  let arg; let __t1
  _expand_macro_arg=0
  _get_tok_macro __ 1
  _expand_macro_arg=1
  if [ $_tok != $_MACRO_ARG ] ; then
    defstr __str_123 "expected macro argument after #"
    _syntax_error __ $__str_123
  fi
  _get_macro_arg arg $_val
  _car __t1 $arg
  _car _tok $__t1
  if { [ $_tok = $_IDENTIFIER ] || [ $_tok = $_MACRO ] || { [ $_KEYWORDS_START -le $_tok ] && [ $_tok -le $_KEYWORDS_END ]; }; } && { _cdr __t1 $arg; [ $__t1 = 0 ]; } ; then
    _car __t1 $arg
    _cdr _val $__t1
  else
    _val=$_NOT_SUPPORTED_ID
  fi
  _tok=$_STRING
  endlet $1 __t1 arg
}

: $((right_digits = result = right_val = left_val = 0))
_paste_integers() { let left_val $2; let right_val $3
  let result; let right_digits
  result=$left_val
  right_digits=$right_val
  while [ $right_digits -gt 0 ]; do
    result=$((result * 10))
    right_digits=$((right_digits / 10))
  done
  : $(($1 = result + right_val))
  endlet $1 right_digits result right_val left_val
}

: $((__t1 = right_val = right_tok = left_val = left_tok = 0))
_paste_tokens() { let left_tok $2; let left_val $3
  let right_tok; let right_val; let __t1
  _expand_macro_arg=0
  _get_tok_macro __ 1
  _expand_macro_arg=1
  if [ $_tok = $_MACRO_ARG ] ; then
    if _get_macro_arg __t1 $_val; [ $__t1 = 0 ] ; then
      _tok=$left_tok
      _val=$left_val
      endlet $1 __t1 right_val right_tok left_val left_tok
      return
    else
      _get_macro_arg __t1 $_val
      _begin_macro_expansion __ 0 $__t1 0
      _get_tok_macro __ 1
    fi
  fi
  right_tok=$_tok
  right_val=$_val
  if [ $left_tok = $_IDENTIFIER ] || [ $left_tok = $_TYPE ] || [ $left_tok = $_MACRO ] || { [ $_KEYWORDS_START -le $left_tok ] && [ $left_tok -le $_KEYWORDS_END ]; } ; then
    _begin_symbol __
    _accum_symbol_string __ $left_val
    if [ $right_tok = $_IDENTIFIER ] || [ $right_tok = $_TYPE ] || [ $right_tok = $_MACRO ] || { [ $_KEYWORDS_START -le $right_tok ] && [ $right_tok -le $_KEYWORDS_END ]; } ; then
      _accum_symbol_string __ $right_val
    elif [ $right_tok = $_INTEGER ] || [ $right_tok = $_INTEGER_HEX ] || [ $right_tok = $_INTEGER_OCT ] ; then
      _accum_symbol_integer __ $((- right_val))
    else
      defstr __str_124 "cannot paste an identifier with a non-identifier or non-negative integer"
      _syntax_error __ $__str_124
    fi
    _end_symbol _val
    _symbol_type _tok $_val
  elif [ $left_tok = $_INTEGER ] || [ $left_tok = $_INTEGER_HEX ] || [ $left_tok = $_INTEGER_OCT ] ; then
    if [ $right_tok = $_INTEGER ] || [ $right_tok = $_INTEGER_HEX ] || [ $right_tok = $_INTEGER_OCT ] ; then
      _paste_integers __t1 $((- left_val)) $((- right_val))
      _val=$((-__t1))
    elif [ $right_tok = $_IDENTIFIER ] || [ $right_tok = $_MACRO ] || { [ $_KEYWORDS_START -le $right_tok ] && [ $right_tok -le $_KEYWORDS_END ]; } ; then
      _begin_symbol __
      _accum_symbol_integer __ $((- left_val))
      _accum_symbol_string __ $right_val
      _end_symbol _val
      _symbol_type _tok $_val
    else
      defstr __str_125 "cannot paste an integer with a non-integer"
      _syntax_error __ $__str_125
    fi
  else
    defstr __str_126 "cannot paste a non-identifier or non-integer"
    _syntax_error __ $__str_126
  fi
  endlet $1 __t1 right_val right_tok left_val left_tok
}

: $((__t1 = prev_tok_column_number = prev_tok_line_number = 0))
_get_tok() {
  let prev_tok_line_number; let prev_tok_column_number; let __t1
  prev_tok_line_number=$_line_number
  prev_tok_column_number=$_column_number
  while [ 1 != 0 ]; do
    if [ $_macro_tok_lst != 0 ] ; then
      _car __t1 $_macro_tok_lst
      _car _tok $__t1
      _car __t1 $_macro_tok_lst
      _cdr _val $__t1
      _cdr _macro_tok_lst $_macro_tok_lst
      if [ $_tok -ge $_IDENTIFIER ] ; then
        _symbol_type _tok $_val
      fi
      if [ $_macro_tok_lst != 0 ] && { _car __t1 $_macro_tok_lst; _car __t1 $__t1; [ $__t1 = $_HASH_HASH ]; } ; then
        if [ $_tok = $_MACRO ] || [ $_tok = $_MACRO_ARG ] ; then
          _cdr _macro_tok_lst $_macro_tok_lst
          _paste_last_token=1
        else
          _cdr _macro_tok_lst $_macro_tok_lst
          _paste_tokens __ $_tok $_val
        fi
      elif [ $_macro_tok_lst = 0 ] && [ $_paste_last_token != 0 ] ; then
        if [ $_macro_stack_ix = 0 ] ; then
          defstr __str_127 "## cannot appear at the end of a macro expansion"
          _syntax_error __ $__str_127
        fi
        _return_to_parent_macro __
        _paste_last_token=0
        _paste_tokens __ $_tok $_val
      fi
      if [ $_tok = $_MACRO ] ; then
        if _attempt_macro_expansion __t1 $_val; [ $__t1 != 0 ] ; then
          continue
        fi
        break
      elif [ $_tok = $_MACRO_ARG ] && [ $_expand_macro_arg != 0 ] ; then
        _get_macro_arg __t1 $_val
        _begin_macro_expansion __ 0 $__t1 0
        continue
      elif [ $_tok = $__HASH__ ] ; then
        _stringify __
        break
      fi
      break
    elif [ $_macro_stack_ix != 0 ] ; then
      _return_to_parent_macro __
      continue
    elif [ $_ch -le $__SPACE__ ] ; then
      if [ $_ch = -1 ] ; then
        _tok=-1
        break
      fi
      _tok=0
      while [ 0 -le $_ch ] && [ $_ch -le $__SPACE__ ]; do
        if [ $_ch = $__LF__ ] ; then
          _tok=$_ch
        fi
        _get_ch __
      done
      if [ $_tok = $__LF__ ] && [ $((! _skip_newlines)) != 0 ] ; then
        break
      fi
    elif [ $_tok = $__LF__ ] && [ $_ch = $__HASH__ ] ; then
      _tok=0
      _handle_preprocessor_directive __
    elif { [ $__a__ -le $_ch ] && [ $_ch -le $__z__ ]; } || { [ $__A__ -le $_ch ] && [ $_ch -le $__Z__ ]; } || [ $_ch = $__UNDERSCORE__ ] ; then
      _get_ident __
      if [ $_tok = $_MACRO ] ; then
        if [ $_expand_macro != 0 ] ; then
          if _attempt_macro_expansion __t1 $_val; [ $__t1 != 0 ] ; then
            continue
          fi
          break
        fi
      fi
      break
    elif [ $__0__ -le $_ch ] && [ $_ch -le $__9__ ] ; then
      _val=0
      _tok=$_INTEGER
      if [ $_ch = $__0__ ] ; then
        _get_ch __
        if [ $_ch = $__x__ ] || [ $_ch = $__X__ ] ; then
          _tok=$_INTEGER_HEX
          _get_ch __
          if _accum_digit __t1 16; [ $__t1 != 0 ] ; then
            while _accum_digit __t1 16; [ $__t1 != 0 ]; do
              :
            done
          else
            defstr __str_128 "invalid hex integer -- it must have at least one digit"
            _syntax_error __ $__str_128
          fi
        else
          while _accum_digit __t1 8; [ $__t1 != 0 ]; do
            :
          done
          _tok=$(((_val == 0) ? _INTEGER : _INTEGER_OCT))
        fi
      else
        while _accum_digit __t1 10; [ $__t1 != 0 ]; do
          :
        done
      fi
      break
    elif [ $_ch = $__QUOTE__ ] ; then
      _get_ch __
      _get_string_char __
      if [ $_ch != $__QUOTE__ ] ; then
        defstr __str_129 "unterminated character literal"
        _syntax_error __ $__str_129
      fi
      _get_ch __
      _tok=$_CHARACTER
      break
    elif [ $_ch = $__DQUOTE__ ] ; then
      _get_ch __
      _begin_symbol __
      _accum_string_until __ $__DQUOTE__
      _end_symbol _val
      _tok=$_STRING
      break
    else
      _tok=$_ch
      if [ $_ch = $__SLASH__ ] ; then
        _get_ch __
        if [ $_ch = $__STAR__ ] ; then
          _get_ch __
          _tok=$_ch
          while { [ $_tok != $__STAR__ ] || [ $_ch != $__SLASH__ ]; } && [ $_ch != -1 ]; do
            _tok=$_ch
            _get_ch __
          done
          if [ $_ch = -1 ] ; then
            defstr __str_130 "unterminated comment"
            _syntax_error __ $__str_130
          fi
          _get_ch __
        elif [ $_ch = $__SLASH__ ] ; then
          _skip_to_end_of_line __
        else
          if [ $_ch = $__EQ__ ] ; then
            _get_ch __
            _tok=$_SLASH_EQ
          fi
          break
        fi
      elif [ $_ch = $__AMP__ ] ; then
        _get_ch __
        if [ $_ch = $__AMP__ ] ; then
          _get_ch __
          _tok=$_AMP_AMP
        elif [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_AMP_EQ
        fi
        break
      elif [ $_ch = $__BAR__ ] ; then
        _get_ch __
        if [ $_ch = $__BAR__ ] ; then
          _get_ch __
          _tok=$_BAR_BAR
        elif [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_BAR_EQ
        fi
        break
      elif [ $_ch = $__LT__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_LT_EQ
        elif [ $_ch = $__LT__ ] ; then
          _get_ch __
          if [ $_ch = $__EQ__ ] ; then
            _get_ch __
            _tok=$_LSHIFT_EQ
          else
            _tok=$_LSHIFT
          fi
        fi
        break
      elif [ $_ch = $__GT__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_GT_EQ
        elif [ $_ch = $__GT__ ] ; then
          _get_ch __
          if [ $_ch = $__EQ__ ] ; then
            _get_ch __
            _tok=$_RSHIFT_EQ
          else
            _tok=$_RSHIFT
          fi
        fi
        break
      elif [ $_ch = $__EQ__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_EQ_EQ
        fi
        break
      elif [ $_ch = $__EXCL__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_EXCL_EQ
        fi
        break
      elif [ $_ch = $__PLUS__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_PLUS_EQ
        elif [ $_ch = $__PLUS__ ] ; then
          _get_ch __
          _tok=$_PLUS_PLUS
        fi
        break
      elif [ $_ch = $__MINUS__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_MINUS_EQ
        elif [ $_ch = $__GT__ ] ; then
          _get_ch __
          _tok=$_ARROW
        elif [ $_ch = $__MINUS__ ] ; then
          _get_ch __
          _tok=$_MINUS_MINUS
        fi
        break
      elif [ $_ch = $__STAR__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_STAR_EQ
        fi
        break
      elif [ $_ch = $__PERCENT__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_PERCENT_EQ
        fi
        break
      elif [ $_ch = $__CARET__ ] ; then
        _get_ch __
        if [ $_ch = $__EQ__ ] ; then
          _get_ch __
          _tok=$_CARET_EQ
        fi
        break
      elif [ $_ch = $__HASH__ ] ; then
        _get_ch __
        if [ $_ch = $__HASH__ ] ; then
          _get_ch __
          _tok=$_HASH_HASH
        fi
        break
      elif [ $_ch = $__PERIOD__ ] ; then
        _get_ch __
        if [ $_ch = $__PERIOD__ ] ; then
          _get_ch __
          if [ $_ch = $__PERIOD__ ] ; then
            _get_ch __
            _tok=$_ELLIPSIS
          else
            defstr __str_131 "invalid token"
            _syntax_error __ $__str_131
          fi
        fi
        break
      elif [ $_ch = $__TILDE__ ] || [ $_ch = $__PERIOD__ ] || [ $_ch = $__QUESTION__ ] || [ $_ch = $__COMMA__ ] || [ $_ch = $__COLON__ ] || [ $_ch = $__SEMICOLON__ ] || [ $_ch = $__LPAREN__ ] || [ $_ch = $__RPAREN__ ] || [ $_ch = $__LBRACK__ ] || [ $_ch = $__RBRACK__ ] || [ $_ch = $__LBRACE__ ] || [ $_ch = $__RBRACE__ ] ; then
        _get_ch __
        break
      elif [ $_ch = $__BACKSLASH__ ] ; then
        _get_ch __
        if [ $_ch = $__LF__ ] ; then
          _get_ch __
        else
          defstr __str_132 "unexpected character after backslash"
          _syntax_error __ $__str_132
        fi
      else
        defstr __str_131 "invalid token"
        _syntax_error __ $__str_131
      fi
    fi
  done
  _last_tok_line_number=$prev_tok_line_number
  _last_tok_column_number=$prev_tok_column_number
  endlet $1 __t1 prev_tok_column_number prev_tok_line_number
}

: $((c = 0))
_print_string_char() { let c $2
  if [ $c = 7 ] ; then
    printf "\\\\a"
  elif [ $c = 8 ] ; then
    printf "\\\\b"
  elif [ $c = 12 ] ; then
    printf "\\\\f"
  elif [ $c = 10 ] ; then
    printf "\\\\n"
  elif [ $c = 13 ] ; then
    printf "\\\\r"
  elif [ $c = 9 ] ; then
    printf "\\\\t"
  elif [ $c = 11 ] ; then
    printf "\\\\v"
  elif [ $c = $__BACKSLASH__ ] || [ $c = $__QUOTE__ ] || [ $c = $__DQUOTE__ ] ; then
    printf "\\\\"
    printf %b \\0$((c/64))$((c/8%8))$((c%8))
  elif [ $c -lt 32 ] || [ $c -gt 126 ] ; then
    printf "\\\\"
    printf "%d" $((c >> 6))
    printf "%d" $(((c >> 3) & 7))
    printf "%d" $((c & 7))
  else
    printf %b \\0$((c/64))$((c/8%8))$((c%8))
  fi
  endlet $1 c
}

: $((__t1 = string_end = string_start = symbol = 0))
_print_tok_string() { let symbol $2
  let string_start; let string_end; let __t1
  _symbol_buf string_start $symbol
  _symbol_len __t1 $symbol
  string_end=$((string_start + __t1))
  while [ $string_start -lt $string_end ]; do
    _print_string_char __ $((_$string_start))
    : $((string_start += 1))
  done
  endlet $1 __t1 string_end string_start symbol
}

_print_tok_indent_level=0
_print_tok_preceding_nl_count=0
: $((i = 0))
_print_tok_indent() {
  let i
  i=0
  while [ $i -lt $_print_tok_indent_level ]; do
    printf " "
    printf " "
    : $((i += 1))
  done
  endlet $1 i
}

: $((__t1 = val = tok = 0))
_print_tok() { let tok $2; let val $3
  let __t1
  if [ $tok = $__LF__ ] ; then
    if [ $_print_tok_preceding_nl_count -ge 2 ] ; then
      endlet $1 __t1 val tok
      return
    fi
    : $((_print_tok_preceding_nl_count += 1))
    printf "\n"
    endlet $1 __t1 val tok
    return
  elif [ $tok = $__LBRACE__ ] ; then
    _print_tok_indent __
    printf %b \\0$((tok/64))$((tok/8%8))$((tok%8))
    : $((_print_tok_indent_level += 1))
    endlet $1 __t1 val tok
    return
  elif [ $tok = $__RBRACE__ ] ; then
    : $((_print_tok_indent_level -= 1))
    _print_tok_indent __
    printf %b \\0$((tok/64))$((tok/8%8))$((tok%8))
    endlet $1 __t1 val tok
    return
  fi
  if [ $_print_tok_preceding_nl_count != 0 ] ; then
    _print_tok_indent __
    _print_tok_preceding_nl_count=0
  fi
  if [ $tok = $_BREAK_KW ] ; then
    printf "break"
  elif [ $tok = $_CASE_KW ] ; then
    printf "case"
  elif [ $tok = $_CONTINUE_KW ] ; then
    printf "continue"
  elif [ $tok = $_DEFAULT_KW ] ; then
    printf "default"
  elif [ $tok = $_DO_KW ] ; then
    printf "do"
  elif [ $tok = $_ELSE_KW ] ; then
    printf "else"
  elif [ $tok = $_FOR_KW ] ; then
    printf "for"
  elif [ $tok = $_IF_KW ] ; then
    printf "if"
  elif [ $tok = $_RETURN_KW ] ; then
    printf "return"
  elif [ $tok = $_SIZEOF_KW ] ; then
    printf "sizeof"
  elif [ $tok = $_SWITCH_KW ] ; then
    printf "switch"
  elif [ $tok = $_TYPEDEF_KW ] ; then
    printf "typedef"
  elif [ $tok = $_WHILE_KW ] ; then
    printf "while"
  elif [ $tok = $_CHAR_KW ] ; then
    printf "char"
  elif [ $tok = $_DOUBLE_KW ] ; then
    printf "double"
  elif [ $tok = $_ENUM_KW ] ; then
    printf "enum"
  elif [ $tok = $_FLOAT_KW ] ; then
    printf "float"
  elif [ $tok = $_INT_KW ] ; then
    printf "int"
  elif [ $tok = $_LONG_KW ] ; then
    printf "long"
  elif [ $tok = $_SHORT_KW ] ; then
    printf "short"
  elif [ $tok = $_SIGNED_KW ] ; then
    printf "signed"
  elif [ $tok = $_UNSIGNED_KW ] ; then
    printf "unsigned"
  elif [ $tok = $_VOID_KW ] ; then
    printf "void"
  elif [ $tok = $_CONST_KW ] ; then
    printf "const"
  elif [ $tok = $_AUTO_KW ] ; then
    printf "auto"
  elif [ $tok = $_EXTERN_KW ] ; then
    printf "extern"
  elif [ $tok = $_REGISTER_KW ] ; then
    printf "register"
  elif [ $tok = $_STATIC_KW ] ; then
    printf "static"
  elif [ $tok = $_VOLATILE_KW ] ; then
    printf "volatile"
  elif [ $tok = $_INLINE_KW ] ; then
    printf "inline"
  elif [ $tok = $_GOTO_KW ] ; then
    printf "goto"
  elif [ $tok = $_STRUCT_KW ] ; then
    printf "struct"
  elif [ $tok = $_UNION_KW ] ; then
    printf "union"
  elif [ $tok = $_AMP_AMP ] ; then
    printf "&&"
  elif [ $tok = $_AMP_EQ ] ; then
    printf "&="
  elif [ $tok = $_ARROW ] ; then
    printf -- "->"
  elif [ $tok = $_BAR_BAR ] ; then
    printf "||"
  elif [ $tok = $_BAR_EQ ] ; then
    printf "|="
  elif [ $tok = $_CARET_EQ ] ; then
    printf "^="
  elif [ $tok = $_EQ_EQ ] ; then
    printf "=="
  elif [ $tok = $_GT_EQ ] ; then
    printf ">="
  elif [ $tok = $_LSHIFT_EQ ] ; then
    printf "<<="
  elif [ $tok = $_LSHIFT ] ; then
    printf "<<"
  elif [ $tok = $_LT_EQ ] ; then
    printf "<="
  elif [ $tok = $_MINUS_EQ ] ; then
    printf -- "-="
  elif [ $tok = $_MINUS_MINUS ] ; then
    printf -- "--"
  elif [ $tok = $_EXCL_EQ ] ; then
    printf "!="
  elif [ $tok = $_PERCENT_EQ ] ; then
    printf "%%="
  elif [ $tok = $_PLUS_EQ ] ; then
    printf "+="
  elif [ $tok = $_RSHIFT_EQ ] ; then
    printf ">>="
  elif [ $tok = $_RSHIFT ] ; then
    printf ">>"
  elif [ $tok = $_SLASH_EQ ] ; then
    printf "/="
  elif [ $tok = $_STAR_EQ ] ; then
    printf "*="
  elif [ $tok = $_HASH_HASH ] ; then
    printf "##"
  elif [ $tok = $_PLUS_PLUS_PRE ] ; then
    printf "++"
  elif [ $tok = $_MINUS_MINUS_PRE ] ; then
    printf -- "--"
  elif [ $tok = $_PLUS_PLUS_POST ] ; then
    printf "++"
  elif [ $tok = $_MINUS_MINUS_POST ] ; then
    printf -- "--"
  elif [ $tok = $_ELLIPSIS ] ; then
    printf "..."
  elif [ $tok = $_FUN_DECL ] ; then
    printf "fun_decl"
  elif [ $tok = $_CAST ] ; then
    printf "cast"
  elif [ $tok = $_INITIALIZER_LIST ] ; then
    printf "initializer_list"
  elif [ $tok = $_DECL ] ; then
    printf "decl"
  elif [ $tok = $_DECLS ] ; then
    printf "decls"
  elif [ $tok = $_LIST ] ; then
    printf "list"
  elif [ $tok = $_IDENTIFIER ] ; then
    _symbol_buf __t1 $val
    _putstr __ $__t1
  elif [ $tok = $_MACRO ] ; then
    printf "["
    _symbol_buf __t1 $val
    _putstr __ $__t1
    printf "]"
  elif [ $tok = $_INTEGER ] ; then
    printf "%d" $val
  elif [ $tok = $_INTEGER_HEX ] || [ $tok = $_INTEGER_OCT ] ; then
    printf "%d" $val
  elif [ $tok = $_CHARACTER ] ; then
    printf "'"
    _print_string_char __ $val
    printf "'"
  elif [ $tok = $_STRING ] ; then
    printf "\""
    _print_tok_string __ $val
    printf "\""
  elif [ $tok = $_MACRO_ARG ] ; then
    printf "ARG["
    printf "%d" $val
    printf "]"
  else
    printf %b \\0$((tok/64))$((tok/8%8))$((tok%8))
  fi
  if [ $tok != $__LF__ ] ; then
    printf " "
  fi
  endlet $1 __t1 val tok
}

: $((tok = 0))
_print_tok_type() { let tok $2
  if [ $tok = $_BREAK_KW ] ; then
    printf "break"
  elif [ $tok = $_CASE_KW ] ; then
    printf "case"
  elif [ $tok = $_CONTINUE_KW ] ; then
    printf "continue"
  elif [ $tok = $_DEFAULT_KW ] ; then
    printf "default"
  elif [ $tok = $_DO_KW ] ; then
    printf "do"
  elif [ $tok = $_ELSE_KW ] ; then
    printf "else"
  elif [ $tok = $_FOR_KW ] ; then
    printf "for"
  elif [ $tok = $_IF_KW ] ; then
    printf "if"
  elif [ $tok = $_RETURN_KW ] ; then
    printf "return"
  elif [ $tok = $_SIZEOF_KW ] ; then
    printf "sizeof"
  elif [ $tok = $_SWITCH_KW ] ; then
    printf "switch"
  elif [ $tok = $_TYPEDEF_KW ] ; then
    printf "typedef"
  elif [ $tok = $_WHILE_KW ] ; then
    printf "while"
  elif [ $tok = $_CHAR_KW ] ; then
    printf "char"
  elif [ $tok = $_DOUBLE_KW ] ; then
    printf "double"
  elif [ $tok = $_ENUM_KW ] ; then
    printf "enum"
  elif [ $tok = $_FLOAT_KW ] ; then
    printf "float"
  elif [ $tok = $_INT_KW ] ; then
    printf "int"
  elif [ $tok = $_LONG_KW ] ; then
    printf "long"
  elif [ $tok = $_SHORT_KW ] ; then
    printf "short"
  elif [ $tok = $_SIGNED_KW ] ; then
    printf "signed"
  elif [ $tok = $_UNSIGNED_KW ] ; then
    printf "unsigned"
  elif [ $tok = $_VOID_KW ] ; then
    printf "void"
  elif [ $tok = $_CONST_KW ] ; then
    printf "const"
  elif [ $tok = $_AUTO_KW ] ; then
    printf "auto"
  elif [ $tok = $_EXTERN_KW ] ; then
    printf "extern"
  elif [ $tok = $_REGISTER_KW ] ; then
    printf "register"
  elif [ $tok = $_STATIC_KW ] ; then
    printf "static"
  elif [ $tok = $_VOLATILE_KW ] ; then
    printf "volatile"
  elif [ $tok = $_INLINE_KW ] ; then
    printf "inline"
  elif [ $tok = $_GOTO_KW ] ; then
    printf "goto"
  elif [ $tok = $_STRUCT_KW ] ; then
    printf "struct"
  elif [ $tok = $_UNION_KW ] ; then
    printf "union"
  elif [ $tok = $_AMP_AMP ] ; then
    printf "&&"
  elif [ $tok = $_AMP_EQ ] ; then
    printf "&="
  elif [ $tok = $_ARROW ] ; then
    printf -- "->"
  elif [ $tok = $_BAR_BAR ] ; then
    printf "||"
  elif [ $tok = $_BAR_EQ ] ; then
    printf "|="
  elif [ $tok = $_CARET_EQ ] ; then
    printf "^="
  elif [ $tok = $_EQ_EQ ] ; then
    printf "=="
  elif [ $tok = $_GT_EQ ] ; then
    printf ">="
  elif [ $tok = $_LSHIFT_EQ ] ; then
    printf "<<="
  elif [ $tok = $_LSHIFT ] ; then
    printf "<<"
  elif [ $tok = $_LT_EQ ] ; then
    printf "<="
  elif [ $tok = $_MINUS_EQ ] ; then
    printf -- "-="
  elif [ $tok = $_MINUS_MINUS ] ; then
    printf -- "--"
  elif [ $tok = $_EXCL_EQ ] ; then
    printf "!="
  elif [ $tok = $_PERCENT_EQ ] ; then
    printf "%%="
  elif [ $tok = $_PLUS_EQ ] ; then
    printf "+="
  elif [ $tok = $_RSHIFT_EQ ] ; then
    printf ">>="
  elif [ $tok = $_RSHIFT ] ; then
    printf ">>"
  elif [ $tok = $_SLASH_EQ ] ; then
    printf "/="
  elif [ $tok = $_STAR_EQ ] ; then
    printf "*="
  elif [ $tok = $_HASH_HASH ] ; then
    printf "##"
  elif [ $tok = $_PLUS_PLUS_PRE ] ; then
    printf "++"
  elif [ $tok = $_MINUS_MINUS_PRE ] ; then
    printf -- "--"
  elif [ $tok = $_PLUS_PLUS_POST ] ; then
    printf "++"
  elif [ $tok = $_MINUS_MINUS_POST ] ; then
    printf -- "--"
  elif [ $tok = $_ELLIPSIS ] ; then
    printf "..."
  elif [ $tok = $_FUN_DECL ] ; then
    printf "fun_decl"
  elif [ $tok = $_CAST ] ; then
    printf "cast"
  elif [ $tok = $_INITIALIZER_LIST ] ; then
    printf "initializer_list"
  elif [ $tok = $_DECL ] ; then
    printf "decl"
  elif [ $tok = $_DECLS ] ; then
    printf "decls"
  elif [ $tok = $_LIST ] ; then
    printf "list"
  elif [ $tok = $_IDENTIFIER ] ; then
    printf "identifier"
  elif [ $tok = $_INTEGER ] ; then
    printf "integer"
  elif [ $tok = $_CHARACTER ] ; then
    printf "character"
  elif [ $tok = $_STRING ] ; then
    printf "string"
  elif [ $tok = $_MACRO ] ; then
    printf "macro"
  elif [ $tok = $_MACRO_ARG ] ; then
    printf "macro argument"
  elif [ $tok = -1 ] ; then
    printf "end of file"
  elif [ $tok = $__LF__ ] ; then
    printf "newline"
  elif [ $__SPACE__ -lt $tok ] && [ $tok -lt 127 ] ; then
    printf %b \\0$((tok/64))$((tok/8%8))$((tok%8))
  else
    printf "tok="
    printf "%d" $tok
    printf "\n"
    defstr __str_133 "print_tok_type: unknown token"
    _fatal_error __ $__str_133
  fi
  endlet $1 tok
}

: $((expected_tok = 0))
_expect_tok() { let expected_tok $2
  if [ $_tok != $expected_tok ] ; then
    printf "expected tok="
    _print_tok_type __ $expected_tok
    printf "\ncurrent tok="
    _print_tok_type __ $_tok
    printf "\n"
    defstr __str_134 "unexpected token"
    _parse_error __ $__str_134 $_tok
  fi
  _get_tok __
  endlet $1 expected_tok
}

: $((op = type_or_decl = 0))
_get_type_specifier() { let type_or_decl $2
  let op
  while [ 1 != 0 ]; do
    _get_op op $type_or_decl
    if [ $op = $_DECL ] ; then
      _get_child type_or_decl $type_or_decl 1
    elif [ $op = $__LBRACK__ ] ; then
      _get_child type_or_decl $type_or_decl 0
    elif [ $op = $__STAR__ ] ; then
      _get_child type_or_decl $type_or_decl 1
    else
      : $(($1 = type_or_decl))
      break
    fi
  done
  endlet $1 op type_or_decl
}

: $((is_const = parent_type = 0))
_pointer_type() { let parent_type $2; let is_const $3
  _new_ast2 $1 $__STAR__ $((is_const ? (1 << (_CONST_KW - _CONST_KW)) : 0)) $parent_type
  endlet $1 is_const parent_type
}

: $((func_type = 0))
_make_variadic_func() { let func_type $2
  _set_child __ $func_type 2 1
  : $(($1 = func_type))
  endlet $1 func_type
}

: $((__t1 = op = type = 0))
_is_constant_type() { let type $2
  let op; let __t1
  _get_op op $type
  if [ $op = $__LBRACK__ ] ; then
    : $(($1 = 0))
  elif [ $op = $__LPAREN__ ] ; then
    : $(($1 = 0))
  elif [ $op = $__STAR__ ] ; then
    _get_child __t1 $type 0
    : $(($1 = __t1 & (1 << (_CONST_KW - _CONST_KW))))
  else
    _get_child __t1 $type 0
    : $(($1 = __t1 & (1 << (_CONST_KW - _CONST_KW))))
  fi
  endlet $1 __t1 op type
}

: $((tok = 0))
_is_type_starter() { let tok $2
  : $(($1 = (tok == _INT_KW) || (tok == _CHAR_KW) || (tok == _SHORT_KW) || (tok == _LONG_KW) || (tok == _VOID_KW) || (tok == _FLOAT_KW) || (tok == _DOUBLE_KW) || (tok == _SIGNED_KW) || (tok == _UNSIGNED_KW) || (tok == _TYPE) || (tok == _CONST_KW) || (tok == _ENUM_KW) || (tok == _STRUCT_KW) || (tok == _UNION_KW) || (tok == _AUTO_KW) || (tok == _EXTERN_KW) || (tok == _INLINE_KW) || (tok == _REGISTER_KW) || (tok == _STATIC_KW) || (tok == _TYPEDEF_KW) || (tok == _VOLATILE_KW)))
  endlet $1 tok
}

: $((__t1 = op = last_literal_type = next_value = value = rest = result = ident = name = 0))
_parse_enum() {
  let name; let ident; let result; let rest; let value; let next_value; let last_literal_type; let op; let __t1
  result=0
  value=0
  next_value=0
  last_literal_type=$_INTEGER
  _expect_tok __ $_ENUM_KW
  if [ $_tok = $_IDENTIFIER ] || [ $_tok = $_TYPE ] ; then
    _new_ast0 name $_IDENTIFIER $_val
    _get_tok __
  else
    name=0
  fi
  if [ $_tok = $__LBRACE__ ] ; then
    _get_tok __
    while [ $_tok != $__RBRACE__ ]; do
      if [ $_tok != $_IDENTIFIER ] ; then
        defstr __str_135 "identifier expected"
        _parse_error __ $__str_135 $_tok
      fi
      _new_ast0 ident $_IDENTIFIER $_val
      _get_tok __
      if [ $_tok = $__EQ__ ] ; then
        _get_tok __
        _parse_constant_expression value
        if [ $value = 0 ] ; then
          defstr __str_136 "Enum value must be a constant expression"
          _parse_error __ $__str_136 $_tok
        fi
        _get_op op $value
        if [ $op != $_INTEGER ] && [ $op != $_INTEGER_HEX ] && [ $op != $_INTEGER_OCT ] ; then
          _compute_constant __t1 $value 0
          _new_ast0 value $last_literal_type $((-__t1))
        fi
        _get_val __t1 $value
        next_value=$((__t1 - 1))
        _get_op last_literal_type $value
      else
        _new_ast0 value $last_literal_type $next_value
        : $((next_value -= 1))
      fi
      if [ $result = 0 ] ; then
        _new_ast2 __t1 $__EQ__ $ident $value
        _cons result $__t1 0
        rest=$result
      else
        _new_ast2 __t1 $__EQ__ $ident $value
        _cons __t1 $__t1 0
        _set_child __ $rest 1 $__t1
        _get_child rest $rest 1
      fi
      if [ $_tok = $__COMMA__ ] ; then
        _get_tok __
      else
        break
      fi
    done
    _expect_tok __ $__RBRACE__
  fi
  _new_ast3 $1 $_ENUM_KW 0 $name $result
  endlet $1 __t1 op last_literal_type next_value value rest result ident name
}

: $((__t1 = ends_in_flex_array = rest = result = decl = type_specifier = name = struct_or_union_tok = 0))
_parse_struct_or_union() { let struct_or_union_tok $2
  let name; let type_specifier; let decl; let result; let rest; let ends_in_flex_array; let __t1
  result=0
  ends_in_flex_array=0
  _expect_tok __ $struct_or_union_tok
  if [ $_tok = $_IDENTIFIER ] || [ $_tok = $_TYPE ] ; then
    _new_ast0 name $_IDENTIFIER $_val
    _get_tok __
  else
    name=0
  fi
  if [ $_tok = $__LBRACE__ ] ; then
    _get_tok __
    while [ $_tok != $__RBRACE__ ]; do
      if _is_type_starter __t1 $_tok; [ $((!__t1)) != 0 ] ; then
        defstr __str_137 "type expected in struct declaration"
        _parse_error __ $__str_137 $_tok
      fi
      if [ $ends_in_flex_array != 0 ] ; then
        defstr __str_138 "flexible array member must be last"
        _parse_error __ $__str_138 $_tok
      fi
      _parse_declaration_specifiers type_specifier 0
      if [ $_tok = $__SEMICOLON__ ] ; then
        if { _get_op __t1 $type_specifier; [ $__t1 != $_ENUM_KW ]; } && { _get_op __t1 $type_specifier; [ $__t1 != $_STRUCT_KW ]; } && { _get_op __t1 $type_specifier; [ $__t1 != $_UNION_KW ]; } ; then
          defstr __str_139 "Anonymous struct/union member must be a struct or union type"
          _parse_error __ $__str_139 $_tok
        fi
        _new_ast3 decl $_DECL 0 $type_specifier 0
        if [ $result = 0 ] ; then
          _cons result $decl 0
          : $((rest = result))
        else
          _cons __t1 $decl 0
          _set_child __ $rest 1 $__t1
          _get_child rest $rest 1
        fi
      else
        while [ 1 != 0 ]; do
          _parse_declarator decl 0 $type_specifier
          if [ $result = 0 ] ; then
            _cons result $decl 0
            : $((rest = result))
          else
            _cons __t1 $decl 0
            _set_child __ $rest 1 $__t1
            _get_child rest $rest 1
          fi
          if _get_child __t1 $decl 1; [ $__t1 = $_VOID_KW ] ; then
            defstr __str_140 "member with void type not allowed in struct/union"
            _parse_error __ $__str_140 $_tok
          fi
          if { _get_child __t1 $decl 1; [ $__t1 = $__LBRACK__ ]; } && { _get_child __t1 $decl 1; _get_child __t1 $__t1 1; [ $__t1 = 0 ]; } ; then
            ends_in_flex_array=1
            break
          fi
          if [ $_tok = $__COMMA__ ] ; then
            _get_tok __
          else
            break
          fi
        done
      fi
      _expect_tok __ $__SEMICOLON__
    done
    _expect_tok __ $__RBRACE__
  fi
  _new_ast3 $1 $struct_or_union_tok 0 $name $result
  endlet $1 __t1 ends_in_flex_array rest result decl type_specifier name struct_or_union_tok
}

: $((type_specifier = 0))
_parse_type_specifier() {
  let type_specifier
  type_specifier=0
  if [ $_tok = $_CHAR_KW ] || [ $_tok = $_INT_KW ] || [ $_tok = $_VOID_KW ] ; then
    _new_ast0 type_specifier $_tok 0
    _get_tok __
    : $(($1 = type_specifier))
  elif [ $_tok = $_SHORT_KW ] ; then
    _get_tok __
    if [ $_tok = $_INT_KW ] ; then
      _get_tok __
    fi
    _new_ast0 $1 $_SHORT_KW 0
  elif [ $_tok = $_SIGNED_KW ] ; then
    _get_tok __
    _parse_type_specifier type_specifier
    if [ $type_specifier = 0 ] ; then
      _new_ast0 type_specifier $_INT_KW 0
    fi
    : $(($1 = type_specifier))
  elif [ $_tok = $_LONG_KW ] ; then
    _get_tok __
    if [ $_tok = $_LONG_KW ] ; then
      _get_tok __
      if [ $_tok = $_INT_KW ] ; then
        _get_tok __
      fi
      _new_ast0 $1 $_LONG_KW 0
    elif [ $_tok = $_INT_KW ] ; then
      _get_tok __
      _new_ast0 $1 $_INT_KW 0
    else
      _new_ast0 $1 $_INT_KW 0
    fi
  else
    : $(($1 = 0))
  fi
  endlet $1 type_specifier
}

_glo_specifier_storage_class=0
: $((__t1 = specifier_storage_class = loop = type_qualifier = type_specifier = allow_typedef = 0))
_parse_declaration_specifiers() { let allow_typedef $2
  let type_specifier; let type_qualifier; let loop; let specifier_storage_class; let __t1
  type_specifier=0
  type_qualifier=0
  loop=1
  specifier_storage_class=0
  while [ $loop != 0 ]; do
    if [ $_tok = $_CHAR_KW ] || [ $_tok = $_INT_KW ] || [ $_tok = $_VOID_KW ] || [ $_tok = $_SHORT_KW ] || [ $_tok = $_SIGNED_KW ] || [ $_tok = $_UNSIGNED_KW ] || [ $_tok = $_LONG_KW ] || [ $_tok = $_FLOAT_KW ] || [ $_tok = $_DOUBLE_KW ] ; then
      if [ $type_specifier != 0 ] ; then
        defstr __str_141 "Unexpected C type specifier"
        _parse_error __ $__str_141 $_tok
      fi
      _parse_type_specifier type_specifier
      if [ $type_specifier = 0 ] ; then
        defstr __str_142 "Failed to parse type specifier"
        _parse_error __ $__str_142 $_tok
      fi
    elif [ $_tok = $_AUTO_KW ] || [ $_tok = $_REGISTER_KW ] || [ $_tok = $_STATIC_KW ] || [ $_tok = $_EXTERN_KW ] || [ $_tok = $_TYPEDEF_KW ] ; then
      if [ $specifier_storage_class != 0 ] ; then
        defstr __str_143 "Multiple storage classes not supported"
        _parse_error __ $__str_143 $_tok
      fi
      if [ $_tok = $_TYPEDEF_KW ] && [ $((! allow_typedef)) != 0 ] ; then
        defstr __str_144 "Unexpected typedef"
        _parse_error __ $__str_144 $_tok
      fi
      specifier_storage_class=$_tok
      _get_tok __
    elif [ $_tok = $_INLINE_KW ] ; then
      _get_tok __
    elif [ $_tok = $_CONST_KW ] || [ $_tok = $_VOLATILE_KW ] ; then
      type_qualifier=$((type_qualifier | (1 << (_tok - _CONST_KW))))
      _get_tok __
    elif [ $_tok = $_STRUCT_KW ] || [ $_tok = $_UNION_KW ] ; then
      if [ $type_specifier != 0 ] ; then
        defstr __str_145 "Multiple types not supported"
        _parse_error __ $__str_145 $_tok
      fi
      _parse_struct_or_union type_specifier $_tok
    elif [ $_tok = $_ENUM_KW ] ; then
      if [ $type_specifier != 0 ] ; then
        defstr __str_145 "Multiple types not supported"
        _parse_error __ $__str_145 $_tok
      fi
      _parse_enum type_specifier
    elif [ $_tok = $_TYPE ] ; then
      if [ $type_specifier != 0 ] ; then
        defstr __str_145 "Multiple types not supported"
        _parse_error __ $__str_145 $_tok
      fi
      _symbol_tag type_specifier $_val
      _get_tok __
    else
      loop=0
    fi
  done
  if [ $type_specifier = 0 ] ; then
    defstr __str_146 "Type expected"
    _parse_error __ $__str_146 $_tok
  fi
  if [ $type_qualifier != 0 ] ; then
    if { _get_op __t1 $type_specifier; [ $__t1 = $__LBRACK__ ]; } || { _get_op __t1 $type_specifier; [ $__t1 = $__LPAREN__ ]; } ; then
      defstr __str_147 "Type qualifiers not allowed on typedef'ed array or function type"
      _parse_error __ $__str_147 $_tok
    fi
    _get_child __t1 $type_specifier 0
    _set_child __ $type_specifier 0 $((__t1 | type_qualifier))
  fi
  _glo_specifier_storage_class=$specifier_storage_class
  : $(($1 = type_specifier))
  endlet $1 __t1 specifier_storage_class loop type_qualifier type_specifier allow_typedef
}

_parse_param_list_is_variadic=0
: $((__t2 = __t1 = decl = rest = result = 0))
_parse_param_list() {
  let result; let rest; let decl; let __t1; let __t2
  result=0
  _parse_param_list_is_variadic=0
  _expect_tok __ $__LPAREN__
  while [ $_tok != $__RPAREN__ ] && [ $_tok != -1 ]; do
    if _is_type_starter __t1 $_tok; [ $__t1 != 0 ] ; then
      _parse_declaration_specifiers __t1 0
      _parse_declarator decl 1 $__t1
      if _get_child __t1 $decl 1; _get_op __t1 $__t1; [ $__t1 = $_VOID_KW ] ; then
        if [ $_tok != $__RPAREN__ ] || [ $result != 0 ] ; then
          defstr __str_148 "void must be the only parameter"
          _parse_error __ $__str_148 $_tok
        fi
        break
      fi
    elif [ $_tok = $_IDENTIFIER ] ; then
      _new_ast0 __t1 $_IDENTIFIER $_val
      _new_ast0 __t2 $_INT_KW 0
      _new_ast3 decl $_DECL $__t1 $__t2 0
      _get_tok __
    elif [ $_tok = $_ELLIPSIS ] ; then
      if [ $result = 0 ] ; then
        defstr __str_149 "Function must have a named parameter before ellipsis parameter"
        _parse_error __ $__str_149 $_tok
      fi
      _get_tok __
      _parse_param_list_is_variadic=1
      break
    else
      defstr __str_150 "Parameter declaration expected"
      _parse_error __ $__str_150 $_tok
    fi
    if [ $_tok = $__COMMA__ ] ; then
      _get_tok __
    fi
    if [ $result = 0 ] ; then
      _cons result $decl 0
      : $((rest = result))
    else
      _cons __t1 $decl 0
      _set_child __ $rest 1 $__t1
      _get_child rest $rest 1
    fi
  done
  _expect_tok __ $__RPAREN__
  : $(($1 = result))
  endlet $1 __t2 __t1 decl rest result
}

: $((op = type = 0))
_get_inner_type() { let type $2
  let op
  _get_op op $type
  if [ $op = $_DECL ] || [ $op = $__STAR__ ] ; then
    _get_child $1 $type 1
  elif [ $op = $__LBRACK__ ] || [ $op = $__LPAREN__ ] ; then
    _get_child $1 $type 0
  else
    defstr __str_151 "Invalid type"
    _fatal_error __ $__str_151
    : $(($1 = 0))
  fi
  endlet $1 op type
}

: $((op = inner_type = parent_type = 0))
_update_inner_type() { let parent_type $2; let inner_type $3
  let op
  _get_op op $parent_type
  if [ $op = $_DECL ] || [ $op = $__STAR__ ] ; then
    _set_child __ $parent_type 1 $inner_type
  elif [ $op = $__LBRACK__ ] || [ $op = $__LPAREN__ ] ; then
    _set_child __ $parent_type 0 $inner_type
  fi
  endlet $1 op inner_type parent_type
}

_parse_declarator_parent_type_parent=0
: $((__t2 = __t1 = parent_type_parent = arr_size_expr = decl = result = first_tok = parent_type = abstract_decl = 0))
_parse_declarator() { let abstract_decl $2; let parent_type $3
  let first_tok; let result; let decl; let arr_size_expr; let parent_type_parent; let __t1; let __t2
  first_tok=$_tok
  result=0
  if [ $_tok = $_IDENTIFIER ] ; then
    _new_ast0 __t1 $_IDENTIFIER $_val
    _new_ast3 result $_DECL $__t1 $parent_type 0
    parent_type_parent=$result
    _get_tok __
  elif [ $_tok = $__STAR__ ] ; then
    _get_tok __
    _pointer_type parent_type_parent $parent_type $((_tok == _CONST_KW))
    if [ $_tok = $_CONST_KW ] ; then
      _get_tok __
    fi
    _parse_declarator result $abstract_decl $parent_type_parent
  elif [ $_tok = $__LPAREN__ ] ; then
    _get_tok __
    _parse_declarator result $abstract_decl $parent_type
    parent_type_parent=$_parse_declarator_parent_type_parent
    _expect_tok __ $__RPAREN__
  else
    if [ $abstract_decl != 0 ] ; then
      _new_ast3 result $_DECL 0 $parent_type 0
      parent_type_parent=$result
    else
      defstr __str_152 "Invalid declarator, expected an identifier but declarator doesn't have one"
      _parse_error __ $__str_152 $_tok
    fi
  fi
  decl=$result
  _get_child result $decl 1
  while [ $first_tok != $__STAR__ ]; do
    if [ $_tok = $__LBRACK__ ] ; then
      if _get_op __t1 $result; [ $__t1 = $_VOID_KW ] ; then
        defstr __str_153 "void array not allowed"
        _parse_error __ $__str_153 $_tok
      fi
      _get_tok __
      if [ $_tok = $__RBRACK__ ] ; then
        _val=0
      else
        _parse_constant_expression arr_size_expr
        if [ $arr_size_expr = 0 ] ; then
          defstr __str_154 "Array size must be an integer constant"
          _parse_error __ $__str_154 $_tok
        fi
        _compute_constant _val $arr_size_expr 0
      fi
      _get_inner_type __t1 $parent_type_parent
      _new_ast2 result $__LBRACK__ $__t1 $_val
      _update_inner_type __ $parent_type_parent $result
      parent_type_parent=$result
      _expect_tok __ $__RBRACK__
    elif [ $_tok = $__LPAREN__ ] ; then
      _get_inner_type __t1 $parent_type_parent
      _parse_param_list __t2
      _new_ast3 result $__LPAREN__ $__t1 $__t2 0
      if [ $_parse_param_list_is_variadic != 0 ] ; then
        _make_variadic_func result $result
      fi
      _update_inner_type __ $parent_type_parent $result
      parent_type_parent=$result
    else
      break
    fi
  done
  _parse_declarator_parent_type_parent=$parent_type_parent
  : $(($1 = decl))
  endlet $1 __t2 __t1 parent_type_parent arr_size_expr decl result first_tok parent_type abstract_decl
}

: $((__t1 = rest = result = 0))
_parse_initializer_list() {
  let result; let rest; let __t1
  result=0
  rest=0
  _expect_tok __ $__LBRACE__
  while [ $_tok != $__RBRACE__ ] && [ $_tok != -1 ]; do
    if [ $_tok = $__LBRACE__ ] ; then
      defstr __str_155 "nested initializer lists not supported"
      _syntax_error __ $__str_155
    fi
    if [ $result = 0 ] ; then
      _parse_initializer __t1
      _cons result $__t1 0
      : $((rest = result))
    else
      _parse_initializer __t1
      _cons __t1 $__t1 0
      _set_child __ $rest 1 $__t1
      _get_child rest $rest 1
    fi
    if [ $_tok = $__COMMA__ ] ; then
      _get_tok __
    else
      break
    fi
  done
  _expect_tok __ $__RBRACE__
  _new_ast1 $1 $_INITIALIZER_LIST $result
  endlet $1 __t1 rest result
}

_parse_initializer() {
  if [ $_tok = $__LBRACE__ ] ; then
    _parse_initializer_list $1
  else
    _parse_assignment_expression $1
  fi
}

: $((__t1 = declarator = type_specifier = is_for_typedef = 0))
_parse_declarator_and_initializer() { let is_for_typedef $2; let type_specifier $3
  let declarator; let __t1
  _parse_declarator declarator 0 $type_specifier
  if [ $is_for_typedef = 0 ] ; then
    if [ $_tok = $__EQ__ ] ; then
      _get_tok __
      _parse_initializer __t1
      _set_child __ $declarator 2 $__t1
    fi
  fi
  : $(($1 = declarator))
  endlet $1 __t1 declarator type_specifier is_for_typedef
}

: $((__t1 = rest = declarators = first_declarator = type_specifier = is_for_typedef = 0))
_parse_declarators() { let is_for_typedef $2; let type_specifier $3; let first_declarator $4
  let declarators; let rest; let __t1
  _cons declarators $first_declarator 0
  rest=$declarators
  while [ $_tok != $__SEMICOLON__ ]; do
    if [ $_tok = $__COMMA__ ] ; then
      _get_tok __
      _parse_declarator_and_initializer __t1 $is_for_typedef $type_specifier
      _cons __t1 $__t1 0
      _set_child __ $rest 1 $__t1
      _get_child rest $rest 1
    else
      defstr __str_156 "';' or ',' expected"
      _parse_error __ $__str_156 $_tok
    fi
  done
  : $(($1 = declarators))
  endlet $1 __t1 rest declarators first_declarator type_specifier is_for_typedef
}

: $((__t1 = decl_type = decl_ident = declarator = 0))
_add_typedef() { let declarator $2
  let decl_ident; let decl_type; let __t1
  _get_child __t1 $declarator 0
  _get_val decl_ident $__t1
  _get_child decl_type $declarator 1
  if { _get_op __t1 $decl_type; [ $__t1 = $_STRUCT_KW ]; } || { _get_op __t1 $decl_type; [ $__t1 = $_UNION_KW ]; } || { _get_op __t1 $decl_type; [ $__t1 = $_ENUM_KW ]; } ; then
    if { _get_child __t1 $decl_type 1; [ $__t1 != 0 ]; } && { _get_child __t1 $decl_type 1; _get_val __t1 $__t1; [ $__t1 != $decl_ident ]; } ; then
      defstr __str_157 "typedef name must match struct/union/enum name"
      _syntax_error __ $__str_157
    fi
    _new_ast0 __t1 $_IDENTIFIER $decl_ident
    _set_child __ $decl_type 1 $__t1
  fi
  _set_symbol_type __ $decl_ident $_TYPE
  _set_symbol_tag __ $decl_ident $decl_type
  endlet $1 __t1 decl_type decl_ident declarator
}

: $((__t1 = params = fun_type = declarator = 0))
_parse_fun_def() { let declarator $2
  let fun_type; let params; let __t1
  _get_child fun_type $declarator 1
  _get_child params $fun_type 1
  while [ $params != 0 ]; do
    if _get_child __t1 $params 0; _get_child __t1 $__t1 0; [ $__t1 = 0 ] ; then
      defstr __str_158 "Parameter name expected"
      _parse_error __ $__str_158 $_tok
    fi
    _get_child params $params 1
  done
  if _get_child __t1 $declarator 2; [ $__t1 != 0 ] ; then
    defstr __str_159 "Initializer not allowed in function definition"
    _parse_error __ $__str_159 $_tok
  fi
  _parse_compound_statement __t1
  _new_ast2 $1 $_FUN_DECL $declarator $__t1
  endlet $1 __t1 params fun_type declarator
}

: $((__t1 = type_specifier = declarators = declarator = result = local = 0))
_parse_declaration() { let local $2
  let result; let declarator; let declarators; let type_specifier; let __t1
  _parse_declaration_specifiers type_specifier 1
  if [ $_tok = $__SEMICOLON__ ] ; then
    if { _get_op __t1 $type_specifier; [ $__t1 != $_ENUM_KW ]; } && { _get_op __t1 $type_specifier; [ $__t1 != $_STRUCT_KW ]; } && { _get_op __t1 $type_specifier; [ $__t1 != $_UNION_KW ]; } ; then
      defstr __str_160 "enum/struct/union declaration expected"
      _parse_error __ $__str_160 $_tok
    fi
    if [ $_glo_specifier_storage_class = $_TYPEDEF_KW ] ; then
      _new_ast3 __t1 $_DECL 0 $type_specifier 0
      _add_typedef __ $__t1
    fi
    result=$type_specifier
  elif [ $_glo_specifier_storage_class = $_TYPEDEF_KW ] ; then
    _parse_declarator_and_initializer declarator 1 $type_specifier
    _parse_declarators declarators 1 $type_specifier $declarator
    type_specifier=$declarators
    while [ $declarators != 0 ]; do
      _get_child __t1 $declarators 0
      _add_typedef __ $__t1
      _get_child declarators $declarators 1
    done
    _new_ast1 result $_TYPEDEF_KW $type_specifier
  else
    _parse_declarator_and_initializer declarator 0 $type_specifier
    if { _get_child __t1 $declarator 1; _get_op __t1 $__t1; [ $__t1 = $__LPAREN__ ]; } && [ $_tok = $__LBRACE__ ] ; then
      if [ $local != 0 ] ; then
        defstr __str_161 "Function definition not allowed in local scope"
        _parse_error __ $__str_161 $_tok
      fi
      _parse_fun_def $1 $declarator
      endlet $1 __t1 type_specifier declarators declarator result local
      return
    fi
    _parse_declarators declarators 0 $type_specifier $declarator
    _new_ast2 result $_DECLS $declarators $_glo_specifier_storage_class
  fi
  _expect_tok __ $__SEMICOLON__
  : $(($1 = result))
  endlet $1 __t1 type_specifier declarators declarator result local
}

: $((result = first_par_already_consumed = 0))
_parse_parenthesized_expression() { let first_par_already_consumed $2
  let result
  if [ $((! first_par_already_consumed)) != 0 ] ; then
    _expect_tok __ $__LPAREN__
  fi
  _parse_comma_expression result
  _expect_tok __ $__RPAREN__
  : $(($1 = result))
  endlet $1 result first_par_already_consumed
}

: $((__t1 = rest = result = 0))
_parse_primary_expression() {
  let result; let rest; let __t1
  result=0
  if [ $_tok = $_IDENTIFIER ] || [ $_tok = $_CHARACTER ] || [ $_tok = $_INTEGER ] || [ $_tok = $_INTEGER_HEX ] || [ $_tok = $_INTEGER_OCT ] ; then
    _new_ast0 result $_tok $_val
    _get_tok __
  elif [ $_tok = $_STRING ] ; then
    _new_ast0 result $_STRING $_val
    _get_tok __
    if [ $_tok = $_STRING ] ; then
      _get_val __t1 $result
      _cons result $__t1 0
      rest=$result
      while [ $_tok = $_STRING ]; do
        _cons __t1 $_val 0
        _set_cdr __ $rest $__t1
        _cdr rest $rest
        _get_tok __
      done
      _begin_symbol __
      while [ $result != 0 ]; do
        _car __t1 $result
        _accum_symbol_string __ $__t1
        _cdr result $result
      done
      _end_symbol __t1
      _new_ast0 result $_STRING $__t1
    fi
  elif [ $_tok = $__LPAREN__ ] ; then
    _parse_parenthesized_expression result 0
  else
    defstr __str_162 "identifier, literal, or '(' expected"
    _parse_error __ $__str_162 $_tok
  fi
  : $(($1 = result))
  endlet $1 __t1 rest result
}

: $((__t1 = child = result = 0))
_parse_postfix_expression() { let result $2
  let child; let __t1
  if [ $result = 0 ] ; then
    _parse_primary_expression result
  fi
  while [ 1 != 0 ]; do
    if [ $_tok = $__LBRACK__ ] ; then
      _get_tok __
      _parse_comma_expression child
      _new_ast2 result $__LBRACK__ $result $child
      _expect_tok __ $__RBRACK__
    elif [ $_tok = $__LPAREN__ ] ; then
      _get_tok __
      if [ $_tok = $__RPAREN__ ] ; then
        child=0
      else
        _parse_call_params child
      fi
      _new_ast2 result $__LPAREN__ $result $child
      _expect_tok __ $__RPAREN__
    elif [ $_tok = $__PERIOD__ ] ; then
      _get_tok __
      if [ $_tok != $_IDENTIFIER ] ; then
        defstr __str_135 "identifier expected"
        _parse_error __ $__str_135 $_tok
      fi
      _new_ast0 __t1 $_IDENTIFIER $_val
      _new_ast2 result $__PERIOD__ $result $__t1
      _get_tok __
    elif [ $_tok = $_ARROW ] ; then
      _get_tok __
      if [ $_tok != $_IDENTIFIER ] ; then
        defstr __str_135 "identifier expected"
        _parse_error __ $__str_135 $_tok
      fi
      _new_ast0 __t1 $_IDENTIFIER $_val
      _new_ast2 result $_ARROW $result $__t1
      _get_tok __
    elif [ $_tok = $_PLUS_PLUS ] ; then
      _get_tok __
      _new_ast1 result $_PLUS_PLUS_POST $result
    elif [ $_tok = $_MINUS_MINUS ] ; then
      _get_tok __
      _new_ast1 result $_MINUS_MINUS_POST $result
    else
      break
    fi
  done
  : $(($1 = result))
  endlet $1 __t1 child result
}

: $((__t1 = op = result = 0))
_parse_unary_expression() {
  let result; let op; let __t1
  if [ $_tok = $_PLUS_PLUS ] ; then
    _get_tok __
    _parse_unary_expression result
    _new_ast1 result $_PLUS_PLUS_PRE $result
  elif [ $_tok = $_MINUS_MINUS ] ; then
    _get_tok __
    _parse_unary_expression result
    _new_ast1 result $_MINUS_MINUS_PRE $result
  elif [ $_tok = $__AMP__ ] || [ $_tok = $__STAR__ ] || [ $_tok = $__PLUS__ ] || [ $_tok = $__MINUS__ ] || [ $_tok = $__TILDE__ ] || [ $_tok = $__EXCL__ ] ; then
    op=$_tok
    _get_tok __
    _parse_cast_expression result
    _new_ast1 result $op $result
  elif [ $_skip_newlines != 0 ] && [ $_tok = $_SIZEOF_KW ] ; then
    _get_tok __
    if [ $_tok = $__LPAREN__ ] ; then
      _get_tok __
      if _is_type_starter __t1 $_tok; [ $__t1 != 0 ] ; then
        _parse_declaration_specifiers __t1 0
        _parse_declarator result 1 $__t1
        _expect_tok __ $__RPAREN__
      else
        _parse_parenthesized_expression __t1 1
        _parse_postfix_expression result $__t1
      fi
    else
      _parse_unary_expression result
    fi
    _new_ast1 result $_SIZEOF_KW $result
  elif [ $((! _skip_newlines)) != 0 ] && [ $_tok = $_IDENTIFIER ] && [ $_val = $_DEFINED_ID ] ; then
    _get_tok_macro __ 1
    if [ $_tok = $__LPAREN__ ] ; then
      _get_tok_macro __ 1
      _new_ast0 __t1 $_IDENTIFIER $_DEFINED_ID
      _new_ast2 result $__LPAREN__ $__t1 $_tok
      _get_tok_macro __ 1
      _expect_tok __ $__RPAREN__
    elif [ $_tok = $_IDENTIFIER ] || [ $_tok = $_MACRO ] ; then
      _new_ast0 __t1 $_IDENTIFIER $_DEFINED_ID
      _new_ast2 result $__LPAREN__ $__t1 $_tok
      _get_tok_macro __ 1
    else
      defstr __str_163 "identifier or '(' expected"
      _parse_error __ $__str_163 $_tok
      : $(($1 = 0))
      endlet $1 __t1 op result
      return
    fi
  else
    _parse_postfix_expression result 0
  fi
  : $(($1 = result))
  endlet $1 __t1 op result
}

: $((__t1 = type = 0))
_parse_cast_expression() {
  let type; let __t1
  if [ $_tok = $__LPAREN__ ] ; then
    _get_tok __
    if _is_type_starter __t1 $_tok; [ $__t1 != 0 ] ; then
      _parse_declaration_specifiers __t1 0
      _parse_declarator type 1 $__t1
      _expect_tok __ $__RPAREN__
      _parse_cast_expression __t1
      _new_ast2 $1 $_CAST $type $__t1
    else
      _parse_parenthesized_expression __t1 1
      _parse_postfix_expression $1 $__t1
    fi
  else
    _parse_unary_expression $1
  fi
  endlet $1 __t1 type
}

: $((op = 0))
_binop_prec() { let op $2
  if [ $op = $__COMMA__ ] ; then
    : $(($1 = 1))
  elif [ $op = $__EQ__ ] || [ $op = $_PLUS_EQ ] || [ $op = $_MINUS_EQ ] || [ $op = $_STAR_EQ ] || [ $op = $_SLASH_EQ ] || [ $op = $_PERCENT_EQ ] || [ $op = $_LSHIFT_EQ ] || [ $op = $_RSHIFT_EQ ] || [ $op = $_AMP_EQ ] || [ $op = $_CARET_EQ ] || [ $op = $_BAR_EQ ] ; then
    : $(($1 = 2))
  elif [ $op = $__QUESTION__ ] ; then
    : $(($1 = 3))
  elif [ $op = $_BAR_BAR ] ; then
    : $(($1 = 4))
  elif [ $op = $_AMP_AMP ] ; then
    : $(($1 = 5))
  elif [ $op = $__BAR__ ] ; then
    : $(($1 = 6))
  elif [ $op = $__CARET__ ] ; then
    : $(($1 = 7))
  elif [ $op = $__AMP__ ] ; then
    : $(($1 = 8))
  elif [ $op = $_EQ_EQ ] || [ $op = $_EXCL_EQ ] ; then
    : $(($1 = 9))
  elif [ $op = $__LT__ ] || [ $op = $__GT__ ] || [ $op = $_LT_EQ ] || [ $op = $_GT_EQ ] ; then
    : $(($1 = 10))
  elif [ $op = $_LSHIFT ] || [ $op = $_RSHIFT ] ; then
    : $(($1 = 11))
  elif [ $op = $__PLUS__ ] || [ $op = $__MINUS__ ] ; then
    : $(($1 = 12))
  elif [ $op = $__STAR__ ] || [ $op = $__SLASH__ ] || [ $op = $__PERCENT__ ] ; then
    : $(($1 = 13))
  else
    : $(($1 = 0))
  fi
  endlet $1 op
}

: $((__t1 = prec = op = mid = left = min_prec = 0))
_parse_binary_expression() { let min_prec $2
  let left; let mid; let op; let prec; let __t1
  _parse_cast_expression left
  while _binop_prec prec $_tok; [ $prec -ge $min_prec ]; do
    op=$_tok
    _get_tok __
    if [ $op = $__QUESTION__ ] ; then
      _parse_comma_expression mid
      _expect_tok __ $__COLON__
      _parse_binary_expression __t1 $prec
      _new_ast3 left $__QUESTION__ $left $mid $__t1
    elif [ $prec = 2 ] ; then
      _parse_binary_expression __t1 $prec
      _new_ast2 left $op $left $__t1
    else
      _parse_binary_expression __t1 $((prec + 1))
      _new_ast2 left $op $left $__t1
    fi
  done
  : $(($1 = left))
  endlet $1 __t1 prec op mid left min_prec
}

_parse_assignment_expression() {
  _parse_binary_expression $1 2
}

_parse_comma_expression() {
  _parse_binary_expression $1 1
}

: $((__t1 = result = 0))
_parse_call_params() {
  let result; let __t1
  _parse_assignment_expression result
  _cons result $result 0
  if [ $_tok = $__COMMA__ ] ; then
    _get_tok __
    _parse_call_params __t1
    _set_child __ $result 1 $__t1
  fi
  : $(($1 = result))
  endlet $1 __t1 result
}

_parse_comma_expression_opt() {
  if [ $_tok = $__COLON__ ] || [ $_tok = $__SEMICOLON__ ] || [ $_tok = $__RPAREN__ ] ; then
    : $(($1 = 0))
  else
    _parse_comma_expression $1
  fi
}

_parse_constant_expression() {
  _parse_binary_expression $1 3
}

: $((__t1 = start_tok = child3 = child2 = child1 = result = 0))
_parse_statement() {
  let result; let child1; let child2; let child3; let start_tok; let __t1
  if [ $_tok = $_IF_KW ] ; then
    _get_tok __
    _parse_parenthesized_expression result 0
    _parse_statement child1
    if [ $_tok = $_ELSE_KW ] ; then
      _get_tok __
      _parse_statement child2
    else
      child2=0
    fi
    _new_ast3 result $_IF_KW $result $child1 $child2
  elif [ $_tok = $_SWITCH_KW ] ; then
    _get_tok __
    _parse_parenthesized_expression result 0
    _parse_statement child1
    _new_ast2 result $_SWITCH_KW $result $child1
  elif [ $_tok = $_CASE_KW ] ; then
    _get_tok __
    _parse_constant_expression result
    _expect_tok __ $__COLON__
    _parse_statement child1
    _new_ast2 result $_CASE_KW $result $child1
  elif [ $_tok = $_DEFAULT_KW ] ; then
    _get_tok __
    _expect_tok __ $__COLON__
    _parse_statement result
    _new_ast1 result $_DEFAULT_KW $result
  elif [ $_tok = $_WHILE_KW ] ; then
    _get_tok __
    _parse_parenthesized_expression result 0
    _parse_statement child1
    _new_ast2 result $_WHILE_KW $result $child1
  elif [ $_tok = $_DO_KW ] ; then
    _get_tok __
    _parse_statement result
    _expect_tok __ $_WHILE_KW
    _parse_parenthesized_expression child1 0
    _expect_tok __ $__SEMICOLON__
    _new_ast2 result $_DO_KW $result $child1
  elif [ $_tok = $_FOR_KW ] ; then
    _get_tok __
    _expect_tok __ $__LPAREN__
    _parse_comma_expression_opt result
    _expect_tok __ $__SEMICOLON__
    _parse_comma_expression_opt child1
    _expect_tok __ $__SEMICOLON__
    _parse_comma_expression_opt child2
    _expect_tok __ $__RPAREN__
    _parse_statement child3
    _new_ast4 result $_FOR_KW $result $child1 $child2 $child3
  elif [ $_tok = $_GOTO_KW ] ; then
    _get_tok __
    _expect_tok __ $_IDENTIFIER
    _new_ast0 __t1 $_IDENTIFIER $_val
    _new_ast1 result $_GOTO_KW $__t1
    _expect_tok __ $__SEMICOLON__
  elif [ $_tok = $_CONTINUE_KW ] ; then
    _get_tok __
    _expect_tok __ $__SEMICOLON__
    _new_ast0 result $_CONTINUE_KW 0
  elif [ $_tok = $_BREAK_KW ] ; then
    _get_tok __
    _expect_tok __ $__SEMICOLON__
    _new_ast0 result $_BREAK_KW 0
  elif [ $_tok = $_RETURN_KW ] ; then
    _get_tok __
    _parse_comma_expression_opt result
    _expect_tok __ $__SEMICOLON__
    _new_ast1 result $_RETURN_KW $result
  elif [ $_tok = $__LBRACE__ ] ; then
    _parse_compound_statement result
  else
    start_tok=$_tok
    _parse_comma_expression_opt result
    if [ $_tok = $__COLON__ ] && [ $start_tok != $__LPAREN__ ] && { _get_op __t1 $result; [ $__t1 = $_IDENTIFIER ]; } ; then
      _get_tok __
      _parse_statement child1
      _new_ast2 result $__COLON__ $result $child1
    else
      _expect_tok __ $__SEMICOLON__
    fi
  fi
  : $(($1 = result))
  endlet $1 __t1 start_tok child3 child2 child1 result
}

: $((__t1 = rest = child1 = result = 0))
_parse_compound_statement() {
  let result; let child1; let rest; let __t1
  result=0
  _expect_tok __ $__LBRACE__
  while [ $_tok != $__RBRACE__ ] && [ $_tok != -1 ]; do
    if _is_type_starter __t1 $_tok; [ $__t1 != 0 ] ; then
      _parse_declaration child1 1
    else
      _parse_statement child1
    fi
    if [ $child1 = 0 ] ; then
      continue
    fi
    if [ $result = 0 ] ; then
      _new_ast2 result $__LBRACE__ $child1 0
      rest=$result
    else
      _new_ast2 child1 $__LBRACE__ $child1 0
      _set_child __ $rest 1 $child1
      rest=$child1
    fi
  done
  _expect_tok __ $__RBRACE__
  : $(($1 = result))
  endlet $1 __t1 rest child1 result
}

_runtime_use_local_vars=0
_runtime_local_vars_defined=0
_runtime_local_vars() {
  if [ $(((_runtime_local_vars_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "#_ Local variables\n"
  printf "__=0\n"
  printf "__SP=0\n"
  printf "let() { # \$1: variable name, \$2: value (optional)\n"
  printf "  : \$((__\$((__SP += 1))=\$1)) # Push\n"
  printf "  : \$((\$1=\${2-0}))           # Init\n"
  printf "}\n"
  printf "endlet() { # \$1: return variable\n"
  printf "           # \$2...: function local variables\n"
  printf "  __ret=\$1 # Don't overwrite return value\n"
  printf "  : \$((__tmp = \$__ret))\n"
  printf "  while [ \$# -ge 2 ]; do\n"
  printf "    : \$((\$2 = __\$(((__SP -= 1) + 1)))) # Pop\n"
  printf "    shift;\n"
  printf "  done\n"
  printf "  : \$((\$__ret=__tmp))   # Restore return value\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_char_to_int=0
_runtime_char_to_int_defined=0
_runtime_char_to_int() {
  if [ $(((_runtime_char_to_int_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "__c2i_0=48\n"
  printf "__c2i_1=49\n"
  printf "__c2i_2=50\n"
  printf "__c2i_3=51\n"
  printf "__c2i_4=52\n"
  printf "__c2i_5=53\n"
  printf "__c2i_6=54\n"
  printf "__c2i_7=55\n"
  printf "__c2i_8=56\n"
  printf "__c2i_9=57\n"
  printf "__c2i_a=97\n"
  printf "__c2i_b=98\n"
  printf "__c2i_c=99\n"
  printf "__c2i_d=100\n"
  printf "__c2i_e=101\n"
  printf "__c2i_f=102\n"
  printf "__c2i_g=103\n"
  printf "__c2i_h=104\n"
  printf "__c2i_i=105\n"
  printf "__c2i_j=106\n"
  printf "__c2i_k=107\n"
  printf "__c2i_l=108\n"
  printf "__c2i_m=109\n"
  printf "__c2i_n=110\n"
  printf "__c2i_o=111\n"
  printf "__c2i_p=112\n"
  printf "__c2i_q=113\n"
  printf "__c2i_r=114\n"
  printf "__c2i_s=115\n"
  printf "__c2i_t=116\n"
  printf "__c2i_u=117\n"
  printf "__c2i_v=118\n"
  printf "__c2i_w=119\n"
  printf "__c2i_x=120\n"
  printf "__c2i_y=121\n"
  printf "__c2i_z=122\n"
  printf "__c2i_A=65\n"
  printf "__c2i_B=66\n"
  printf "__c2i_C=67\n"
  printf "__c2i_D=68\n"
  printf "__c2i_E=69\n"
  printf "__c2i_F=70\n"
  printf "__c2i_G=71\n"
  printf "__c2i_H=72\n"
  printf "__c2i_I=73\n"
  printf "__c2i_J=74\n"
  printf "__c2i_K=75\n"
  printf "__c2i_L=76\n"
  printf "__c2i_M=77\n"
  printf "__c2i_N=78\n"
  printf "__c2i_O=79\n"
  printf "__c2i_P=80\n"
  printf "__c2i_Q=81\n"
  printf "__c2i_R=82\n"
  printf "__c2i_S=83\n"
  printf "__c2i_T=84\n"
  printf "__c2i_U=85\n"
  printf "__c2i_V=86\n"
  printf "__c2i_W=87\n"
  printf "__c2i_X=88\n"
  printf "__c2i_Y=89\n"
  printf "__c2i_Z=90\n"
  printf "char_to_int() {\n"
  printf "  case \$1 in\n"
  printf "    [[:alnum:]]) __c=\$((__c2i_\$1)) ;;\n"
  printf "    ' ') __c=32 ;;\n"
  printf "    '!') __c=33 ;;\n"
  printf "    '\"') __c=34 ;;\n"
  printf "    '#') __c=35 ;;\n"
  printf "    '\$') __c=36 ;;\n"
  printf "    '%%') __c=37 ;;\n"
  printf "    '&') __c=38 ;;\n"
  printf "    \"'\") __c=39 ;;\n"
  printf "    '(') __c=40 ;;\n"
  printf "    ')') __c=41 ;;\n"
  printf "    '*') __c=42 ;;\n"
  printf "    '+') __c=43 ;;\n"
  printf "    ',') __c=44 ;;\n"
  printf "    '-') __c=45 ;;\n"
  printf "    '.') __c=46 ;;\n"
  printf "    '/') __c=47 ;;\n"
  printf "    ':') __c=58 ;;\n"
  printf "    ';') __c=59 ;;\n"
  printf "    '<') __c=60 ;;\n"
  printf "    '=') __c=61 ;;\n"
  printf "    '>') __c=62 ;;\n"
  printf "    '?') __c=63 ;;\n"
  printf "    '@') __c=64 ;;\n"
  printf "    '[') __c=91 ;;\n"
  printf "    '\\\\') __c=92 ;;\n"
  printf "    ']') __c=93 ;;\n"
  printf "    '^') __c=94 ;;\n"
  printf "    '_') __c=95 ;;\n"
  printf "    '\`') __c=96 ;;\n"
  printf "    '{') __c=123 ;;\n"
  printf "    '|') __c=124 ;;\n"
  printf "    '}') __c=125 ;;\n"
  printf "    '~') __c=126 ;;\n"
  printf "    *)\n"
  printf "      __c=\$(printf \"%%d\" \"'\$1\"); __c=\$((__c > 0 ? __c : 256 + __c)) ;;\n"
  printf "  esac\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_unpack_string_to_buf=0
_runtime_unpack_string_to_buf_defined=0
_runtime_unpack_string_to_buf() {
  if [ $(((_runtime_unpack_string_to_buf_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_char_to_int __
  printf "#_ Unpack a Shell string into an appropriately sized buffer\n"
  printf "unpack_string_to_buf() { # \$1: Shell string, \$2: Buffer, \$3: Ends with EOF?\n"
  printf "  __fgetc_buf=\"\$1\"\n"
  printf "  __buffer=\$2\n"
  printf "  __ends_with_eof=\${3:-1}\n"
  printf "  __fgetc_buf16=\n"
  printf "  __stdin_buf256=\n"
  printf "  __continue=1\n"
  printf "  while [ \$__continue != 0 ] ; do\n"
  printf "    if [ -z \"\$__stdin_buf256\" ]; then\n"
  printf "      if [ \${#__fgetc_buf} -ge 256 ]; then\n"
  printf "        __temp=\"\${__fgetc_buf#????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????}\"\n"
  printf "        __stdin_buf256=\"\${__fgetc_buf%%\"\$__temp\"}\"\n"
  printf "        __fgetc_buf=\"\$__temp\"\n"
  printf "      else\n"
  printf "        __stdin_buf256=\"\$__fgetc_buf\"\n"
  printf "        __fgetc_buf=\n"
  printf ""
  printf "      fi\n"
  printf "    fi\n"
  printf "    if [ -z \"\$__fgetc_buf16\" ]; then\n"
  printf "      if [ \${#__stdin_buf256} -ge 16 ]; then\n"
  printf "        __temp=\"\${__stdin_buf256#????????????????}\"\n"
  printf "        __fgetc_buf16=\"\${__stdin_buf256%%\"\$__temp\"}\"\n"
  printf "        __stdin_buf256=\"\$__temp\"\n"
  printf "      else\n"
  printf "        __fgetc_buf16=\"\$__stdin_buf256\"\n"
  printf "        __stdin_buf256=\n"
  printf "        __continue=0\n"
  printf "      fi\n"
  printf "    fi\n"
  printf "    while [ ! -z \"\$__fgetc_buf16\" ]; do\n"
  printf "      case \"\$__fgetc_buf16\" in\n"
  printf "        \" \"*) : \$((_\$__buffer = 32))  ;;\n"
  printf "        \"e\"*) : \$((_\$__buffer = 101)) ;;\n"
  printf "        \"=\"*) : \$((_\$__buffer = 61))  ;;\n"
  printf "        \"t\"*) : \$((_\$__buffer = 116)) ;;\n"
  printf "        \";\"*) : \$((_\$__buffer = 59))  ;;\n"
  printf "        \"i\"*) : \$((_\$__buffer = 105)) ;;\n"
  printf "        \")\"*) : \$((_\$__buffer = 41))  ;;\n"
  printf "        \"(\"*) : \$((_\$__buffer = 40))  ;;\n"
  printf "        \"n\"*) : \$((_\$__buffer = 110)) ;;\n"
  printf "        \"s\"*) : \$((_\$__buffer = 115)) ;;\n"
  printf "        \"l\"*) : \$((_\$__buffer = 108)) ;;\n"
  printf "        \"+\"*) : \$((_\$__buffer = 43))  ;;\n"
  printf "        \"p\"*) : \$((_\$__buffer = 112)) ;;\n"
  printf "        \"a\"*) : \$((_\$__buffer = 97))  ;;\n"
  printf "        \"r\"*) : \$((_\$__buffer = 114)) ;;\n"
  printf "        \"f\"*) : \$((_\$__buffer = 102)) ;;\n"
  printf "        \"d\"*) : \$((_\$__buffer = 100)) ;;\n"
  printf "        \"*\"*) : \$((_\$__buffer = 42))  ;;\n"
  printf "        *)\n"
  printf "          char_to_int \"\${__fgetc_buf16%%\"\${__fgetc_buf16#?}\"}\"\n"
  printf "          : \$((_\$__buffer = __c))\n"
  printf "          ;;\n"
  printf "      esac\n"
  printf "      __fgetc_buf16=\"\${__fgetc_buf16#?}\"  # Remove the first character\n"
  printf "      : \$((__buffer += 1))              # Move to the next buffer position\n"
  printf "    done\n"
  printf "  done\n"
  printf "\n"
  printf "  if [ \$__ends_with_eof -eq 0 ]; then # Ends with newline and not EOF?\n"
  printf "    : \$((_\$__buffer = 10))            # Line ends with newline\n"
  printf "    : \$((__buffer += 1))\n"
  printf "  fi\n"
  printf "  : \$((_\$__buffer = 0))               # Then \\\\0\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_malloc=0
_runtime_malloc_defined=0
_runtime_malloc() {
  if [ $(((_runtime_malloc_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "__ALLOC=1 # Starting heap at 1 because 0 is the null pointer.\n\n"
  printf "_malloc() { # \$2 = object size\n"
  printf "  : \$((_\$__ALLOC = \$2)) # Track object size\n"
  printf "  : \$((\$1 = \$__ALLOC + 1))\n"
  printf "  : \$((__ALLOC += \$2 + 1))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_initialize=0
_runtime_initialize_defined=0
_runtime_initialize() {
  if [ $(((_runtime_initialize_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "#_ Initialize memory with the list of values.\n"
  printf "initialize() { # \$1 = var name, \$2 = length, \$3... = elements\n"
  printf "  __ptr=\$((\$1))\n"
  printf "  __size=\$2\n"
  printf "  __i=0\n"
  printf "  while [ \$# -ge 3 ]; do\n"
  printf "    : \$((_\$((__ptr + __i)) = \$3))\n"
  printf "    : \$((__i += 1))\n"
  printf "    shift\n"
  printf "  done\n"
  printf "\n"
  printf "  while [ \$__i -lt \$__size ]; do\n"
  printf "    : \$((_\$((__ptr + __i)) = 0))\n"
  printf "    : \$((__i += 1))\n"
  printf "  done\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_defarr=0
_runtime_defarr_defined=0
_runtime_defarr() {
  if [ $(((_runtime_defarr_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  if [ $_runtime_use_initialize != 0 ] ; then
    _runtime_initialize __
    printf "defarr() {\n"
    printf "  _malloc \$1 \$2;\n"
    printf "  if [ \$# -gt 2 ]; then initialize \$@; fi\n"
    printf "}\n"
  else
    printf "defarr() { _malloc \$1 \$2; }\n"
  fi
  printf "\n"
}

_runtime_use_free=0
_runtime_free_defined=0
_runtime_free() {
  if [ $(((_runtime_free_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "_free() { # \$2 = object to free\n"
  printf "  __ptr=\$((\$2 - 1))          # Start of object\n"
  printf "  __end=\$((__ptr + _\$__ptr)) # End of object\n"
  printf "  while [ \$__ptr -lt \$__end ]; do\n"
  printf "    unset \"_\$__ptr\"\n"
  printf "    : \$((__ptr += 1))\n"
  printf "  done\n"
  printf "  : \$((\$1 = 0))              # Return 0\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_make_argv=0
_runtime_make_argv_defined=0
_runtime_make_argv() {
  if [ $(((_runtime_make_argv_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  _runtime_unpack_string_to_buf __
  printf "make_argv() {\n"
  printf "  __argc=\$1; shift;\n"
  printf "  _malloc __argv \$((__argc + 1)) # Allocate enough space for all elements and null terminator.\n"
  printf "  __argv_ptr=\$__argv\n"
  printf "\n"
  printf "  while [ \$# -ge 1 ]; do\n"
  printf "    _malloc _\$__argv_ptr \$((\${#1} + 1))\n"
  printf "    unpack_string_to_buf \"\$1\" \$((_\$__argv_ptr)) 1\n"
  printf "    : \$((__argv_ptr += 1))\n"
  printf "    shift\n"
  printf "  done\n"
  printf "  : \$((_\$__argv_ptr = 0)) # Null-terminate the argv array\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_unpack_escaped_string=0
_runtime_unpack_escaped_string_defined=0
_runtime_unpack_escaped_string() {
  if [ $(((_runtime_unpack_escaped_string_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  _runtime_char_to_int __
  printf "next_sub_buffer() {\n"
  printf "  if [ -z \"\$__us_buf256\" ]; then\n"
  printf "    if [ \${#__str} -ge 256 ]; then\n"
  printf "      __temp=\"\${__str#????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????}\"\n"
  printf "      __us_buf256=\"\${__str%%\"\$__temp\"}\"\n"
  printf "      __str=\"\$__temp\"\n"
  printf "    else\n"
  printf "      __us_buf256=\"\$__str\"\n"
  printf "      __str=\n"
  printf ""
  printf "    fi\n"
  printf "  fi\n"
  printf "  if [ -z \"\$__us_buf16\" ]; then\n"
  printf "    if [ \${#__us_buf256} -ge 16 ]; then\n"
  printf "      __temp=\"\${__us_buf256#????????????????}\"\n"
  printf "      __us_buf16=\"\${__us_buf256%%\"\$__temp\"}\"\n"
  printf "      __us_buf256=\"\$__temp\"\n"
  printf "    else\n"
  printf "      __us_buf16=\"\$__us_buf256\"\n"
  printf "      __us_buf256=\n"
  printf ""
  printf "    fi\n"
  printf "  fi\n"
  printf "}\n"
  printf "unpack_escaped_string() { # \$1 = string, \$2 = size (optional)\n"
  printf "  __str=\"\$1\"\n"
  printf "  # Allocates enough space for all characters, assuming that no character is escaped\n"
  printf "  _malloc __addr \$((\${2:-\${#__str} + 1}))\n"
  printf "  __ptr=\$__addr\n"
  printf "  __end=\$((__ptr + \${2:-\${#__str} + 1})) # End of allocated memory\n"
  printf "  __us_buf16=\n"
  printf "  __us_buf256=\n"
  printf "  while [ ! -z \"\$__str\" ] || [ ! -z \"\$__us_buf256\" ] ; do\n"
  printf "    next_sub_buffer\n"
  printf "    while [ ! -z \"\$__us_buf16\" ]; do\n"
  printf "      case \"\$__us_buf16\" in\n"
  printf "        '\\\\'*)\n"
  printf "          __us_buf16=\"\${__us_buf16#?}\" # Remove the current char from \$__us_buf16\n"
  printf "          if [ -z \"\$__us_buf16\" ]; then next_sub_buffer; fi\n"
  printf "          case \"\$__us_buf16\" in\n"
  printf "            '0'*) __c=0 ;;\n"
  printf "            'a'*) __c=7 ;;\n"
  printf "            'b'*) __c=8 ;;\n"
  printf "            'f'*) __c=12 ;;\n"
  printf "            'n'*) __c=10 ;;\n"
  printf "            'r'*) __c=13 ;;\n"
  printf "            't'*) __c=9 ;;\n"
  printf "            'v'*) __c=11 ;;\n"
  printf "            '\\\\'*) __c=92 ;;\n"
  printf "            '\"'*) __c=34 ;;\n"
  printf "            \"'\"*) __c=39 ;;\n"
  printf "            '?'*) __c=63 ;;\n"
  printf "            '\$'*) __c=36 ;; # Not in C, used to escape variable expansion between double quotes\n"
  printf "            *) echo \"invalid escape in string: \$__us_buf16\"; exit 1 ;;\n"
  printf "          esac\n"
  printf "          __us_buf16=\"\${__us_buf16#?}\" # Remove the current char from \$__us_buf16\n"
  printf "          ;;\n"
  printf "        *)\n"
  printf "          char_to_int \"\${__us_buf16%%\"\${__us_buf16#?}\"}\"\n"
  printf "          __us_buf16=\"\${__us_buf16#?}\" # Remove the current char from \$__us_buf16\n"
  printf "          ;;\n"
  printf "      esac\n"
  printf "    : \$((_\$__ptr = __c))\n"
  printf "    : \$((__ptr += 1))\n"
  printf "    done\n"
  printf "  done\n"
  printf "  while [ \$__ptr -le \$__end ]; do\n"
  printf "    : \$((_\$__ptr = 0))\n"
  printf "    : \$((__ptr += 1))\n"
  printf "  done\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_defstr=0
_runtime_defstr_defined=0
_runtime_defstr() {
  if [ $(((_runtime_defstr_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_unpack_escaped_string __
  printf "#_ Define a string, and return a reference to it in the varible taken as argument.\n"
  printf "#_ If the variable is already defined, this function does nothing.\n"
  printf "#_ Note that it's up to the caller to ensure that no 2 strings share the same variable.\n"
  printf "defstr() { # \$1 = variable name, \$2 = string, \$3 = size (optional)\n"
  printf "  set +u # Necessary to allow the variable to be empty\n"
  printf "  if [ \$((\$1)) -eq 0 ]; then\n"
  printf "    unpack_escaped_string \"\$2\" \$3\n"
  printf "    : \$((\$1 = __addr))\n"
  printf "  fi\n"
  printf "  set -u\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_getchar=0
_runtime_getchar_defined=0
_runtime_getchar() {
  if [ $(((_runtime_getchar_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_char_to_int __
  printf "__stdin_buf=\n"
  printf "__stdin_line_ending=0 # Line ending, either -1 (EOF) or 10 ('\\\\n')\n"
  printf "__stdin_buf16=\n"
  printf "__stdin_buf256=\n"
  printf "__stdin_end=1\n"
  printf "_getchar() {\n"
  printf "  if [ -z \"\$__stdin_buf16\" ] && [ \$__stdin_end -eq 1 ] ; then          # need to get next line when buffer empty\n"
  printf "    if [ \$__stdin_line_ending != 0 ]; then  # Line is empty, return line ending\n"
  printf "      : \$((\$1 = __stdin_line_ending))\n"
  printf "      __stdin_line_ending=0                  # Reset line ending for next getchar call\n"
  printf "      return\n"
  printf "    fi\n"
  printf "    __stdin_end=0\n"
  printf "    IFS=                                            # don't split input\n"
  printf "    if read -r __stdin_buf ; then                   # read next line into \$__stdin_buf\n"
  printf "      if [ -z \"\$__stdin_buf\" ] ; then               # an empty line implies a newline character\n"
  printf "        : \$((\$1 = 10))                              # next getchar call will read next line\n"
  printf "        return\n"
  printf "      fi\n"
  printf "      __stdin_line_ending=10\n"
  printf "    else\n"
  printf "      if [ -z \"\$__stdin_buf\" ] ; then               # EOF reached when read fails\n"
  printf "        : \$((\$1 = -1))\n"
  printf "        return\n"
  printf "      else\n"
  printf "        __stdin_line_ending=-1\n"
  printf "      fi\n"
  printf "    fi\n"
  printf "  fi\n"
  printf "  if [ -z \"\$__stdin_buf256\" ]; then\n"
  printf "    if [ \${#__stdin_buf} -ge 256 ]; then\n"
  printf "      __temp=\"\${__stdin_buf#????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????}\"\n"
  printf "      __stdin_buf256=\"\${__stdin_buf%%\"\$__temp\"}\"\n"
  printf "      __stdin_buf=\"\$__temp\"\n"
  printf "    else\n"
  printf "      __stdin_buf256=\"\$__stdin_buf\"\n"
  printf "      __stdin_buf=\n"
  printf ""
  printf "    fi\n"
  printf "  fi\n"
  printf "  if [ -z \"\$__stdin_buf16\" ]; then\n"
  printf "    if [ \${#__stdin_buf256} -ge 16 ]; then\n"
  printf "      __temp=\"\${__stdin_buf256#????????????????}\"\n"
  printf "      __stdin_buf16=\"\${__stdin_buf256%%\"\$__temp\"}\"\n"
  printf "      __stdin_buf256=\"\$__temp\"\n"
  printf "    else\n"
  printf "      __stdin_buf16=\"\$__stdin_buf256\"\n"
  printf "      __stdin_buf256=\n"
  printf "      __stdin_end=1\n"
  printf "    fi\n"
  printf "  fi\n"
  printf "  case \"\$__stdin_buf16\" in\n"
  printf "    \" \"*) : \$((\$1 = 32))  ;;\n"
  printf "    \"e\"*) : \$((\$1 = 101)) ;;\n"
  printf "    \"=\"*) : \$((\$1 = 61))  ;;\n"
  printf "    \"t\"*) : \$((\$1 = 116)) ;;\n"
  printf "    \";\"*) : \$((\$1 = 59))  ;;\n"
  printf "    \"i\"*) : \$((\$1 = 105)) ;;\n"
  printf "    \")\"*) : \$((\$1 = 41))  ;;\n"
  printf "    \"(\"*) : \$((\$1 = 40))  ;;\n"
  printf "    \"n\"*) : \$((\$1 = 110)) ;;\n"
  printf "    \"s\"*) : \$((\$1 = 115)) ;;\n"
  printf "    \"l\"*) : \$((\$1 = 108)) ;;\n"
  printf "    \"+\"*) : \$((\$1 = 43))  ;;\n"
  printf "    \"p\"*) : \$((\$1 = 112)) ;;\n"
  printf "    \"a\"*) : \$((\$1 = 97))  ;;\n"
  printf "    \"r\"*) : \$((\$1 = 114)) ;;\n"
  printf "    \"f\"*) : \$((\$1 = 102)) ;;\n"
  printf "    \"d\"*) : \$((\$1 = 100)) ;;\n"
  printf "    \"*\"*) : \$((\$1 = 42))  ;;\n"
  printf "    *)\n"
  printf "      char_to_int \"\${__stdin_buf16%%\"\${__stdin_buf16#?}\"}\"\n"
  printf "      : \$((\$1 = __c))\n"
  printf "      ;;\n"
  printf "  esac\n"
  printf "  __stdin_buf16=\${__stdin_buf16#?}  # Remove the first character\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_put_pstr=0
_runtime_put_pstr_defined=0
_runtime_put_pstr() {
  if [ $(((_runtime_put_pstr_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "_put_pstr() {\n"
  printf "  : \$((\$1 = 0)); shift # Return 0\n"
  printf "  __addr=\$1; shift\n"
  printf "  while [ \$((__c = _\$__addr)) != 0 ]; do\n"
  printf "    printf %%b \\\\\\\\0\$((__c/64))\$((__c/8%%8))\$((__c%%8))\n"
  printf "    : \$((__addr += 1))\n"
  printf "  done\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_printf=0
_runtime_printf_defined=0
_runtime_printf() {
  if [ $(((_runtime_printf_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_put_pstr __
  printf "read_int() {\n"
  printf "  __int=\n"
  printf "  while [ \$((__c = _\$__fmt_ptr)) != 0 ] && [ \$__c -ge 48 ] && [ \$__c -le 57 ]; do\n"
  printf "    __int=\"\$__int\$((__c - 48))\"\n"
  printf "    : \$((__fmt_ptr += 1))\n"
  printf "  done\n"
  printf "}\n"
  printf "\n"
  printf "pad() {\n"
  printf "  if [ \$((\$1 - 1)) -ge 1 ]; then\n"
  printf "    printf \"%%\$((\$1 - 1))s\" \"\"\n"
  printf "  fi\n"
  printf "}\n"
  printf "\n"
  printf "printf_invalid_format_error() {\n"
  printf "  printf \"Invalid format specifier. %%%%\"\n"
  printf "  : \$((_\$__fmt_ptr = 0)) # Terminate string after %%...\n"
  printf "  _put_pstr __ \$__mod_start\n"
  printf "  printf \"\\\\n\"\n"
  printf "  exit 1\n"
  printf "}\n"
  printf "\n"
  printf "printf_reset() {\n"
  printf "  __mod=0\n"
  printf "  __flags=\n"
  printf "  __width=\n"
  printf "  __precision=\n"
  printf "}\n"
  printf "\n"
  printf "_printf() { # \$1 = printf format string, \$2... = printf args\n"
  printf "  : \$((\$1 = 0)); shift # Return 0\n"
  printf "  __fmt_ptr=\$1; shift\n"
  printf "  __mod_start=0\n"
  printf "  printf_reset\n"
  printf "  while [ \"\$((__head = _\$__fmt_ptr))\" != 0 ] ; do\n"
  printf "    __fmt_ptr=\$((__fmt_ptr + 1))\n"
  printf "    if [ \$__mod -eq 1 ] ; then\n"
  printf "      __char=\$(printf \"\\\\\\\\\$((\$__head/64))\$((\$__head/8%%8))\$((\$__head%%8))\")\n"
  printf "      __head_char=\$__char\n"
  printf "      case \$__head_char in\n"
  printf "        '%%')\n"
  printf "          if [ -n \"\${__flags}\${__width}\${__precision}\" ]; then printf_invalid_format_error; fi\n"
  printf "          printf \"%%%%\"\n"
  printf "          printf_reset\n"
  printf "          ;;\n"
  printf "        'd'|'i'|'o'|'u'|'x'|'X')\n"
  printf "          printf \"%%\${__flags}\${__width}\${__precision}\${__head_char}\" \$1\n"
  printf "          shift\n"
  printf "          printf_reset\n"
  printf "          ;;\n"
  printf "        'c')\n"
  printf "          case \"\$__flags\" in\n"
  printf "            *'-'*)\n"
  printf "              printf %%b \\\\\\\\0\$((\$1/64))\$((\$1/8%%8))\$((\$1%%8)); pad \${__width:-0} ;;\n"
  printf "            *) pad \${__width:-0}; printf %%b \\\\\\\\0\$((\$1/64))\$((\$1/8%%8))\$((\$1%%8)) ;;\n"
  printf "          esac\n"
  printf "          shift\n"
  printf "          printf_reset\n"
  printf "          ;;\n"
  printf "        's')\n"
  printf "          # We only want to use the shell's native printf (and _put_pstr subshell) if %%s has sub-specifiers\n"
  printf "          if [ -z \"{__flags}\${__width}{__precision}\" ]; then\n"
  printf "            _put_pstr __ \$1\n"
  printf "          else\n"
  printf "            printf \"%%\${__flags}\${__width}\${__precision}s\" \"\$(_put_pstr __ \$1)\"\n"
  printf "          fi\n"
  printf "          shift\n"
  printf "          printf_reset\n"
  printf "          ;;\n"
  printf "        '-'|'+'|' '|'#'|'0')\n"
  printf "          if [ -n \"\${__width}\${__precision}\" ]; then printf_invalid_format_error; fi\n"
  printf "          __flags=\"\$__flags\$__head_char\"\n"
  printf "          ;;\n"
  printf "        [0-9])\n"
  printf "          if [ -n \"\${__width}\${__precision}\" ]; then printf_invalid_format_error; fi\n"
  printf "          read_int\n"
  printf "          __width=\"\$__head_char\$__int\"\n"
  printf "          ;;\n"
  printf "        '*')\n"
  printf "          if [ -n \"\${__width}\${__precision}\" ]; then printf_invalid_format_error; fi\n"
  printf "          __width=\$1\n"
  printf "          shift\n"
  printf "          ;;\n"
  printf "        '.')\n"
  printf "          __head=\$((_\$__fmt_ptr))\n"
  printf "          if [ \$__head = 42 ]; then # 42 = '*'\n"
  printf "            __fmt_ptr=\$((__fmt_ptr + 1))\n"
  printf "            __precision=\".\$1\"\n"
  printf "            shift\n"
  printf "          elif [ \$__head -ge 48 ] && [ \$__head -le 57 ]; then\n"
  printf "            read_int\n"
  printf "            __precision=\".\$__int\"\n"
  printf "          else\n"
  printf "            printf_invalid_format_error\n"
  printf "          fi\n"
  printf "          ;;\n"
  printf "        *)\n"
  printf "          echo \"4: Unknown format specifier %%\$__head_char\"; exit 1\n"
  printf "      esac\n"
  printf "    elif [ \$__head = 37 ]; then # 37 == '%%'\n"
  printf "      __mod=1; __mod_start=\$__fmt_ptr\n"
  printf "    else\n"
  printf "      printf %%b \\\\\\\\0\$((\$__head/64))\$((\$__head/8%%8))\$((\$__head%%8))\n"
  printf "    fi\n"
  printf "  done\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_unpack_string=0
_runtime_unpack_string_defined=0
_runtime_unpack_string() {
  if [ $(((_runtime_unpack_string_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  _runtime_unpack_string_to_buf __
  printf "#_ Unpack a Shell string into a newly allocated buffer\n"
  printf "unpack_string() { # \$1: return location, \$2: Shell string\n"
  printf "  _malloc __addr \$((\${#2} + 1))  # Allocate buffer\n"
  printf "  unpack_string_to_buf \"\$2\" \$__addr\n"
  printf "  : \$((\$1 = __addr))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_isatty=0
_runtime_isatty_defined=0
_runtime_isatty() {
  if [ $(((_runtime_isatty_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  printf "_isatty() { # \$2: fd\n"
  printf "  [ -t \$2 ] && : \$((\$1 = 1)) || : \$((\$1 = 0))\n"
  printf "}\n\n"
}

_runtime_use_open=0
_runtime_open_defined=0
_runtime_open() {
  if [ $(((_runtime_open_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  _runtime_put_pstr __
  printf "_malloc __buffer_fd0 1000   # Allocate buffer\n"
  printf ": \$((_\$__buffer_fd0 = 0))   # Init buffer to \"\"\n"
  printf ": \$((__cursor_fd0 = 0))     # Make buffer empty\n"
  printf ": \$((__buflen_fd0 = 1000))  # Init buffer length\n"
  printf "__state_fd0=0 # stdin\n"
  printf "__state_fd1=1 # stdout\n"
  printf "__state_fd2=2 # stderr\n"
  printf "__state_fd3=-1\n"
  printf "__state_fd4=-1\n"
  printf "__state_fd5=-1\n"
  printf "__state_fd6=-1\n"
  printf "__state_fd7=-1\n"
  printf "__state_fd8=-1\n"
  printf "__state_fd9=-1\n"
  printf "\n"
  printf "_open() { # \$2: filename, \$3: flags, \$4: mode\n"
  printf "  # Get available fd\n"
  printf "  __fd=0\n"
  printf "  while [ \$__fd -lt 10 ]; do\n"
  printf "    if [ \$((__state_fd\$__fd)) -lt 0 ]; then\n"
  printf "      break\n"
  printf "    fi\n"
  printf "    : \$((__fd += 1))\n"
  printf "  done\n"
  printf "  if [ \$__fd -gt 9 ] ; then\n"
  printf "    # Some shells don't support fd > 9\n"
  printf "    echo \"No more file descriptors available to open \$(_put_pstr __ \$2)\" ; exit 1\n"
  printf "  else\n"
  printf "    # Because the file must be read line-by-line, and string\n"
  printf "    # values can't be assigned to dynamic variables, each line\n"
  printf "    # is read and then unpacked in the buffer.\n"
  printf "    _malloc __addr 1000                 # Allocate buffer\n"
  printf "    : \$((_\$__addr = 0))                 # Init buffer to \"\"\n"
  printf "    : \$((__buffer_fd\$__fd = __addr))    # Buffer address\n"
  printf "    : \$((__cursor_fd\$__fd = 0))         # Buffer cursor\n"
  printf "    : \$((__buflen_fd\$__fd = 1000))      # Buffer length\n"
  printf "    : \$((__state_fd\$__fd = \$3))         # Mark the fd as opened\n"
  printf "    __res=\$(_put_pstr __ \$2)\n"
  printf "    if [ \$3 = 0 ] ; then\n"
  printf "      case \$__fd in\n"
  printf "        0) exec 0< \"\$__res\" ;; 1) exec 1< \"\$__res\" ;; 2) exec 2< \"\$__res\" ;;\n"
  printf "        3) exec 3< \"\$__res\" ;; 4) exec 4< \"\$__res\" ;; 5) exec 5< \"\$__res\" ;;\n"
  printf "        6) exec 6< \"\$__res\" ;; 7) exec 7< \"\$__res\" ;; 8) exec 8< \"\$__res\" ;;\n"
  printf "        9) exec 9< \"\$__res\" ;;\n"
  printf "      esac\n"
  printf "    elif [ \$3 = 1 ] ; then\n"
  printf "      case \$__fd in\n"
  printf "        0) exec 0> \"\$__res\" ;; 1) exec 1> \"\$__res\" ;; 2) exec 2> \"\$__res\" ;;\n"
  printf "        3) exec 3> \"\$__res\" ;; 4) exec 4> \"\$__res\" ;; 5) exec 5> \"\$__res\" ;;\n"
  printf "        6) exec 6> \"\$__res\" ;; 7) exec 7> \"\$__res\" ;; 8) exec 8> \"\$__res\" ;;\n"
  printf "        9) exec 9> \"\$__res\" ;;\n"
  printf "      esac\n"
  printf "    elif [ \$3 = 2 ] ; then\n"
  printf "      case \$__fd in\n"
  printf "        0) exec 0>> \"\$__res\" ;; 1) exec 1>> \"\$__res\" ;; 2) exec 2>> \"\$__res\" ;;\n"
  printf "        3) exec 3>> \"\$__res\" ;; 4) exec 4>> \"\$__res\" ;; 5) exec 5>> \"\$__res\" ;;\n"
  printf "        6) exec 6>> \"\$__res\" ;; 7) exec 7>> \"\$__res\" ;; 8) exec 8>> \"\$__res\" ;;\n"
  printf "        9) exec 9>> \"\$__res\" ;;\n"
  printf "      esac\n"
  printf "    else\n"
  printf "      echo \"Unknown file mode\" ; exit 1\n"
  printf "    fi\n"
  printf "  fi\n"
  printf "  : \$((\$1 = __fd))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_read_byte=0
_runtime_read_byte_defined=0
_runtime_read_byte() {
  if [ $(((_runtime_read_byte_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_malloc __
  _runtime_free __
  _runtime_char_to_int __
  _runtime_unpack_string_to_buf __
  printf "refill_buffer() { # \$1: fd\n"
  printf "  __fd=\$1\n"
  printf "  __buffer=\$((__buffer_fd\$__fd))\n"
  printf "\n"
  printf "  IFS=\n"
  printf "  __ends_with_eof=0\n"
  printf "  read -r __temp_buf <&\$__fd || __ends_with_eof=1\n"
  printf "\n"
  printf "  # Check that the buffer is large enough to unpack the line\n"
  printf "  __buflen=\$((__buflen_fd\$__fd - 2)) # Minus 2 to account for newline and \\\\0\n"
  printf "  __len=\${#__temp_buf}\n"
  printf "  if [ \$__len -gt \$__buflen ]; then\n"
  printf "    # Free buffer and reallocate a new one double the line size\n"
  printf "    __buflen=\$((__len * 2))\n"
  printf "    _free __ \$__buffer\n"
  printf "    _malloc __buffer \$__buflen\n"
  printf "    : \$((__buffer_fd\$__fd = __buffer))\n"
  printf "    : \$((__buflen_fd\$__fd = __buflen))\n"
  printf "  fi\n"
  printf "  unpack_string_to_buf \"\$__temp_buf\" \$__buffer \$__ends_with_eof\n"
  printf "}\n"
  printf "\n"
  printf "read_byte() { # \$2: fd\n"
  printf "  __fd=\$2\n"
  printf "  : \$((__buffer=__buffer_fd\$__fd))\n"
  printf "  : \$((__cursor=__cursor_fd\$__fd))\n"
  printf "  # The cursor is at the end of the buffer, we need to read the next line\n"
  printf "  if [ \$((_\$((__buffer + __cursor)))) -eq 0 ]; then\n"
  printf "    # Buffer has been read completely, read next line\n"
  printf "    refill_buffer \$__fd\n"
  printf "    __cursor=0 # Reset cursor and reload buffer\n"
  printf "    : \$((__buffer=__buffer_fd\$__fd))\n"
  printf "    if [ \$((_\$((__buffer + __cursor)))) -eq 0 ]; then\n"
  printf "      : \$((\$1 = -1)) # EOF\n"
  printf "      return\n"
  printf "    fi\n"
  printf "  fi\n"
  printf "  : \$((\$1 = _\$((__buffer + __cursor))))\n"
  printf "  : \$((__cursor_fd\$__fd = __cursor + 1))  # Increment cursor\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_read=0
_runtime_read_defined=0
_runtime_read() {
  if [ $(((_runtime_read_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_read_byte __
  _runtime_open __
  printf "_read() { : \$((__fd = \$2)) \$((__buf = \$3)) \$((__count = \$4))\n"
  printf "  : \$((__i = 0))\n"
  printf "  while [ \$__i -lt \$__count ] ; do\n"
  printf "    read_byte __byte \$__fd\n"
  printf "    if [ \$__byte -lt 0 ] ; then break; fi\n"
  printf "    : \$((_\$((__buf + __i)) = __byte))\n"
  printf "    : \$((__i += 1))\n"
  printf "  done\n"
  printf "  : \$((\$1 = __i))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_write=0
_runtime_write_defined=0
_runtime_write() {
  if [ $(((_runtime_write_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_open __
  printf "_write() { : \$((__fd = \$2)) \$((__buf = \$3)) \$((__count = \$4))\n"
  printf "  : \$((__i = 0))\n"
  printf "  while [ \$__i -lt \$__count ] ; do\n"
  printf "    : \$((__byte = _\$((__buf+__i))))\n"
  printf "    printf %%b \\\\\\\\0\$((\$__byte/64))\$((\$__byte/8%%8))\$((\$__byte%%8)) >&\$__fd\n"
  printf "    : \$((__i += 1))\n"
  printf "  done\n"
  printf "  : \$((\$1 = __count))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_close=0
_runtime_close_defined=0
_runtime_close() {
  if [ $(((_runtime_close_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_open __
  _runtime_free __
  printf "_close() { # \$2: fd\n"
  printf "  __fd=\$2\n"
  printf "  __buf=\$((__buffer_fd\$__fd))  # Get buffer\n"
  printf "  _free __ \$__buf              # Release buffer\n"
  printf "  : \$((__state_fd\$__fd = -1))  # Mark the fd as closed\n"
  printf "  case \$__fd in\n"
  printf "    0) exec 0<&- ;; 1) exec 1<&- ;; 2) exec 2<&- ;;\n"
  printf "    3) exec 3<&- ;; 4) exec 4<&- ;; 5) exec 5<&- ;;\n"
  printf "    6) exec 6<&- ;; 7) exec 7<&- ;; 8) exec 8<&- ;;\n"
  printf "    9) exec 9<&- ;;\n"
  printf "  esac\n"
  printf "  : \$((\$1 = 0))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_fopen=0
_runtime_fopen_defined=0
_runtime_fopen() {
  if [ $(((_runtime_fopen_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_open __
  printf "#_ Open the file and return the file descriptor directly.\n"
  printf "_fopen() { # \$2: File name, \$3: Mode\n"
  printf "  _open __fd \$2 \$((_\$3 == 119)) 511\n"
  printf "  : \$((\$1 = __fd))\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_fclose=0
_runtime_fclose_defined=0
_runtime_fclose() {
  if [ $(((_runtime_fclose_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_free __
  _runtime_close __
  printf "_fclose() { # \$2: file\n"
  printf "  _close \$1 \$2\n"
  printf "}\n"
  printf "\n"
}

_runtime_use_fgetc=0
_runtime_fgetc_defined=0
_runtime_fgetc() {
  if [ $(((_runtime_fgetc_defined += 1) - 1)) != 0 ] ; then
    return
  fi
  _runtime_read_byte __
  printf "_fgetc() { # \$2: file\n"
  printf "  read_byte \$1 \$2\n"
  printf "}\n"
  printf "\n"
}

_produce_runtime() {
  if [ $_runtime_use_defstr != 0 ] ; then
    _runtime_defstr __
  fi
  if [ $_runtime_use_malloc != 0 ] ; then
    _runtime_malloc __
  fi
  if [ $_runtime_use_free != 0 ] ; then
    _runtime_free __
  fi
  if [ $_runtime_use_put_pstr != 0 ] ; then
    _runtime_put_pstr __
  fi
  if [ $_runtime_use_fopen != 0 ] ; then
    _runtime_fopen __
  fi
  if [ $_runtime_use_fclose != 0 ] ; then
    _runtime_fclose __
  fi
  if [ $_runtime_use_fgetc != 0 ] ; then
    _runtime_fgetc __
  fi
  if [ $_runtime_use_read != 0 ] ; then
    _runtime_read __
  fi
  if [ $_runtime_use_write != 0 ] ; then
    _runtime_write __
  fi
  if [ $_runtime_use_open != 0 ] ; then
    _runtime_open __
  fi
  if [ $_runtime_use_close != 0 ] ; then
    _runtime_close __
  fi
  if [ $_runtime_use_make_argv != 0 ] ; then
    _runtime_make_argv __
  fi
  if [ $_runtime_use_local_vars != 0 ] ; then
    _runtime_local_vars __
  fi
  if [ $_runtime_use_unpack_string_to_buf != 0 ] ; then
    _runtime_unpack_string_to_buf __
  fi
  if [ $_runtime_use_getchar != 0 ] ; then
    _runtime_getchar __
  fi
  if [ $_runtime_use_printf != 0 ] ; then
    _runtime_printf __
  fi
  if [ $_runtime_use_unpack_string != 0 ] ; then
    _runtime_unpack_string __
  fi
  if [ $_runtime_use_isatty != 0 ] ; then
    _runtime_isatty __
  fi
}

: $((c = 0))
_handle_shell_include() {
  let c
  _runtime_use_put_pstr=1
  _runtime_use_unpack_string=1
  while _read_char c $_fd; [ $c != -1 ]; do
    printf %b \\0$((c/64))$((c/8%8))$((c%8))
  done
  printf "\n"
  _restore_include_context __
  endlet $1 c
}

_text_pool=0
_text_alloc=1
#_ TEXT_NODES enum declaration
readonly _TEXT_TREE=0
readonly _TEXT_INTEGER=1
readonly _TEXT_INTEGER_HEX=2
readonly _TEXT_INTEGER_OCT=3
readonly _TEXT_STRING=4
readonly _TEXT_ESCAPED=5
_wrap_int() { # i: $2
  if [ $((_text_alloc + 2)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_INTEGER))
  : $((_$((_text_pool + _text_alloc + 1)) = $2))
  : $(($1 = (_text_alloc = _text_alloc + 2) - 2))
}

_wrap_int_hex() { # i: $2
  if [ $((_text_alloc + 2)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_INTEGER_HEX))
  : $((_$((_text_pool + _text_alloc + 1)) = $2))
  : $(($1 = (_text_alloc = _text_alloc + 2) - 2))
}

_wrap_int_oct() { # i: $2
  if [ $((_text_alloc + 2)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_INTEGER_OCT))
  : $((_$((_text_pool + _text_alloc + 1)) = $2))
  : $(($1 = (_text_alloc = _text_alloc + 2) - 2))
}

: $((__t1 = op = 0))
_wrap_integer() { # multiply: $2, obj: $3
  let op; let __t1
  _get_op op $3
  if [ $op = $_INTEGER ] ; then
    _get_val __t1 $3
    _wrap_int $1 $(($2 * -__t1))
  elif [ $op = $_INTEGER_HEX ] ; then
    _get_val __t1 $3
    _wrap_int_hex $1 $(($2 * -__t1))
  elif [ $op = $_INTEGER_OCT ] ; then
    _get_val __t1 $3
    _wrap_int_oct $1 $(($2 * -__t1))
  else
    defstr __str_165 "wrap_integer: unknown integer type"
    _fatal_error __ $__str_165
    : $(($1 = 0))
  fi
  endlet $1 __t1 op
}

_escape_text() { # t: $2, for_printf: $3
  if [ $((_text_alloc + 3)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_ESCAPED))
  : $((_$((_text_pool + _text_alloc + 1)) = $2))
  : $((_$((_text_pool + _text_alloc + 2)) = $3))
  : $(($1 = (_text_alloc = _text_alloc + 3) - 3))
}

_string_concat() { # t1: $2, t2: $3
  if [ $((_text_alloc + 4)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_TREE))
  : $((_$((_text_pool + _text_alloc + 1)) = 2))
  : $((_$((_text_pool + _text_alloc + 2)) = $2))
  : $((_$((_text_pool + _text_alloc + 3)) = $3))
  : $(($1 = (_text_alloc = _text_alloc + 4) - 4))
}

_string_concat3() { # t1: $2, t2: $3, t3: $4
  if [ $((_text_alloc + 5)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_TREE))
  : $((_$((_text_pool + _text_alloc + 1)) = 3))
  : $((_$((_text_pool + _text_alloc + 2)) = $2))
  : $((_$((_text_pool + _text_alloc + 3)) = $3))
  : $((_$((_text_pool + _text_alloc + 4)) = $4))
  : $(($1 = (_text_alloc = _text_alloc + 5) - 5))
}

_string_concat4() { # t1: $2, t2: $3, t3: $4, t4: $5
  if [ $((_text_alloc + 6)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_TREE))
  : $((_$((_text_pool + _text_alloc + 1)) = 4))
  : $((_$((_text_pool + _text_alloc + 2)) = $2))
  : $((_$((_text_pool + _text_alloc + 3)) = $3))
  : $((_$((_text_pool + _text_alloc + 4)) = $4))
  : $((_$((_text_pool + _text_alloc + 5)) = $5))
  : $(($1 = (_text_alloc = _text_alloc + 6) - 6))
}

_string_concat5() { # t1: $2, t2: $3, t3: $4, t4: $5, t5: $6
  if [ $((_text_alloc + 7)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_TREE))
  : $((_$((_text_pool + _text_alloc + 1)) = 5))
  : $((_$((_text_pool + _text_alloc + 2)) = $2))
  : $((_$((_text_pool + _text_alloc + 3)) = $3))
  : $((_$((_text_pool + _text_alloc + 4)) = $4))
  : $((_$((_text_pool + _text_alloc + 5)) = $5))
  : $((_$((_text_pool + _text_alloc + 6)) = $6))
  : $(($1 = (_text_alloc = _text_alloc + 7) - 7))
}

_wrap_str_imm() { # s: $2, end: $3
  if [ $((_text_alloc + 3)) -ge 1000000 ] ; then
    defstr __str_164 "string tree pool overflow"
    _fatal_error __ $__str_164
  fi
  : $((_$((_text_pool + _text_alloc)) = _TEXT_STRING))
  : $((_$((_text_pool + _text_alloc + 1)) = $2))
  : $((_$((_text_pool + _text_alloc + 2)) = $3))
  : $(($1 = (_text_alloc = _text_alloc + 3) - 3))
}

_wrap_str_lit() { # s: $2
  _wrap_str_imm $1 $2 0
}

: $((__t2 = __t1 = 0))
_wrap_str_pool() { # ident_symbol: $2
  let __t1; let __t2
  _symbol_buf __t1 $2
  _symbol_buf_end __t2 $2
  _wrap_str_imm $1 $__t1 $__t2
  endlet $1 __t2 __t1
}

_concatenate_strings_with() { # t1: $2, t2: $3, sep: $4
  if [ $2 = 0 ] ; then
    : $(($1 = $3))
    return
  fi
  if [ $3 = 0 ] ; then
    : $(($1 = $2))
    return
  fi
  _string_concat3 $1 $2 $4 $3
}

: $((for_printf = c = 0))
_print_escaped_char() { let c $2; let for_printf $3
  if [ $c = $__NUL__ ] ; then
    printf "\\\\"
    printf "0"
  elif [ $c = $__BEL__ ] ; then
    printf "\\\\"
    printf "a"
  elif [ $c = $__BS__ ] ; then
    printf "\\\\"
    printf "b"
  elif [ $c = $__FF__ ] ; then
    printf "\\\\"
    printf "f"
  elif [ $c = $__LF__ ] ; then
    printf "\\\\"
    printf "n"
  elif [ $c = $__CR__ ] ; then
    printf "\\\\"
    printf "r"
  elif [ $c = $__HT__ ] ; then
    printf "\\\\"
    printf "t"
  elif [ $c = $__VT__ ] ; then
    printf "\\\\"
    printf "v"
  elif [ $c = $__DOLLAR__ ] ; then
    printf "\\\\"
    printf "\$"
  elif [ $c = $__BACKTICK__ ] ; then
    printf "\\\\"
    printf "\`"
  elif [ $c = $__BACKSLASH__ ] ; then
    printf "\\\\"
    printf "\\\\"
    printf "\\\\"
    printf "\\\\"
  elif [ $c = $__DQUOTE__ ] ; then
    printf "\\\\"
    printf "\""
  elif [ $c = $__PERCENT__ ] && [ $for_printf != 0 ] ; then
    printf "%%"
    printf "%%"
  else
    printf %b \\0$((c/64))$((c/8%8))$((c%8))
  fi
  endlet $1 for_printf c
}

: $((for_printf = string_end = string_start = 0))
_print_escaped_string() { let string_start $2; let string_end $3; let for_printf $4
  if [ $string_end != 0 ] ; then
    while [ $string_start -lt $string_end ]; do
      _print_escaped_char __ $((_$string_start)) $for_printf
      : $((string_start += 1))
    done
  else
    while [ $((_$string_start)) != 0 ]; do
      _print_escaped_char __ $((_$string_start)) $for_printf
      : $((string_start += 1))
    done
  fi
  endlet $1 for_printf string_end string_start
}

: $((i = for_printf = t = 0))
_print_escaped_text() { let t $2; let for_printf $3
  let i
  if [ $t = 0 ] ; then
    endlet $1 i for_printf t
    return
  fi
  if [ $t -lt 0 ] ; then
    _print_escaped_char __ $((- t)) $for_printf
  elif [ $((_$((_text_pool + t)))) = $_TEXT_TREE ] ; then
    i=0
    while [ $i -lt $((_$((_text_pool + t + 1)))) ]; do
      if [ $((_$((_text_pool + t + i + 2)))) -lt 0 ] ; then
        _print_escaped_char __ $((-_$((_text_pool + t + i + 2)))) $for_printf
      else
        _print_escaped_text __ $((_$((_text_pool + t + i + 2)))) $for_printf
      fi
      : $((i += 1))
    done
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER ] ; then
    printf "%d" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER_HEX ] ; then
    printf "0x%x" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER_OCT ] ; then
    printf "0%o" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_STRING ] ; then
    _print_escaped_string __ $((_$((_text_pool + t + 1)))) $((_$((_text_pool + t + 2)))) $for_printf
  elif [ $((_$((_text_pool + t)))) = $_TEXT_ESCAPED ] ; then
    defstr __str_166 "Cannot escape a string that is already escaped"
    _fatal_error __ $__str_166
  else
    defstr __str_167 "print_escaped_text: unexpected string tree node"
    _fatal_error __ $__str_167
  fi
  endlet $1 i for_printf t
}

: $((s = i = t = 0))
_print_text() { let t $2
  let i; let s
  if [ $t = 0 ] ; then
    endlet $1 s i t
    return
  fi
  if [ $t -lt 0 ] ; then
    printf %b \\0$(((- t)/64))$(((- t)/8%8))$(((- t)%8))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_TREE ] ; then
    i=0
    while [ $i -lt $((_$((_text_pool + t + 1)))) ]; do
      if [ $((_$((_text_pool + t + i + 2)))) -lt 0 ] ; then
        printf %b \\0$(((-_$((_text_pool + t + i + 2)))/64))$(((-_$((_text_pool + t + i + 2)))/8%8))$(((-_$((_text_pool + t + i + 2)))%8))
      else
        _print_text __ $((_$((_text_pool + t + i + 2))))
      fi
      : $((i += 1))
    done
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER ] ; then
    printf "%d" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER_HEX ] ; then
    printf "0x%x" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_INTEGER_OCT ] ; then
    printf "0%o" $((_$((_text_pool + t + 1))))
  elif [ $((_$((_text_pool + t)))) = $_TEXT_STRING ] ; then
    if [ $((_$((_text_pool + t + 2)))) = 0 ] ; then
      _putstr __ $((_$((_text_pool + t + 1))))
    else
      s=$((_$((_text_pool + t + 1))))
      while [ $s -lt $((_$((_text_pool + t + 2)))) ] || [ $((_$s)) != 0 ]; do
        printf %b \\0$(((_$s)/64))$(((_$s)/8%8))$(((_$s)%8))
        : $((s += 1))
      done
    fi
  elif [ $((_$((_text_pool + t)))) = $_TEXT_ESCAPED ] ; then
    _print_escaped_text __ $((_$((_text_pool + t + 1)))) $((_$((_text_pool + t + 2))))
  else
    defstr __str_168 "print_text: unexpected string tree node"
    _fatal_error __ $__str_168
  fi
  endlet $1 s i t
}

#_ STMT_CTX enum declaration
readonly _STMT_CTX_DEFAULT=0
readonly _STMT_CTX_ELSE_IF=1
readonly _STMT_CTX_SWITCH=2
_in_tail_position=0
_gensym_ix=0
_fun_gensym_ix=0
_max_gensym_ix=0
_string_counter=0
_rest_loc_var_fixups=0
_main_defined=0
_characters_useds=0
_any_character_used=0
#_ IDENTIFIER_TYPE enum declaration
readonly _IDENTIFIER_INTERNAL=600
readonly _IDENTIFIER_STRING=601
readonly _IDENTIFIER_DOLLAR=602
_preallocated_fresh_idents=0
_preallocated_dollar_idents=0
: $((i = 0))
_init_comp_context() {
  let i
  i=0
  while [ $i -lt 16 ]; do
    : $((_$((_characters_useds + i)) = 0))
    : $((i += 1))
  done
  i=0
  while [ $i -lt 10 ]; do
    _new_ast0 _$((_preallocated_fresh_idents + i)) $_IDENTIFIER_INTERNAL $i
    : $((i += 1))
  done
  i=0
  while [ $i -lt 10 ]; do
    _new_ast0 _$((_preallocated_dollar_idents + i)) $_IDENTIFIER_DOLLAR $i
    : $((i += 1))
  done
  endlet $1 i
}

_glo_decls=0
_glo_decl_ix=0
_nest_level=0
: $((decl = 0))
_append_glo_decl() { let decl $2
  if [ $((_glo_decl_ix + 3)) -ge 100000 ] ; then
    defstr __str_169 "glo_decls overflow"
    _fatal_error __ $__str_169
  fi
  : $((_$((_glo_decls + _glo_decl_ix)) = _nest_level))
  : $((_$((_glo_decls + _glo_decl_ix + 1)) = 1))
  : $((_$((_glo_decls + _glo_decl_ix + 2)) = decl))
  _glo_decl_ix=$((_glo_decl_ix + 3))
  endlet $1 decl
}

_append_glo_decl_fixup() {
  if [ $((_glo_decl_ix + 3)) -ge 100000 ] ; then
    defstr __str_169 "glo_decls overflow"
    _fatal_error __ $__str_169
  fi
  : $((_$((_glo_decls + _glo_decl_ix)) = -(_nest_level + 1)))
  : $((_$((_glo_decls + _glo_decl_ix + 1)) = 1))
  : $((_$((_glo_decls + _glo_decl_ix + 2)) = 0))
  _glo_decl_ix=$((_glo_decl_ix + 3))
  : $(($1 = _glo_decl_ix - 3))
}

: $((decl = fixup_ix = 0))
_fixup_glo_decl() { let fixup_ix $2; let decl $3
  if [ $((_$((_glo_decls + fixup_ix)))) -ge 0 ] ; then
    defstr __str_170 "fixup_glo_decl: invalid fixup"
    _fatal_error __ $__str_170
  fi
  : $((_$((_glo_decls + fixup_ix)) = -_$((_glo_decls + fixup_ix)) - 1))
  : $((_$((_glo_decls + fixup_ix + 2)) = decl))
  endlet $1 decl fixup_ix
}

: $((start = 0))
_undo_glo_decls() { let start $2
  while [ $start -lt $_glo_decl_ix ]; do
    : $((_$((_glo_decls + start + 1)) -= 1))
    start=$((start + 3))
  done
  endlet $1 start
}

: $((start = 0))
_any_active_glo_decls() { let start $2
  while [ $start -lt $_glo_decl_ix ]; do
    if [ $((_$((_glo_decls + start + 1)))) != 0 ] && [ $((_$((_glo_decls + start + 2)))) != 0 ] ; then
      : $(($1 = 1))
      endlet $1 start
      return
    fi
    start=$((start + 3))
  done
  : $(($1 = 0))
  endlet $1 start
}

: $((end = start = 0))
_replay_glo_decls() { let start $2; let end $3
  while [ $start -lt $end ]; do
    if [ $((_$((_glo_decls + start + 1)))) = 0 ] ; then
      _append_glo_decl __ $((_$((_glo_decls + start + 2))))
    fi
    start=$((start + 3))
  done
  endlet $1 end start
}

: $((__t1 = res = end = start = 0))
_replay_glo_decls_inline() { let start $2; let end $3
  let res; let __t1
  res=0
  while [ $start -lt $end ]; do
    if [ $((_$((_glo_decls + start + 1)))) = 0 ] ; then
      defstr __str_171 "; "
      _wrap_str_lit __t1 $__str_171
      _concatenate_strings_with res $res $((_$((_glo_decls + start + 2)))) $__t1
    fi
    start=$((start + 3))
  done
  if [ $res != 0 ] ; then
    defstr __str_171 "; "
    _wrap_str_lit __t1 $__str_171
    _string_concat res $res $__t1
  fi
  : $(($1 = res))
  endlet $1 __t1 res end start
}

: $((level = i = 0))
_print_glo_decls() {
  let i; let level
  i=0
  while [ $i -lt $_glo_decl_ix ]; do
    if [ $((_$((_glo_decls + i + 1)))) = 1 ] ; then
      if [ $((_$((_glo_decls + i + 2)))) != 0 ] ; then
        level=$((_$((_glo_decls + i))))
        while [ $level -gt 0 ]; do
          printf " "
          printf " "
          : $((level -= 1))
        done
        _print_text __ $((_$((_glo_decls + i + 2))))
        printf "\n"
      fi
    fi
    i=$((i + 3))
  done
  endlet $1 level i
}

_cgc_fs=0
_cgc_locals=0
_cgc_locals_fun=0
_cgc_globals=0
_cgc_global_alloc=0
#_ BINDING enum declaration
readonly _BINDING_PARAM_LOCAL=0
readonly _BINDING_VAR_LOCAL=1
readonly _BINDING_VAR_GLOBAL=2
readonly _BINDING_ENUM_CST=3
readonly _BINDING_LOOP=4
readonly _BINDING_SWITCH=5
readonly _BINDING_FUN=6
readonly _BINDING_GOTO_LABEL=7
readonly _BINDING_TYPE_STRUCT=8
readonly _BINDING_TYPE_UNION=9
readonly _BINDING_TYPE_ENUM=10
: $((binding = 0))
_cgc_lookup_last_binding() { let binding $3 # binding_type: $2
  while [ $binding != 0 ]; do
    if [ $((_$((_heap + binding + 1)))) = $2 ] ; then
      break
    fi
    binding=$((_$((_heap + binding))))
  done
  : $(($1 = binding))
  endlet $1 binding
}

: $((binding = 0))
_cgc_lookup_var() { let binding $3 # ident: $2
  while [ $binding != 0 ]; do
    if [ $((_$((_heap + binding + 1)))) -le $_BINDING_VAR_GLOBAL ] && [ $((_$((_heap + binding + 2)))) = $2 ] ; then
      break
    fi
    binding=$((_$((_heap + binding))))
  done
  : $(($1 = binding))
  endlet $1 binding
}

_cgc_lookup_enclosing_loop() { # env: $2
  _cgc_lookup_last_binding $1 $_BINDING_LOOP $2
}

: $((binding = 0))
_cgc_lookup_enclosing_loop_or_switch() { let binding $2
  while [ $binding != 0 ]; do
    if [ $((_$((_heap + binding + 1)))) = $_BINDING_LOOP ] || [ $((_$((_heap + binding + 1)))) = $_BINDING_SWITCH ] ; then
      break
    fi
    binding=$((_$((_heap + binding))))
  done
  : $(($1 = binding))
  endlet $1 binding
}

: $((binding = env = 0))
_cgc_add_local() { let env $5 # binding_type: $2, ident: $3, type: $4
  let binding
  _alloc_obj binding 5
  : $((_$((_heap + binding)) = env))
  : $((_$((_heap + binding + 1)) = $2))
  : $((_$((_heap + binding + 2)) = $3))
  : $((_$((_heap + binding + 3)) = _cgc_fs))
  : $((_$((_heap + binding + 4)) = $4))
  : $(($1 = binding))
  endlet $1 binding env
}

: $((__t1 = 0))
_cgc_add_local_var() { # binding_type: $2, ident: $3, type: $4
  let __t1
  : $((_cgc_fs += 1))
  _cgc_add_local _cgc_locals $2 $3 $4 $_cgc_locals
  if _cgc_lookup_var __t1 $3 $_cgc_locals_fun; [ $__t1 = 0 ] ; then
    _cgc_add_local _cgc_locals_fun $2 $3 $4 $_cgc_locals_fun
  fi
  endlet $1 __t1
}

: $((binding = 0))
_cgc_add_enclosing_loop() {
  let binding
  _alloc_obj binding 4
  : $((_$((_heap + binding)) = _cgc_locals))
  : $((_$((_heap + binding + 1)) = _BINDING_LOOP))
  : $((_$((_heap + binding + 2)) = 0))
  : $((_$((_heap + binding + 3)) = 0))
  _cgc_locals=$binding
  endlet $1 binding
}

: $((binding = 0))
_cgc_add_enclosing_switch() { # in_tail_position: $2
  let binding
  _alloc_obj binding 3
  : $((_$((_heap + binding)) = _cgc_locals))
  : $((_$((_heap + binding + 1)) = _BINDING_SWITCH))
  : $((_$((_heap + binding + 2)) = $2))
  _cgc_locals=$binding
  endlet $1 binding
}

: $((loop_depth = binding = 0))
_cgc_loop_depth() { let binding $2
  let loop_depth
  loop_depth=0
  _cgc_lookup_enclosing_loop binding $binding
  while [ $binding != 0 ]; do
    _cgc_lookup_enclosing_loop binding $((_$((_heap + binding))))
    : $((loop_depth += 1))
  done
  : $(($1 = loop_depth))
  endlet $1 loop_depth binding
}

: $((__t2 = __t1 = op = i = prefixed_with_dollar = ident = 0))
_format_special_var() { let ident $2; let prefixed_with_dollar $3
  let i; let op; let __t1; let __t2
  _get_op op $ident
  if [ $op = $_IDENTIFIER_INTERNAL ] ; then
    defstr __str_172 "__t"
    _wrap_str_lit __t1 $__str_172
    _get_val __t2 $ident
    _wrap_int __t2 $__t2
    _string_concat $1 $__t1 $__t2
  elif [ $op = $_IDENTIFIER_STRING ] ; then
    defstr __str_173 "__str_"
    _wrap_str_lit __t1 $__str_173
    _get_val __t2 $ident
    _wrap_int __t2 $__t2
    _string_concat $1 $__t1 $__t2
  elif [ $op = $_IDENTIFIER_DOLLAR ] ; then
    _get_val i $ident
    if [ $prefixed_with_dollar != 0 ] ; then
      if [ $i -le 9 ] ; then
        _wrap_int $1 $i
      else
        _wrap_int __t1 $i
        _string_concat3 $1 $((-__LBRACE__)) $__t1 $((-__RBRACE__))
      fi
    else
      if [ $i -le 9 ] ; then
        _wrap_int __t1 $i
        _string_concat $1 $((-__DOLLAR__)) $__t1
      else
        defstr __str_174 "\${"
        _wrap_str_lit __t1 $__str_174
        _wrap_int __t2 $i
        _string_concat3 $1 $__t1 $__t2 $((-__RBRACE__))
      fi
    fi
  else
    defstr __str_175 "format_special_var: unknown identifier type"
    _fatal_error __ $__str_175
    : $(($1 = 0))
  fi
  endlet $1 __t2 __t1 op i prefixed_with_dollar ident
}

: $((__t1 = ident_symbol = 0))
_global_var() { let ident_symbol $2
  let __t1
  _wrap_str_pool __t1 $ident_symbol
  _string_concat $1 $((-__UNDERSCORE__)) $__t1
  endlet $1 __t1 ident_symbol
}

: $((ident_symbol = 0))
_local_var() { let ident_symbol $2
  if [ $ident_symbol = $_ARGV_ID ] ; then
    defstr __str_88 "argv_"
    _wrap_str_lit $1 $__str_88
  else
    _wrap_str_pool $1 $ident_symbol
  fi
  endlet $1 ident_symbol
}

: $((__t1 = prefixed_with_dollar = binding = ident_symbol = 0))
_local_var_or_param() { let ident_symbol $2; let binding $3; let prefixed_with_dollar $4
  let __t1
  if [ $((_$((_heap + binding + 1)))) = $_BINDING_PARAM_LOCAL ] && { _is_constant_type __t1 $((_$((_heap + binding + 4)))); [ $__t1 != 0 ]; } ; then
    if [ $prefixed_with_dollar != 0 ] ; then
      _wrap_int $1 $((_$((_heap + binding + 3))))
    else
      _wrap_int __t1 $((_$((_heap + binding + 3))))
      _string_concat $1 $((-__DOLLAR__)) $__t1
    fi
  else
    _local_var $1 $ident_symbol
  fi
  endlet $1 __t1 prefixed_with_dollar binding ident_symbol
}

: $((__t1 = ident_symbol = binding = prefixed_with_dollar = ident = 0))
_env_var_with_prefix() { let ident $2; let prefixed_with_dollar $3
  let binding; let ident_symbol; let __t1
  if _get_op __t1 $ident; [ $__t1 = $_IDENTIFIER ] ; then
    _get_val ident_symbol $ident
    if _cgc_lookup_var binding $ident_symbol $_cgc_locals; [ $binding != 0 ] ; then
      _local_var_or_param $1 $ident_symbol $binding $prefixed_with_dollar
    else
      _global_var $1 $ident_symbol
    fi
  else
    _format_special_var $1 $ident $prefixed_with_dollar
  fi
  endlet $1 __t1 ident_symbol binding prefixed_with_dollar ident
}

: $((__t2 = __t1 = member_name_ident = 0))
_struct_member_var() { let member_name_ident $2
  let __t1; let __t2
  defstr __str_176 "__"
  _wrap_str_lit __t1 $__str_176
  _get_val __t2 $member_name_ident
  _wrap_str_pool __t2 $__t2
  _string_concat $1 $__t1 $__t2
  endlet $1 __t2 __t1 member_name_ident
}

: $((__t2 = __t1 = struct_name_ident = 0))
_struct_sizeof_var() { let struct_name_ident $2
  let __t1; let __t2
  defstr __str_177 "__sizeof__"
  _wrap_str_lit __t1 $__str_177
  _get_val __t2 $struct_name_ident
  _wrap_str_pool __t2 $__t2
  _string_concat $1 $__t1 $__t2
  endlet $1 __t2 __t1 struct_name_ident
}

: $((__t1 = ident_tok = 0))
_function_name() { let ident_tok $2
  let __t1
  _wrap_str_pool __t1 $ident_tok
  _string_concat $1 $((-__UNDERSCORE__)) $__t1
  endlet $1 __t1 ident_tok
}

: $((ix = 0))
_new_dollar_ident() { let ix $2
  if [ $ix -lt 10 ] ; then
    : $(($1 = _$((_preallocated_dollar_idents + ix))))
  else
    _new_ast0 $1 $_IDENTIFIER_DOLLAR $ix
  fi
  endlet $1 ix
}

: $((ix = 0))
_new_fresh_ident() { let ix $2
  if [ $ix -lt 10 ] ; then
    : $(($1 = _$((_preallocated_fresh_idents + ix))))
  else
    _new_ast0 $1 $_IDENTIFIER_INTERNAL $ix
  fi
  endlet $1 ix
}

_fresh_ident() {
  : $((_gensym_ix += 1))
  _fun_gensym_ix=$(((_gensym_ix > _fun_gensym_ix) ? _gensym_ix : _fun_gensym_ix))
  _max_gensym_ix=$(((_gensym_ix > _max_gensym_ix) ? _gensym_ix : _max_gensym_ix))
  _new_fresh_ident $1 $_gensym_ix
}

: $((index = string_symbol = 0))
_fresh_string_ident() { let string_symbol $2
  let index
  _symbol_defstr_index index $string_symbol
  if [ $index = 0 ] ; then
    _set_symbol_defstr_index __ $string_symbol $((_string_counter += 1))
    index=$_string_counter
  fi
  _new_ast0 $1 $_IDENTIFIER_STRING $((index - 1))
  endlet $1 index string_symbol
}

: $((__t1 = ident_symbol = kind = decl = 0))
_add_var_to_local_env() { let decl $2; let kind $3
  let ident_symbol; let __t1
  _get_child __t1 $decl 0
  _get_val ident_symbol $__t1
  if _cgc_lookup_var __t1 $ident_symbol $_cgc_locals; [ $__t1 != 0 ] ; then
    defstr __str_178 "Local variable shadowing is not supported."
    _fatal_error __ $__str_178
  fi
  _get_child __t1 $decl 1
  _cgc_add_local_var __ $kind $ident_symbol $__t1
  endlet $1 __t1 ident_symbol kind decl
}

: $((__t1 = type = name = ident_symbol = local = variable = 0))
_assert_var_decl_is_safe() { let variable $2; let local $3
  let ident_symbol; let name; let type; let __t1
  _get_child __t1 $variable 0
  _get_val ident_symbol $__t1
  _symbol_buf name $ident_symbol
  _get_child type $variable 1
  if [ $((_$((name + 0)))) = $__UNDERSCORE__ ] ; then
    defstr __str_179 "variable name is invalid. It can't start with '_'."
    _fatal_error __ $__str_179
  fi
  if [ $local != 0 ] && { [ $ident_symbol = $_ARGV__ID ] || [ $ident_symbol = $_ENV_ID ] || [ $ident_symbol = $_HOME_ID ] || [ $ident_symbol = $_IFS_ID ] || [ $ident_symbol = $_LANG_ID ] || [ $ident_symbol = $_LC_ALL_ID ] || [ $ident_symbol = $_LC_COLLATE_ID ] || [ $ident_symbol = $_LC_CTYPE_ID ] || [ $ident_symbol = $_LC_MESSAGES_ID ] || [ $ident_symbol = $_LINENO_ID ] || [ $ident_symbol = $_NLSPATH_ID ] || [ $ident_symbol = $_PATH_ID ] || [ $ident_symbol = $_PPID_ID ] || [ $ident_symbol = $_PS1_ID ] || [ $ident_symbol = $_PS4_ID ] || [ $ident_symbol = $_PWD_ID ]; } ; then
    defstr __str_180 "variable name is reserved by the shell and can't be used as a local variable."
    _fatal_error __ $__str_180
  fi
  if [ $local != 0 ] ; then
    if { _get_op __t1 $type; [ $__t1 = $__LBRACK__ ]; } || { _get_op __t1 $type; [ $__t1 = $_STRUCT_KW ]; } ; then
      defstr __str_181 "local array/struct value type is not supported for shell backend. Use a reference type instead."
      _fatal_error __ $__str_181
    fi
  else
    if { { _get_op __t1 $type; [ $__t1 = $__LBRACK__ ]; } && { _get_child __t1 $type 0; _get_op __t1 $__t1; [ $__t1 = $__LBRACK__ ]; }; } || { { _get_op __t1 $type; [ $__t1 = $__LBRACK__ ]; } && { _get_child __t1 $type 0; _get_op __t1 $__t1; [ $__t1 = $_STRUCT_KW ]; }; } || { _get_op __t1 $type; [ $__t1 = $_STRUCT_KW ]; } ; then
      defstr __str_182 "global array of struct and struct value type are not supported in shell backend. Use a reference type instead."
      _fatal_error __ $__str_182
    fi
  fi
  endlet $1 __t1 type name ident_symbol local variable
}

: $((decl = lst = 0))
_handle_function_params() { let lst $2
  let decl
  while [ $lst != 0 ]; do
    _car decl $lst
    _assert_var_decl_is_safe __ $decl 1
    _add_var_to_local_env __ $decl $_BINDING_PARAM_LOCAL
    _cdr lst $lst
  done
  endlet $1 decl lst
}

: $((__t2 = __t1 = sep_str = let_str = params_ix = res = decl = ident = params = 0))
_let_params() { let params $2
  let ident; let decl; let res; let params_ix; let let_str; let sep_str; let __t1; let __t2
  res=0
  params_ix=2
  defstr __str_183 "let "
  _wrap_str_lit let_str $__str_183
  defstr __str_171 "; "
  _wrap_str_lit sep_str $__str_171
  while [ $params != 0 ]; do
    _car decl $params
    if _get_child __t1 $decl 1; _is_constant_type __t1 $__t1; [ $((!__t1)) != 0 ] ; then
      _get_child __t1 $decl 0
      _get_val ident $__t1
      _local_var __t1 $ident
      _new_dollar_ident __t2 $params_ix
      _format_special_var __t2 $__t2 0
      _string_concat4 __t1 $let_str $__t1 $((-__SPACE__)) $__t2
      _concatenate_strings_with res $res $__t1 $sep_str
    fi
    _cdr params $params
    : $((params_ix += 1))
  done
  _runtime_use_local_vars=$((_runtime_use_local_vars | (res != 0)))
  if [ $res != 0 ] ; then
    _string_concat res $((-__SPACE__)) $res
  fi
  : $(($1 = res))
  endlet $1 __t2 __t1 sep_str let_str params_ix res decl ident params
}

: $((__t1 = res = sep_str = let_str = counter = ident = env = 0))
_save_local_vars() {
  let env; let ident; let counter; let let_str; let sep_str; let res; let __t1
  env=$_cgc_locals_fun
  counter=$_fun_gensym_ix
  defstr __str_183 "let "
  _wrap_str_lit let_str $__str_183
  defstr __str_171 "; "
  _wrap_str_lit sep_str $__str_171
  res=0
  while [ $counter -gt 0 ]; do
    _new_fresh_ident ident $counter
    _format_special_var __t1 $ident 1
    _string_concat __t1 $let_str $__t1
    _concatenate_strings_with res $__t1 $res $sep_str
    : $((counter -= 1))
  done
  while [ $env != 0 ]; do
    if [ $((_$((_heap + env + 1)))) != $_BINDING_PARAM_LOCAL ] ; then
      ident=$((_$((_heap + env + 2))))
      _local_var __t1 $ident
      _string_concat __t1 $let_str $__t1
      _concatenate_strings_with res $__t1 $res $sep_str
    fi
    env=$((_$((_heap + env))))
  done
  _runtime_use_local_vars=$((_runtime_use_local_vars | (res != 0)))
  : $(($1 = res))
  endlet $1 __t1 res sep_str let_str counter ident env
}

: $((__t1 = counter = res = ident = env = params_count = 0))
_restore_local_vars() { let params_count $2
  let env; let ident; let res; let counter; let __t1
  env=$_cgc_locals_fun
  res=0
  counter=$_fun_gensym_ix
  while [ $counter -gt 0 ]; do
    _new_fresh_ident ident $counter
    _format_special_var __t1 $ident 0
    _concatenate_strings_with res $res $__t1 $((-__SPACE__))
    : $((counter -= 1))
  done
  while [ $env != 0 ]; do
    ident=$((_$((_heap + env + 2))))
    if [ $((_$((_heap + env + 1)))) != $_BINDING_PARAM_LOCAL ] || { _is_constant_type __t1 $((_$((_heap + env + 4)))); [ $((!__t1)) != 0 ]; } ; then
      _local_var __t1 $ident
      _concatenate_strings_with res $res $__t1 $((-__SPACE__))
    fi
    env=$((_$((_heap + env))))
  done
  if [ $res != 0 ] ; then
    _runtime_use_local_vars=1
    defstr __str_184 "endlet \$1 "
    _wrap_str_lit __t1 $__str_184
    _string_concat $1 $__t1 $res
  else
    : $(($1 = 0))
  fi
  endlet $1 __t1 counter res ident env params_count
}

: $((op = 0))
_op_to_str() { let op $2
  if [ 32 -lt $op ] && [ $op -lt 127 ] ; then
    _string_concat3 $1 $((-__SPACE__)) $((- op)) $((-__SPACE__))
  elif [ $op = $_AMP_AMP ] ; then
    defstr __str_185 " && "
    _wrap_str_lit $1 $__str_185
  elif [ $op = $_AMP_EQ ] ; then
    defstr __str_186 " &= "
    _wrap_str_lit $1 $__str_186
  elif [ $op = $_BAR_BAR ] ; then
    defstr __str_187 " || "
    _wrap_str_lit $1 $__str_187
  elif [ $op = $_BAR_EQ ] ; then
    defstr __str_188 " |= "
    _wrap_str_lit $1 $__str_188
  elif [ $op = $_CARET_EQ ] ; then
    defstr __str_189 " ^= "
    _wrap_str_lit $1 $__str_189
  elif [ $op = $_EQ_EQ ] ; then
    defstr __str_190 " == "
    _wrap_str_lit $1 $__str_190
  elif [ $op = $_GT_EQ ] ; then
    defstr __str_191 " >= "
    _wrap_str_lit $1 $__str_191
  elif [ $op = $_LSHIFT_EQ ] ; then
    defstr __str_192 " <<= "
    _wrap_str_lit $1 $__str_192
  elif [ $op = $_LT_EQ ] ; then
    defstr __str_193 " <= "
    _wrap_str_lit $1 $__str_193
  elif [ $op = $_LSHIFT ] ; then
    defstr __str_194 " << "
    _wrap_str_lit $1 $__str_194
  elif [ $op = $_MINUS_EQ ] ; then
    defstr __str_195 " -= "
    _wrap_str_lit $1 $__str_195
  elif [ $op = $_EXCL_EQ ] ; then
    defstr __str_196 " != "
    _wrap_str_lit $1 $__str_196
  elif [ $op = $_PERCENT_EQ ] ; then
    defstr __str_197 " %= "
    _wrap_str_lit $1 $__str_197
  elif [ $op = $_PLUS_EQ ] ; then
    defstr __str_198 " += "
    _wrap_str_lit $1 $__str_198
  elif [ $op = $_RSHIFT_EQ ] ; then
    defstr __str_199 " >>= "
    _wrap_str_lit $1 $__str_199
  elif [ $op = $_RSHIFT ] ; then
    defstr __str_200 " >> "
    _wrap_str_lit $1 $__str_200
  elif [ $op = $_SLASH_EQ ] ; then
    defstr __str_201 " /= "
    _wrap_str_lit $1 $__str_201
  elif [ $op = $_STAR_EQ ] ; then
    defstr __str_202 " *= "
    _wrap_str_lit $1 $__str_202
  else
    defstr __str_203 "op_to_str: unexpected operator"
    _fatal_error __ $__str_203
    : $(($1 = 0))
  fi
  endlet $1 op
}

: $((op = 0))
_test_op_to_str() { let op $2
  if [ $op = $_EQ_EQ ] ; then
    defstr __str_204 " = "
    _wrap_str_lit $1 $__str_204
  elif [ $op = $_EXCL_EQ ] ; then
    defstr __str_196 " != "
    _wrap_str_lit $1 $__str_196
  elif [ $op = $__LT__ ] ; then
    defstr __str_205 " -lt "
    _wrap_str_lit $1 $__str_205
  elif [ $op = $__GT__ ] ; then
    defstr __str_206 " -gt "
    _wrap_str_lit $1 $__str_206
  elif [ $op = $_LT_EQ ] ; then
    defstr __str_207 " -le "
    _wrap_str_lit $1 $__str_207
  elif [ $op = $_GT_EQ ] ; then
    defstr __str_208 " -ge "
    _wrap_str_lit $1 $__str_208
  else
    defstr __str_209 "test_op_to_str: unexpected operator"
    _fatal_error __ $__str_209
    : $(($1 = 0))
  fi
  endlet $1 op
}

: $((str = res = c = 0))
_character_ident() { let c $2
  let res; let str
  res=0
  : $((_$((_characters_useds + c / 16)) = _$((_characters_useds + (c / 16))) | (1 << (c % 16))))
  _any_character_used=1
  if { [ $__A__ -le $c ] && [ $c -le $__Z__ ]; } || { [ $__a__ -le $c ] && [ $c -le $__z__ ]; } || { [ $__0__ -le $c ] && [ $c -le $__9__ ]; } ; then
    res=$((- c))
  elif [ $c -lt 32 ] ; then
    defstr __str_210 "NUL\0SOH\0STX\0ETX\0EOT\0ENQ\0ACK\0BEL\0BS\0\0HT\0\0LF\0\0VT\0\0FF\0\0CR\0\0SO\0\0SI\0\0DLE\0DC1\0DC2\0DC3\0DC4\0NAK\0SYN\0ETB\0CAN\0EM\0\0SUB\0ESC\0FS\0\0GS\0\0RS\0\0US\0\0"
    str=$__str_210
    _wrap_str_lit res $((str + (c * 4)))
  elif [ $c -lt $__0__ ] ; then
    defstr __str_211 "SPACE\0\0\0EXCL\0\0\0\0DQUOTE\0\0HASH\0\0\0\0DOLLAR\0\0PERCENT\0AMP\0\0\0\0\0QUOTE\0\0\0LPAREN\0\0RPAREN\0\0STAR\0\0\0\0PLUS\0\0\0\0COMMA\0\0\0MINUS\0\0\0PERIOD\0\0SLASH\0\0\0"
    str=$__str_211
    _wrap_str_lit res $((str + ((c - __SPACE__) * 8)))
  elif [ $c -le $__A__ ] ; then
    defstr __str_212 "COLON\0\0\0\0\0SEMICOLON\0LT\0\0\0\0\0\0\0\0EQ\0\0\0\0\0\0\0\0GT\0\0\0\0\0\0\0\0QUESTION\0\0AT\0\0\0\0\0\0\0\0"
    str=$__str_212
    _wrap_str_lit res $((str + ((c - __COLON__) * 10)))
  elif [ $c -le $__a__ ] ; then
    defstr __str_213 "LBRACK\0\0\0\0\0BACKSLASH\0\0RBRACK\0\0\0\0\0CARET\0\0\0\0\0\0UNDERSCORE\0BACKTICK\0\0\0"
    str=$__str_213
    _wrap_str_lit res $((str + ((c - __LBRACK__) * 11)))
  elif [ $c -le 127 ] ; then
    defstr __str_214 "LBRACE\0BAR\0\0\0\0RBRACE\0TILDE\0\0DEL\0\0\0\0"
    str=$__str_214
    _wrap_str_lit res $((str + ((c - __LBRACE__) * 7)))
  else
    defstr __str_215 "character_ident: invalid character"
    _fatal_error __ $__str_215
  fi
  _string_concat5 $1 $((-__UNDERSCORE__)) $((-__UNDERSCORE__)) $res $((-__UNDERSCORE__)) $((-__UNDERSCORE__))
  endlet $1 str res c
}

_replaced_fun_calls=0
_replaced_fun_calls_tail=0
_conditional_fun_calls=0
_conditional_fun_calls_tail=0
_literals_inits=0
_literals_inits_tail=0
_contains_side_effects=0
: $((__t1 = sub1 = start_gensym_ix = executes_conditionally = assign_to = node = 0))
_handle_fun_call_side_effect() { let node $2; let assign_to $3; let executes_conditionally $4
  let start_gensym_ix; let sub1; let __t1
  start_gensym_ix=$_gensym_ix
  if [ $assign_to = 0 ] ; then
    _fresh_ident assign_to
    start_gensym_ix=$_gensym_ix
    : $((_gensym_ix -= 1))
  fi
  _get_child sub1 $node 1
  while [ $sub1 != 0 ]; do
    _car __t1 $sub1
    _handle_side_effects_go __t1 $__t1 $executes_conditionally
    _set_child __ $sub1 0 $__t1
    _cdr sub1 $sub1
  done
  _gensym_ix=$start_gensym_ix
  _new_ast2 __t1 $__EQ__ $assign_to $node
  _cons sub1 $__t1 0
  if [ $executes_conditionally != 0 ] ; then
    if [ $_conditional_fun_calls = 0 ] ; then
      _conditional_fun_calls=$sub1
    else
      _set_child __ $_conditional_fun_calls_tail 1 $sub1
    fi
    _conditional_fun_calls_tail=$sub1
  else
    if [ $_replaced_fun_calls = 0 ] ; then
      _replaced_fun_calls=$sub1
    else
      _set_child __ $_replaced_fun_calls_tail 1 $sub1
    fi
    _replaced_fun_calls_tail=$sub1
  fi
  : $(($1 = assign_to))
  endlet $1 __t1 sub1 start_gensym_ix executes_conditionally assign_to node
}

: $((__t1 = child2 = child1 = child0 = start_gensym_ix = right_conditional_fun_calls = left_conditional_fun_calls = previous_conditional_fun_calls = sub2 = sub1 = nb_children = op = executes_conditionally = node = 0))
_handle_side_effects_go() { let node $2; let executes_conditionally $3
  let op; let nb_children; let sub1; let sub2; let previous_conditional_fun_calls; let left_conditional_fun_calls; let right_conditional_fun_calls; let start_gensym_ix; let child0; let child1; let child2; let __t1
  _get_op op $node
  _get_nb_children nb_children $node
  start_gensym_ix=$_gensym_ix
  if [ $nb_children -ge 1 ] ; then
    _get_child child0 $node 0
  fi
  if [ $nb_children -ge 2 ] ; then
    _get_child child1 $node 1
  fi
  if [ $nb_children -ge 3 ] ; then
    _get_child child2 $node 2
  fi
  if [ $nb_children = 0 ] ; then
    if [ $op = $_IDENTIFIER ] || [ $op = $_IDENTIFIER_INTERNAL ] || [ $op = $_IDENTIFIER_STRING ] || [ $op = $_IDENTIFIER_DOLLAR ] || [ $op = $_CHARACTER ] || [ $op = $_INTEGER ] || [ $op = $_INTEGER_HEX ] || [ $op = $_INTEGER_OCT ] ; then
      : $(($1 = node))
    elif [ $op = $_STRING ] ; then
      _get_val __t1 $node
      _fresh_string_ident sub2 $__t1
      _get_val __t1 $node
      _new_ast2 sub1 $__EQ__ $sub2 $__t1
      _cons sub1 $sub1 0
      if [ $_literals_inits = 0 ] ; then
        _literals_inits=$sub1
      else
        _set_child __ $_literals_inits_tail 1 $sub1
      fi
      _literals_inits_tail=$sub1
      : $(($1 = sub2))
    else
      defstr __str_216 "unexpected operator"
      _fatal_error __ $__str_216
      : $(($1 = 0))
    fi
  elif [ $nb_children = 1 ] ; then
    if [ $op = $__AMP__ ] || [ $op = $__STAR__ ] || [ $op = $__PLUS__ ] || [ $op = $__MINUS__ ] || [ $op = $__TILDE__ ] || [ $op = $__EXCL__ ] ; then
      _handle_side_effects_go __t1 $child0 $executes_conditionally
      _new_ast1 $1 $op $__t1
    elif [ $op = $_PLUS_PLUS_PRE ] || [ $op = $_MINUS_MINUS_PRE ] || [ $op = $_PLUS_PLUS_POST ] || [ $op = $_MINUS_MINUS_POST ] ; then
      _contains_side_effects=1
      _handle_side_effects_go __t1 $child0 $executes_conditionally
      _new_ast1 $1 $op $__t1
    elif [ $op = $_SIZEOF_KW ] ; then
      : $(($1 = node))
    else
      defstr __str_216 "unexpected operator"
      _fatal_error __ $__str_216
      : $(($1 = 0))
    fi
  elif [ $nb_children = 2 ] ; then
    if [ $op = $__LPAREN__ ] ; then
      _handle_fun_call_side_effect $1 $node 0 $executes_conditionally
    elif [ $op = $__EQ__ ] ; then
      if _get_op __t1 $child1; [ $__t1 = $__LPAREN__ ] ; then
        _handle_fun_call_side_effect $1 $child1 $child0 $executes_conditionally
      else
        _handle_side_effects_go sub1 $child0 $executes_conditionally
        _handle_side_effects_go sub2 $child1 $executes_conditionally
        _new_ast2 $1 $op $sub1 $sub2
      fi
    elif [ $op = $__AMP__ ] || [ $op = $__BAR__ ] || [ $op = $__LT__ ] || [ $op = $__GT__ ] || [ $op = $__PLUS__ ] || [ $op = $__MINUS__ ] || [ $op = $__STAR__ ] || [ $op = $__SLASH__ ] || [ $op = $__PERCENT__ ] || [ $op = $__CARET__ ] || [ $op = $__COMMA__ ] || [ $op = $_EQ_EQ ] || [ $op = $_EXCL_EQ ] || [ $op = $_LT_EQ ] || [ $op = $_GT_EQ ] || [ $op = $_LSHIFT ] || [ $op = $_RSHIFT ] || [ $op = $__LBRACK__ ] || [ $op = $__PERIOD__ ] || [ $op = $_ARROW ] ; then
      _handle_side_effects_go sub1 $child0 $executes_conditionally
      _handle_side_effects_go sub2 $child1 $executes_conditionally
      _new_ast2 $1 $op $sub1 $sub2
    elif [ $op = $_AMP_EQ ] || [ $op = $_BAR_EQ ] || [ $op = $_CARET_EQ ] || [ $op = $_LSHIFT_EQ ] || [ $op = $_MINUS_EQ ] || [ $op = $_PERCENT_EQ ] || [ $op = $_PLUS_EQ ] || [ $op = $_RSHIFT_EQ ] || [ $op = $_SLASH_EQ ] || [ $op = $_STAR_EQ ] ; then
      _contains_side_effects=1
      _handle_side_effects_go sub1 $child0 $executes_conditionally
      _handle_side_effects_go sub2 $child1 $executes_conditionally
      _new_ast2 $1 $op $sub1 $sub2
    elif [ $op = $_AMP_AMP ] || [ $op = $_BAR_BAR ] ; then
      previous_conditional_fun_calls=$_conditional_fun_calls
      _conditional_fun_calls=0
      _handle_side_effects_go sub1 $child0 1
      _gensym_ix=$start_gensym_ix
      left_conditional_fun_calls=$_conditional_fun_calls
      _conditional_fun_calls=0
      _handle_side_effects_go sub2 $child1 1
      _gensym_ix=$start_gensym_ix
      right_conditional_fun_calls=$_conditional_fun_calls
      _conditional_fun_calls=$previous_conditional_fun_calls
      _new_ast4 $1 $op $sub1 $sub2 $left_conditional_fun_calls $right_conditional_fun_calls
    elif [ $op = $_CAST ] ; then
      _handle_side_effects_go __t1 $child1 $executes_conditionally
      _new_ast2 $1 $_CAST $child0 $__t1
    else
      defstr __str_216 "unexpected operator"
      _fatal_error __ $__str_216
      : $(($1 = 0))
    fi
  elif [ $nb_children = 3 ] && [ $op = $__QUESTION__ ] ; then
    previous_conditional_fun_calls=$_conditional_fun_calls
    _conditional_fun_calls=0
    _handle_side_effects_go sub1 $child1 1
    left_conditional_fun_calls=$_conditional_fun_calls
    _conditional_fun_calls=0
    _handle_side_effects_go sub2 $child2 1
    right_conditional_fun_calls=$_conditional_fun_calls
    if [ $left_conditional_fun_calls != 0 ] || [ $right_conditional_fun_calls != 0 ] ; then
      defstr __str_217 "Conditional function calls in ternary operator not allowed"
      _fatal_error __ $__str_217
    fi
    _handle_side_effects_go __t1 $child0 $executes_conditionally
    _new_ast3 $1 $__QUESTION__ $__t1 $sub1 $sub2
  else
    defstr __str_216 "unexpected operator"
    _fatal_error __ $__str_216
    : $(($1 = 0))
  fi
  endlet $1 __t1 child2 child1 child0 start_gensym_ix right_conditional_fun_calls left_conditional_fun_calls previous_conditional_fun_calls sub2 sub1 nb_children op executes_conditionally node
}

: $((node = 0))
_handle_side_effects() { let node $2
  _replaced_fun_calls=0
  _conditional_fun_calls=0
  _literals_inits=0
  _contains_side_effects=0
  _handle_side_effects_go $1 $node 0
  endlet $1 node
}

: $((__t4 = __t3 = __t2 = __t1 = array_size_text = string_end = string_start = array_size = string_symbol = ident = 0))
_comp_defstr() { let ident $2; let string_symbol $3; let array_size $4
  let string_start; let string_end; let array_size_text; let __t1; let __t2; let __t3; let __t4
  _symbol_buf string_start $string_symbol
  _symbol_buf_end string_end $string_symbol
  array_size_text=0
  if [ $array_size != -1 ] ; then
    _wrap_int __t1 $array_size
    _string_concat array_size_text $((-__SPACE__)) $__t1
  fi
  if [ $_nest_level = 0 ] ; then
    _runtime_defstr __
  else
    _runtime_use_defstr=1
  fi
  defstr __str_218 "defstr "
  defstr __str_219 " \""
  _wrap_str_lit __t1 $__str_218
  _env_var_with_prefix __t2 $ident 0
  _wrap_str_lit __t3 $__str_219
  _wrap_str_imm __t4 $string_start $string_end
  _escape_text __t4 $__t4 0
  _string_concat3 __t3 $__t3 $__t4 $((-__DQUOTE__))
  _string_concat4 __t1 $__t1 $__t2 $__t3 $array_size_text
  _append_glo_decl __ $__t1
  endlet $1 __t4 __t3 __t2 __t1 array_size_text string_end string_start array_size string_symbol ident
}

: $((res = node = 0))
_initializer_list_len() { let node $2
  let res
  res=0
  while [ $node != 0 ]; do
    : $((res += 1))
    _cdr node $node
  done
  : $(($1 = res))
  endlet $1 res node
}

: $((__t1 = op = str_ident = element = args = expected_len = initializer_list = 0))
_comp_initializer_list() { let initializer_list $2; let expected_len $3
  let args; let element; let str_ident; let op; let __t1
  args=0
  _runtime_use_initialize=1
  while [ $initializer_list != 0 ]; do
    _car element $initializer_list
    _get_op op $element
    if [ $op = $_INTEGER ] ; then
      _get_val __t1 $element
      _wrap_int __t1 $((-__t1))
      _concatenate_strings_with args $args $__t1 $((-__SPACE__))
    elif [ $op = $_CHARACTER ] ; then
      _get_val __t1 $element
      _wrap_int __t1 $__t1
      _concatenate_strings_with args $args $__t1 $((-__SPACE__))
    elif [ $op = $_STRING ] ; then
      _get_val __t1 $element
      _fresh_string_ident str_ident $__t1
      _get_val __t1 $element
      _comp_defstr __ $str_ident $__t1 -1
      _format_special_var __t1 $str_ident 1
      _string_concat __t1 $((-__DOLLAR__)) $__t1
      _concatenate_strings_with args $args $__t1 $((-__SPACE__))
    else
      defstr __str_220 "comp_initializer: unexpected operator"
      _fatal_error __ $__str_220
    fi
    _cdr initializer_list $initializer_list
  done
  : $(($1 = args))
  endlet $1 __t1 op str_ident element args expected_len initializer_list
}

#_ VALUE_CTX enum declaration
readonly _RVALUE_CTX_BASE=0
readonly _RVALUE_CTX_ARITH_EXPANSION=1
readonly _RVALUE_CTX_TEST=2
readonly _RVALUE_CTX_TEST_ELSEIF=3
: $((__t2 = __t1 = side_effect = test_side_effects_code = code = test_side_effects = 0))
_with_prefixed_side_effects() { let test_side_effects $2; let code $3
  let test_side_effects_code; let side_effect; let __t1; let __t2
  test_side_effects_code=0
  while [ $test_side_effects != 0 ]; do
    _car side_effect $test_side_effects
    _get_child __t1 $side_effect 1
    _get_child __t2 $side_effect 0
    _comp_fun_call_code __t1 $__t1 $__t2
    defstr __str_171 "; "
    _wrap_str_lit __t2 $__str_171
    _string_concat3 test_side_effects_code $test_side_effects_code $__t1 $__t2
    _cdr test_side_effects $test_side_effects
  done
  if [ $test_side_effects_code != 0 ] ; then
    defstr __str_221 "{ "
    _wrap_str_lit __t1 $__str_221
    defstr __str_222 "; }"
    _wrap_str_lit __t2 $__str_222
    _string_concat4 $1 $__t1 $test_side_effects_code $code $__t2
  else
    : $(($1 = code))
  fi
  endlet $1 __t2 __t1 side_effect test_side_effects_code code test_side_effects
}

: $((op = 0))
_is_associative_operator() { let op $2
  : $(($1 = (op == __PLUS__) | (op == __STAR__) | (op == __AMP__) | (op == __BAR__) | (op == __CARET__) | (op == _EQ_EQ) | (op == _AMP_AMP) | (op == _BAR_BAR)))
  endlet $1 op
}

: $((__t2 = __t1 = inner_op = outer_op = code = test_side_effects = context = parens_otherwise = 0))
_wrap_if_needed() { let parens_otherwise $2; let context $3; let test_side_effects $4; let code $5; let outer_op $6; let inner_op $7
  let __t1; let __t2
  if [ $context = $_RVALUE_CTX_ARITH_EXPANSION ] ; then
    if [ $parens_otherwise != 0 ] && [ $outer_op != 0 ] && [ $outer_op != $__EQ__ ] && { { _is_associative_operator __t1 $inner_op; [ $((!__t1)) != 0 ]; } || [ $inner_op != $outer_op ]; } ; then
      _string_concat3 $1 $((-__LPAREN__)) $code $((-__RPAREN__))
    else
      : $(($1 = code))
    fi
  elif [ $context = $_RVALUE_CTX_TEST ] ; then
    defstr __str_223 "[ \$(("
    defstr __str_224 ")) != 0 ]"
    _wrap_str_lit __t1 $__str_223
    _wrap_str_lit __t2 $__str_224
    _string_concat3 __t1 $__t1 $code $__t2
    _with_prefixed_side_effects $1 $test_side_effects $__t1
  else
    defstr __str_225 "\$(("
    _wrap_str_lit __t1 $__str_225
    defstr __str_226 "))"
    _wrap_str_lit __t2 $__str_226
    _string_concat3 $1 $__t1 $code $__t2
  fi
  endlet $1 __t2 __t1 inner_op outer_op code test_side_effects context parens_otherwise
}

: $((__t2 = __t1 = code = test_side_effects = context = 0))
_wrap_in_condition_if_needed() { let context $2; let test_side_effects $3; let code $4
  let __t1; let __t2
  if [ $context = $_RVALUE_CTX_TEST ] ; then
    defstr __str_227 "[ "
    defstr __str_228 " != 0 ]"
    _wrap_str_lit __t1 $__str_227
    _wrap_str_lit __t2 $__str_228
    _string_concat3 __t1 $__t1 $code $__t2
    _with_prefixed_side_effects $1 $test_side_effects $__t1
  else
    : $(($1 = code))
  fi
  endlet $1 __t2 __t1 code test_side_effects context
}

: $((__t3 = __t2 = __t1 = child3 = child2 = child1 = child0 = sub3 = sub2 = sub1 = nb_children = op = outer_op = test_side_effects = context = node = 0))
_comp_rvalue_go() { let node $2; let context $3; let test_side_effects $4; let outer_op $5
  let op; let nb_children; let sub1; let sub2; let sub3; let child0; let child1; let child2; let child3; let __t1; let __t2; let __t3
  _get_op op $node
  _get_nb_children nb_children $node
  if [ $nb_children -ge 1 ] ; then
    _get_child child0 $node 0
  fi
  if [ $nb_children -ge 2 ] ; then
    _get_child child1 $node 1
  fi
  if [ $nb_children -ge 3 ] ; then
    _get_child child2 $node 2
  fi
  if [ $nb_children -ge 4 ] ; then
    _get_child child3 $node 3
  fi
  if [ $nb_children = 0 ] ; then
    if [ $op = $_INTEGER ] ; then
      _get_val __t1 $node
      _wrap_int __t1 $((-__t1))
      _wrap_in_condition_if_needed $1 $context $test_side_effects $__t1
    elif [ $op = $_INTEGER_HEX ] || [ $op = $_INTEGER_OCT ] ; then
      _wrap_integer __t1 1 $node
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $_CHARACTER ] ; then
      if [ $context = $_RVALUE_CTX_ARITH_EXPANSION ] ; then
        _get_val __t1 $node
        _character_ident $1 $__t1
      else
        _get_val __t1 $node
        _character_ident __t1 $__t1
        _string_concat __t1 $((-__DOLLAR__)) $__t1
        _wrap_in_condition_if_needed $1 $context $test_side_effects $__t1
      fi
    elif [ $op = $_IDENTIFIER ] || [ $op = $_IDENTIFIER_INTERNAL ] || [ $op = $_IDENTIFIER_STRING ] || [ $op = $_IDENTIFIER_DOLLAR ] ; then
      if [ $context = $_RVALUE_CTX_ARITH_EXPANSION ] ; then
        _env_var_with_prefix $1 $node 0
      else
        _env_var_with_prefix __t1 $node 1
        _string_concat __t1 $((-__DOLLAR__)) $__t1
        _wrap_in_condition_if_needed $1 $context $test_side_effects $__t1
      fi
    else
      defstr __str_229 "comp_rvalue_go: unexpected operator"
      _fatal_error __ $__str_229
      : $(($1 = 0))
    fi
  elif [ $nb_children = 1 ] ; then
    if [ $op = $__STAR__ ] ; then
      _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_BASE 0 $op
      _string_concat __t1 $((-__UNDERSCORE__)) $sub1
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $__PLUS__ ] ; then
      _comp_rvalue_go $1 $child0 $context $test_side_effects $outer_op
    elif [ $op = $__MINUS__ ] || [ $op = $__TILDE__ ] || [ $op = $__EXCL__ ] ; then
      if [ $op = $__MINUS__ ] && { { _get_op __t1 $child0; [ $__t1 = $_INTEGER ]; } || [ $op = $_INTEGER_HEX ] || [ $op = $_INTEGER_OCT ]; } ; then
        _wrap_integer __t1 -1 $child0
        _wrap_in_condition_if_needed $1 $context $test_side_effects $__t1
      elif _get_op __t2 $child0; [ $__t2 = $_IDENTIFIER ] ; then
        _env_var_with_prefix __t1 $child0 0
        _string_concat3 __t1 $((- op)) $((-__SPACE__)) $__t1
        _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
      else
        _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
        _string_concat __t1 $((- op)) $sub1
        _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
      fi
    elif [ $op = $_MINUS_MINUS_PRE ] ; then
      _comp_lvalue sub1 $child0
      defstr __str_230 " -= 1"
      _wrap_str_lit __t1 $__str_230
      _string_concat __t1 $sub1 $__t1
      _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $_PLUS_PLUS_PRE ] ; then
      _comp_lvalue sub1 $child0
      defstr __str_231 " += 1"
      _wrap_str_lit __t1 $__str_231
      _string_concat __t1 $sub1 $__t1
      _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $_MINUS_MINUS_POST ] ; then
      _comp_lvalue sub1 $child0
      defstr __str_232 " -= 1)"
      defstr __str_233 " + 1"
      _wrap_str_lit __t1 $__str_232
      _wrap_str_lit __t2 $__str_233
      _string_concat4 __t1 $((-__LPAREN__)) $sub1 $__t1 $__t2
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $__PLUS__
    elif [ $op = $_PLUS_PLUS_POST ] ; then
      _comp_lvalue sub1 $child0
      defstr __str_234 " += 1)"
      defstr __str_235 " - 1"
      _wrap_str_lit __t1 $__str_234
      _wrap_str_lit __t2 $__str_235
      _string_concat4 __t1 $((-__LPAREN__)) $sub1 $__t1 $__t2
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $__MINUS__
    elif [ $op = $_SIZEOF_KW ] ; then
      if _get_op __t1 $child0; [ $__t1 = $_DECL ] ; then
        _get_child child0 $child0 1
        _get_op op $child0
        if [ $op = $_INT_KW ] || [ $op = $_SHORT_KW ] || [ $op = $_LONG_KW ] || [ $op = $_CHAR_KW ] || [ $op = $_VOID_KW ] || [ $op = $_ENUM_KW ] || [ $op = $__STAR__ ] ; then
          _wrap_int __t1 1
          _wrap_in_condition_if_needed $1 $context $test_side_effects $__t1
        elif [ $op = $_STRUCT_KW ] ; then
          _get_child __t1 $child0 1
          _struct_sizeof_var __t1 $__t1
          _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
        else
          defstr __str_236 "comp_rvalue_go: sizeof is not supported for this type or expression"
          _fatal_error __ $__str_236
          : $(($1 = 0))
        fi
      else
        defstr __str_236 "comp_rvalue_go: sizeof is not supported for this type or expression"
        _fatal_error __ $__str_236
        : $(($1 = 0))
      fi
    elif [ $op = $__AMP__ ] ; then
      _comp_lvalue_address __t1 $child0
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
    else
      defstr __str_229 "comp_rvalue_go: unexpected operator"
      _fatal_error __ $__str_229
      : $(($1 = 0))
    fi
  elif [ $nb_children = 2 ] ; then
    if [ $op = $__PLUS__ ] || [ $op = $__MINUS__ ] || [ $op = $__STAR__ ] || [ $op = $__SLASH__ ] || [ $op = $__PERCENT__ ] || [ $op = $__AMP__ ] || [ $op = $__BAR__ ] || [ $op = $__CARET__ ] || [ $op = $_LSHIFT ] || [ $op = $_RSHIFT ] || [ $op = $__COMMA__ ] ; then
      _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _op_to_str __t1 $op
      _string_concat3 __t1 $sub1 $__t1 $sub2
      _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $__EQ__ ] || [ $op = $_AMP_EQ ] || [ $op = $_BAR_EQ ] || [ $op = $_CARET_EQ ] || [ $op = $_LSHIFT_EQ ] || [ $op = $_MINUS_EQ ] || [ $op = $_PERCENT_EQ ] || [ $op = $_PLUS_EQ ] || [ $op = $_RSHIFT_EQ ] || [ $op = $_SLASH_EQ ] || [ $op = $_STAR_EQ ] ; then
      _comp_lvalue sub1 $child0
      _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _op_to_str __t1 $op
      _string_concat3 __t1 $sub1 $__t1 $sub2
      _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $__LBRACK__ ] ; then
      _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $__PLUS__
      _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $__PLUS__
      defstr __str_237 "_\$(("
      defstr __str_238 " + "
      defstr __str_226 "))"
      _wrap_str_lit __t1 $__str_237
      _wrap_str_lit __t2 $__str_238
      _wrap_str_lit __t3 $__str_226
      _string_concat5 __t1 $__t1 $sub1 $__t2 $sub2 $__t3
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $_ARROW ] ; then
      _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _struct_member_var sub2 $child1
      defstr __str_237 "_\$(("
      defstr __str_238 " + "
      defstr __str_226 "))"
      _wrap_str_lit __t1 $__str_237
      _wrap_str_lit __t2 $__str_238
      _wrap_str_lit __t3 $__str_226
      _string_concat5 __t1 $__t1 $sub1 $__t2 $sub2 $__t3
      _wrap_if_needed $1 0 $context $test_side_effects $__t1 $outer_op $op
    elif [ $op = $_EQ_EQ ] || [ $op = $_EXCL_EQ ] || [ $op = $_LT_EQ ] || [ $op = $_GT_EQ ] || [ $op = $__LT__ ] || [ $op = $__GT__ ] ; then
      if [ $context = $_RVALUE_CTX_TEST ] ; then
        _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_BASE 0 $op
        _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_BASE 0 $op
        defstr __str_227 "[ "
        defstr __str_239 " ]"
        _wrap_str_lit __t1 $__str_227
        _test_op_to_str __t2 $op
        _wrap_str_lit __t3 $__str_239
        _string_concat5 __t1 $__t1 $sub1 $__t2 $sub2 $__t3
        _with_prefixed_side_effects $1 $test_side_effects $__t1
      else
        _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
        _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
        _op_to_str __t1 $op
        _string_concat3 __t1 $sub1 $__t1 $sub2
        _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
      fi
    elif [ $op = $_CAST ] ; then
      _comp_rvalue_go $1 $child1 $context 0 $op
    else
      defstr __str_240 "comp_rvalue_go: unknown rvalue"
      _fatal_error __ $__str_240
      : $(($1 = 0))
    fi
  elif [ $nb_children = 3 ] && [ $op = $__QUESTION__ ] ; then
    _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
    _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
    _comp_rvalue_go sub3 $child2 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
    defstr __str_241 " : "
    _op_to_str __t1 $op
    _wrap_str_lit __t2 $__str_241
    _string_concat5 __t1 $sub1 $__t1 $sub2 $__t2 $sub3
    _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
  elif [ $nb_children = 4 ] && { [ $op = $_AMP_AMP ] || [ $op = $_BAR_BAR ]; } ; then
    if [ $context = $_RVALUE_CTX_TEST ] ; then
      if { { _get_op __t1 $child0; [ $__t1 = $_AMP_AMP ]; } || { _get_op __t1 $child0; [ $__t1 = $_BAR_BAR ]; }; } && { _get_op __t1 $child0; [ $__t1 != $op ]; } ; then
        _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_TEST $child2 $op
        defstr __str_221 "{ "
        _wrap_str_lit __t1 $__str_221
        defstr __str_222 "; }"
        _wrap_str_lit __t2 $__str_222
        _string_concat3 sub1 $__t1 $sub1 $__t2
      else
        _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_TEST $child2 $op
      fi
      if { { _get_op __t1 $child1; [ $__t1 = $_AMP_AMP ]; } || { _get_op __t1 $child1; [ $__t1 = $_BAR_BAR ]; }; } && { _get_op __t1 $child1; [ $__t1 != $op ]; } ; then
        _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_TEST $child3 $op
        defstr __str_221 "{ "
        _wrap_str_lit __t1 $__str_221
        defstr __str_222 "; }"
        _wrap_str_lit __t2 $__str_222
        _string_concat3 sub2 $__t1 $sub2 $__t2
      else
        _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_TEST $child3 $op
      fi
      _op_to_str __t1 $op
      _string_concat3 $1 $sub1 $__t1 $sub2
    else
      if [ $test_side_effects != 0 ] || [ $child2 != 0 ] || [ $child3 != 0 ] ; then
        defstr __str_242 "comp_rvalue_go: && and || with function calls can only be used in tests"
        _fatal_error __ $__str_242
      fi
      _comp_rvalue_go sub1 $child0 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _comp_rvalue_go sub2 $child1 $_RVALUE_CTX_ARITH_EXPANSION 0 $op
      _op_to_str __t1 $op
      _string_concat3 __t1 $sub1 $__t1 $sub2
      _wrap_if_needed $1 1 $context $test_side_effects $__t1 $outer_op $op
    fi
  else
    defstr __str_240 "comp_rvalue_go: unknown rvalue"
    _fatal_error __ $__str_240
    : $(($1 = 0))
  fi
  endlet $1 __t3 __t2 __t1 child3 child2 child1 child0 sub3 sub2 sub1 nb_children op outer_op test_side_effects context node
}

: $((__t2 = __t1 = side_effect = result = fun_call_decl_start = contains_side_effects2 = replaced_fun_calls2 = simple_ast = context = node = 0))
_comp_rvalue() { let node $2; let context $3
  let simple_ast; let replaced_fun_calls2; let contains_side_effects2; let fun_call_decl_start; let result; let side_effect; let __t1; let __t2
  _handle_side_effects simple_ast $node
  replaced_fun_calls2=$_replaced_fun_calls
  contains_side_effects2=$_contains_side_effects
  fun_call_decl_start=$_glo_decl_ix
  while [ $_literals_inits != 0 ]; do
    _car side_effect $_literals_inits
    _get_child __t1 $side_effect 0
    _get_child __t2 $side_effect 1
    _comp_defstr __ $__t1 $__t2 -1
    _cdr _literals_inits $_literals_inits
  done
  if [ $context != $_RVALUE_CTX_TEST_ELSEIF ] ; then
    fun_call_decl_start=$_glo_decl_ix
  fi
  while [ $replaced_fun_calls2 != 0 ]; do
    _car side_effect $replaced_fun_calls2
    _get_child __t1 $side_effect 1
    _get_child __t2 $side_effect 0
    _comp_fun_call __ $__t1 $__t2
    _cdr replaced_fun_calls2 $replaced_fun_calls2
  done
  if [ $context = $_RVALUE_CTX_TEST ] || [ $context = $_RVALUE_CTX_TEST_ELSEIF ] ; then
    _undo_glo_decls __ $fun_call_decl_start
    _replay_glo_decls_inline result $fun_call_decl_start $_glo_decl_ix
    _comp_rvalue_go __t1 $simple_ast $_RVALUE_CTX_TEST 0 0
    _string_concat result $result $__t1
  else
    _comp_rvalue_go result $simple_ast $context 0 0
  fi
  _contains_side_effects=$((_contains_side_effects | contains_side_effects2))
  : $(($1 = result))
  endlet $1 __t2 __t1 side_effect result fun_call_decl_start contains_side_effects2 replaced_fun_calls2 simple_ast context node
}

: $((__t1 = sub2 = sub1 = op = node = 0))
_comp_lvalue_address() { let node $2
  let op; let sub1; let sub2; let __t1
  _get_op op $node
  if [ $op = $_IDENTIFIER ] ; then
    defstr __str_243 "comp_rvalue_go: can't take the address of variable"
    _fatal_error __ $__str_243
    : $(($1 = 0))
  elif [ $op = $__LBRACK__ ] ; then
    _get_child __t1 $node 0
    _comp_rvalue sub1 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    _get_child __t1 $node 1
    _comp_rvalue sub2 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    defstr __str_238 " + "
    _wrap_str_lit __t1 $__str_238
    _string_concat3 $1 $sub1 $__t1 $sub2
  elif [ $op = $__STAR__ ] ; then
    _get_child __t1 $node 0
    _comp_rvalue $1 $__t1 $_RVALUE_CTX_BASE
  elif [ $op = $_ARROW ] ; then
    _get_child __t1 $node 0
    _comp_rvalue sub1 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    _get_child __t1 $node 1
    _struct_member_var sub2 $__t1
    defstr __str_238 " + "
    _wrap_str_lit __t1 $__str_238
    _string_concat3 $1 $sub1 $__t1 $sub2
  elif [ $op = $_CAST ] ; then
    _get_child __t1 $node 1
    _comp_lvalue_address $1 $__t1
  else
    defstr __str_244 "comp_lvalue_address: unknown lvalue"
    _fatal_error __ $__str_244
    : $(($1 = 0))
  fi
  endlet $1 __t1 sub2 sub1 op node
}

: $((__t3 = __t2 = __t1 = sub2 = sub1 = op = node = 0))
_comp_lvalue() { let node $2
  let op; let sub1; let sub2; let __t1; let __t2; let __t3
  _get_op op $node
  if [ $op = $_IDENTIFIER ] || [ $op = $_IDENTIFIER_INTERNAL ] || [ $op = $_IDENTIFIER_STRING ] || [ $op = $_IDENTIFIER_DOLLAR ] ; then
    _env_var_with_prefix $1 $node 0
  elif [ $op = $__LBRACK__ ] ; then
    _get_child __t1 $node 0
    _comp_rvalue sub1 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    _get_child __t1 $node 1
    _comp_rvalue sub2 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    defstr __str_237 "_\$(("
    _wrap_str_lit __t1 $__str_237
    defstr __str_238 " + "
    _wrap_str_lit __t2 $__str_238
    defstr __str_226 "))"
    _wrap_str_lit __t3 $__str_226
    _string_concat5 $1 $__t1 $sub1 $__t2 $sub2 $__t3
  elif [ $op = $__STAR__ ] ; then
    _get_child __t1 $node 0
    _comp_rvalue sub1 $__t1 $_RVALUE_CTX_BASE
    _string_concat $1 $((-__UNDERSCORE__)) $sub1
  elif [ $op = $_ARROW ] ; then
    _get_child __t1 $node 0
    _comp_rvalue sub1 $__t1 $_RVALUE_CTX_ARITH_EXPANSION
    _get_child __t1 $node 1
    _struct_member_var sub2 $__t1
    defstr __str_237 "_\$(("
    _wrap_str_lit __t1 $__str_237
    defstr __str_238 " + "
    _wrap_str_lit __t2 $__str_238
    defstr __str_226 "))"
    _wrap_str_lit __t3 $__str_226
    _string_concat5 $1 $__t1 $sub1 $__t2 $sub2 $__t3
  elif [ $op = $_CAST ] ; then
    _get_child __t1 $node 1
    _comp_lvalue $1 $__t1
  else
    defstr __str_245 "comp_lvalue: unknown lvalue"
    _fatal_error __ $__str_245
    : $(($1 = 0))
  fi
  endlet $1 __t3 __t2 __t1 sub2 sub1 op node
}

: $((__t1 = code_params = param = params = 0))
_fun_call_params() { let params $2
  let param; let code_params; let __t1
  code_params=0
  while [ $params != 0 ]; do
    _car __t1 $params
    _comp_rvalue param $__t1 $_RVALUE_CTX_BASE
    _concatenate_strings_with code_params $code_params $param $((-__SPACE__))
    _cdr params $params
  done
  : $(($1 = code_params))
  endlet $1 __t1 code_params param params
}

: $((__t4 = __t3 = __t2 = __t1 = c = ident = res = param = 0))
_comp_putchar_inline() { let param $2
  let res; let ident; let c; let __t1; let __t2; let __t3; let __t4
  if _get_op __t1 $param; [ $__t1 = $_CHARACTER ] ; then
    _get_val c $param
    if { [ $c -ge 32 ] && [ $c -le 126 ]; } || [ $c = $__LF__ ] ; then
      defstr __str_246 "printf \""
      _wrap_str_lit __t1 $__str_246
      _escape_text __t2 $((- c)) 1
      _string_concat3 $1 $__t1 $__t2 $((-__DQUOTE__))
      endlet $1 __t4 __t3 __t2 __t1 c ident res param
      return
    fi
  fi
  _comp_rvalue res $param $_RVALUE_CTX_ARITH_EXPANSION
  if [ $_contains_side_effects != 0 ] ; then
    _fresh_ident ident
    defstr __str_247 "=\$(("
    defstr __str_226 "))"
    _comp_lvalue __t1 $ident
    _wrap_str_lit __t2 $__str_247
    _wrap_str_lit __t3 $__str_226
    _string_concat4 __t1 $__t1 $__t2 $res $__t3
    _append_glo_decl __ $__t1
    _comp_lvalue res $ident
  elif _get_op __t1 $param; [ $__t1 != $_IDENTIFIER ] ; then
    _string_concat3 res $((-__LPAREN__)) $res $((-__RPAREN__))
  fi
  defstr __str_225 "\$(("
  defstr __str_248 "/64))"
  _wrap_str_lit __t1 $__str_225
  _wrap_str_lit __t2 $__str_248
  _string_concat3 __t1 $__t1 $res $__t2
  defstr __str_225 "\$(("
  defstr __str_249 "/8%8))"
  _wrap_str_lit __t2 $__str_225
  _wrap_str_lit __t3 $__str_249
  _string_concat3 __t2 $__t2 $res $__t3
  defstr __str_225 "\$(("
  defstr __str_250 "%8))"
  _wrap_str_lit __t3 $__str_225
  _wrap_str_lit __t4 $__str_250
  _string_concat3 __t3 $__t3 $res $__t4
  _string_concat3 res $__t1 $__t2 $__t3
  defstr __str_251 "printf %b \\\\\\\\0"
  _wrap_str_lit __t1 $__str_251
  _string_concat $1 $__t1 $res
  endlet $1 __t4 __t3 __t2 __t1 c ident res param
}

: $((__t3 = __t2 = __t1 = escape = params_text = format_str_end = format_str = 0))
_printf_call() { let format_str $2; let format_str_end $3; let params_text $4; let escape $5
  let __t1; let __t2; let __t3
  if [ $format_str = $format_str_end ] ; then
    : $(($1 = 0))
  else
    defstr __str_252 "printf -- \""
    defstr __str_246 "printf \""
    _wrap_str_lit __t1 $(((_$format_str == __MINUS__) ? __str_252 : __str_246))
    _wrap_str_imm __t2 $format_str $format_str_end
    _escape_text __t2 $__t2 $escape
    _concatenate_strings_with __t3 $((-__DQUOTE__)) $params_text $((-__SPACE__))
    _string_concat3 $1 $__t1 $__t2 $__t3
  fi
  endlet $1 __t3 __t2 __t1 escape params_text format_str_end format_str
}

#_ PRINTF_STATE enum declaration
readonly _PRINTF_STATE_FLAGS=0
readonly _PRINTF_STATE_WIDTH=1
readonly _PRINTF_STATE_PRECISION=2
readonly _PRINTF_STATE_SPECIFIER=3
: $((__t3 = __t2 = __t1 = state = has_precision = has_width = precision_text = width_text = mod = params_text = specifier_start = format_start = param = params = format_str = 0))
_handle_printf_call() { let format_str $2; let params $3
  let param; let format_start; let specifier_start; let params_text; let mod; let width_text; let precision_text; let has_width; let has_precision; let state; let __t1; let __t2; let __t3
  param=0
  format_start=$format_str
  params_text=0
  mod=0
  width_text=0
  precision_text=0
  has_width=0
  has_precision=0
  state=$_PRINTF_STATE_FLAGS
  while [ $((_$format_str)) != $__NUL__ ]; do
    if [ $param = 0 ] && [ $params != 0 ] ; then
      _car param $params
      _cdr params $params
    fi
    if [ $mod != 0 ] ; then
      if [ $((_$format_str)) = $__PERCENT__ ] ; then
        mod=0
      elif [ $((_$format_str)) = $__SPACE__ ] || [ $((_$format_str)) = $__HASH__ ] || [ $((_$format_str)) = $__PLUS__ ] || [ $((_$format_str)) = $__MINUS__ ] || [ $((_$format_str)) = $__0__ ] ; then
        if [ $state != $_PRINTF_STATE_FLAGS ] ; then
          defstr __str_253 "printf: flags must come before width and precision"
          _fatal_error __ $__str_253
        fi
      elif [ $__0__ -le $((_$format_str)) ] && [ $((_$format_str)) -le $__9__ ] ; then
        if [ $state != $_PRINTF_STATE_FLAGS ] && [ $state != $_PRINTF_STATE_PRECISION ] ; then
          defstr __str_254 "printf: width or precision already specified"
          _fatal_error __ $__str_254
        fi
        while [ $__0__ -le $((_$format_str)) ] && [ $((_$format_str)) -le $__9__ ]; do
          : $((format_str += 1))
        done
        has_width=$(((state == _PRINTF_STATE_FLAGS) ? 1 : has_width))
        has_precision=$(((state == _PRINTF_STATE_PRECISION) ? 1 : has_precision))
        : $((state += 1))
        : $((format_str -= 1))
      elif [ $((_$format_str)) = $__PERIOD__ ] ; then
        if [ $state -ge $_PRINTF_STATE_PRECISION ] ; then
          defstr __str_255 "printf: precision already specified"
          _fatal_error __ $__str_255
        fi
        state=$_PRINTF_STATE_PRECISION
      elif [ $((_$format_str)) = $__STAR__ ] ; then
        if [ $param = 0 ] ; then
          defstr __str_256 "printf: not enough parameters"
          _fatal_error __ $__str_256
        fi
        if [ $state = $_PRINTF_STATE_FLAGS ] ; then
          _comp_rvalue width_text $param $_RVALUE_CTX_BASE
          has_width=1
        elif [ $state = $_PRINTF_STATE_PRECISION ] ; then
          _comp_rvalue precision_text $param $_RVALUE_CTX_BASE
          has_precision=1
        else
          defstr __str_254 "printf: width or precision already specified"
          _fatal_error __ $__str_254
        fi
        param=0
      elif [ $((_$format_str)) = $__l__ ] || [ $((_$format_str)) = $__d__ ] || [ $((_$format_str)) = $__o__ ] || [ $((_$format_str)) = $__u__ ] || [ $((_$format_str)) = $__x__ ] || [ $((_$format_str)) = $__X__ ] || [ $((_$format_str)) = $__i__ ] ; then
        if [ $((_$format_str)) = $__l__ ] ; then
          while [ $((_$format_str)) = $__l__ ]; do
            : $((format_str += 1))
          done
          if [ $((_$format_str)) != $__d__ ] && [ $((_$format_str)) != $__i__ ] && [ $((_$format_str)) != $__o__ ] && [ $((_$format_str)) != $__u__ ] && [ $((_$format_str)) != $__x__ ] && [ $((_$format_str)) != $__X__ ] ; then
            defstr __str_257 "printf: unsupported format specifier"
            _fatal_error __ $__str_257
          fi
        fi
        if [ $param = 0 ] ; then
          defstr __str_256 "printf: not enough parameters"
          _fatal_error __ $__str_256
        fi
        _concatenate_strings_with params_text $params_text $width_text $((-__SPACE__))
        _concatenate_strings_with params_text $params_text $precision_text $((-__SPACE__))
        _comp_rvalue __t1 $param $_RVALUE_CTX_BASE
        _concatenate_strings_with params_text $params_text $__t1 $((-__SPACE__))
        param=0
        mod=0
      elif [ $((_$format_str)) = $__c__ ] ; then
        if [ $param = 0 ] ; then
          defstr __str_256 "printf: not enough parameters"
          _fatal_error __ $__str_256
        fi
        if [ $has_width != 0 ] ; then
          defstr __str_258 "printf: width not supported for %c"
          _fatal_error __ $__str_258
        fi
        _printf_call __t1 $format_start $specifier_start $params_text 0
        _append_glo_decl __ $__t1
        format_start=$((format_str + 1))
        _comp_putchar_inline __t1 $param
        _append_glo_decl __ $__t1
        param=0
        params_text=0
        mod=0
      elif [ $((_$format_str)) = $__s__ ] ; then
        if [ $param = 0 ] ; then
          defstr __str_256 "printf: not enough parameters"
          _fatal_error __ $__str_256
        fi
        _runtime_use_put_pstr=1
        if [ $has_width != 0 ] || [ $has_precision != 0 ] ; then
          _concatenate_strings_with params_text $params_text $width_text $((-__SPACE__))
          _concatenate_strings_with params_text $params_text $precision_text $((-__SPACE__))
          defstr __str_259 "\"\$(_put_pstr __ "
          defstr __str_260 ")\""
          _wrap_str_lit __t1 $__str_259
          _comp_rvalue __t2 $param $_RVALUE_CTX_BASE
          _wrap_str_lit __t3 $__str_260
          _string_concat3 __t1 $__t1 $__t2 $__t3
          _concatenate_strings_with params_text $params_text $__t1 $((-__SPACE__))
        else
          _printf_call __t1 $format_start $specifier_start $params_text 0
          _append_glo_decl __ $__t1
          format_start=$((format_str + 1))
          defstr __str_261 "_put_pstr __ "
          _wrap_str_lit __t1 $__str_261
          _comp_rvalue __t2 $param $_RVALUE_CTX_BASE
          _string_concat __t1 $__t1 $__t2
          _append_glo_decl __ $__t1
        fi
        param=0
        mod=0
      else
        defstr __str_257 "printf: unsupported format specifier"
        _fatal_error __ $__str_257
      fi
    elif [ $((_$format_str)) = $__PERCENT__ ] ; then
      mod=1
      specifier_start=$format_str
      : $((width_text = precision_text = has_width = has_precision = 0))
      state=$_PRINTF_STATE_FLAGS
    fi
    : $((format_str += 1))
  done
  _printf_call __t1 $format_start $format_str $params_text 0
  _append_glo_decl __ $__t1
  endlet $1 __t3 __t2 __t1 state has_precision has_width precision_text width_text mod params_text specifier_start format_start param params format_str
}

: $((__t2 = __t1 = res = param = name_id = params = name = assign_to = node = 0))
_comp_fun_call_code() { let node $2; let assign_to $3
  let name; let params; let name_id; let param; let res; let __t1; let __t2
  _get_child name $node 0
  _get_child params $node 1
  _get_val name_id $name
  if [ $assign_to = 0 ] ; then
    if { [ $name_id = $_PUTS_ID ] || [ $name_id = $_PUTSTR_ID ] || [ $name_id = $_PRINTF_ID ]; } && { _list_singleton param $params; [ $param != 0 ]; } && { _get_op __t1 $param; [ $__t1 = $_STRING ]; } ; then
      _get_val __t1 $param
      _symbol_buf __t1 $__t1
      _printf_call $1 $__t1 0 0 1
      endlet $1 __t2 __t1 res param name_id params name assign_to node
      return
    elif [ $name_id = $_PRINTF_ID ] && [ $params != 0 ] && { _car __t2 $params; _get_op __t2 $__t2; [ $__t2 = $_STRING ]; } ; then
      _car __t1 $params
      _get_val __t1 $__t1
      _symbol_buf __t1 $__t1
      _cdr __t2 $params
      _handle_printf_call __ $__t1 $__t2
      : $(($1 = 0))
      endlet $1 __t2 __t1 res param name_id params name assign_to node
      return
    elif [ $name_id = $_PUTCHAR_ID ] && { _list_singleton param $params; [ $param != 0 ]; } ; then
      _comp_putchar_inline $1 $param
      endlet $1 __t2 __t1 res param name_id params name assign_to node
      return
    elif [ $name_id = $_EXIT_ID ] && { _list_singleton param $params; [ $param != 0 ]; } ; then
      _comp_rvalue res $param $_RVALUE_CTX_BASE
      defstr __str_262 "exit "
      _wrap_str_lit __t1 $__str_262
      _string_concat $1 $__t1 $res
      endlet $1 __t2 __t1 res param name_id params name assign_to node
      return
    fi
  fi
  if [ $name_id = $_MALLOC_ID ] ; then
    _runtime_use_malloc=1
  elif [ $name_id = $_FREE_ID ] ; then
    _runtime_use_free=1
  elif [ $name_id = $_READ_ID ] ; then
    _runtime_use_read=1
  elif [ $name_id = $_WRITE_ID ] ; then
    _runtime_use_write=1
  elif [ $name_id = $_OPEN_ID ] ; then
    _runtime_use_open=1
  elif [ $name_id = $_CLOSE_ID ] ; then
    _runtime_use_close=1
  elif [ $name_id = $_GETCHAR_ID ] ; then
    _runtime_use_getchar=1
  elif [ $name_id = $_PRINTF_ID ] ; then
    _runtime_use_printf=1
  elif [ $name_id = $_FOPEN_ID ] ; then
    _runtime_use_fopen=1
  elif [ $name_id = $_FCLOSE_ID ] ; then
    _runtime_use_fclose=1
  elif [ $name_id = $_FGETC_ID ] ; then
    _runtime_use_fgetc=1
  elif [ $name_id = $_ISATTY_ID ] ; then
    _runtime_use_isatty=1
  fi
  if [ $assign_to != 0 ] ; then
    _comp_lvalue res $assign_to
  else
    defstr __str_176 "__"
    _wrap_str_lit res $__str_176
  fi
  _get_val __t1 $name
  _function_name __t1 $__t1
  _fun_call_params __t2 $params
  _concatenate_strings_with __t2 $res $__t2 $((-__SPACE__))
  _string_concat3 $1 $__t1 $((-__SPACE__)) $__t2
  endlet $1 __t2 __t1 res param name_id params name assign_to node
}

: $((res = assign_to = node = 0))
_comp_fun_call() { let node $2; let assign_to $3
  let res
  _comp_fun_call_code res $node $assign_to
  if [ $res != 0 ] ; then
    _append_glo_decl __ $res
  fi
  endlet $1 res assign_to node
}

: $((__t5 = __t4 = __t3 = __t2 = __t1 = lhs_op = rhs = lhs = 0))
_comp_assignment() { let lhs $2; let rhs $3
  let lhs_op; let __t1; let __t2; let __t3; let __t4; let __t5
  _get_op lhs_op $lhs
  if [ $lhs_op = $_IDENTIFIER ] || [ $lhs_op = $__LBRACK__ ] || [ $lhs_op = $__STAR__ ] || [ $lhs_op = $_ARROW ] ; then
    if _get_op __t1 $rhs; [ $__t1 = $__LPAREN__ ] ; then
      _comp_fun_call __ $rhs $lhs
    else
      if [ $lhs_op = $_IDENTIFIER ] && { _get_op __t1 $rhs; [ $__t1 != $__EQ__ ]; } ; then
        _comp_lvalue __t1 $lhs
        _comp_rvalue __t2 $rhs $_RVALUE_CTX_BASE
        _string_concat3 __t1 $__t1 $((-__EQ__)) $__t2
        _append_glo_decl __ $__t1
      else
        defstr __str_263 ": \$(("
        defstr __str_204 " = "
        defstr __str_226 "))"
        _wrap_str_lit __t1 $__str_263
        _comp_lvalue __t2 $lhs
        _wrap_str_lit __t3 $__str_204
        _comp_rvalue __t4 $rhs $_RVALUE_CTX_ARITH_EXPANSION
        _wrap_str_lit __t5 $__str_226
        _string_concat5 __t1 $__t1 $__t2 $__t3 $__t4 $__t5
        _append_glo_decl __ $__t1
      fi
    fi
  else
    defstr __str_264 "comp_assignment: unknown lhs"
    _fatal_error __ $__str_264
  fi
  endlet $1 __t5 __t4 __t3 __t2 __t1 lhs_op rhs lhs
}

: $((__t1 = child1 = start_cgc_locals = start_in_tail_position = stmt_ctx = node = 0))
_comp_body() { let node $2; let stmt_ctx $3
  let start_in_tail_position; let start_cgc_locals; let child1; let __t1
  start_in_tail_position=$_in_tail_position
  start_cgc_locals=$_cgc_locals
  _in_tail_position=0
  while [ $node != 0 ]; do
    _get_child child1 $node 1
    if [ $child1 = 0 ] || { _get_op __t1 $child1; [ $__t1 != $__LBRACE__ ]; } ; then
      _in_tail_position=$start_in_tail_position
    fi
    if _get_child __t1 $node 0; _comp_statement __t1 $__t1 $stmt_ctx; [ $__t1 != 0 ] ; then
      break
    fi
    node=$child1
  done
  _cgc_locals=$start_cgc_locals
  : $(($1 = node != 0))
  endlet $1 __t1 child1 start_cgc_locals start_in_tail_position stmt_ctx node
}

_last_stmt=0
: $((__t1 = op = str = statement = 0))
_make_switch_pattern() { let statement $2
  let str; let op; let __t1
  str=0
  while [ 1 != 0 ]; do
    _get_op op $statement
    if [ $op = $_DEFAULT_KW ] ; then
      str=$((-__STAR__))
      _get_child statement $statement 0
    elif [ $op = $_CASE_KW ] ; then
      _get_child __t1 $statement 0
      _comp_rvalue __t1 $__t1 $_RVALUE_CTX_BASE
      _concatenate_strings_with str $str $__t1 $((-__BAR__))
      _get_child statement $statement 1
    else
      if [ $str = 0 ] ; then
        defstr __str_265 "Expected case in switch. Fallthrough is not supported."
        _fatal_error __ $__str_265
      fi
      _last_stmt=$statement
      _string_concat $1 $str $((-__RPAREN__))
      break
    fi
  done
  endlet $1 __t1 op str statement
}

: $((__t3 = __t2 = __t1 = start_cgc_locals = statement = node = 0))
_comp_switch() { let node $2
  let statement; let start_cgc_locals; let __t1; let __t2; let __t3
  start_cgc_locals=$_cgc_locals
  defstr __str_266 "case "
  defstr __str_267 " in"
  _wrap_str_lit __t1 $__str_266
  _get_child __t2 $node 0
  _comp_rvalue __t2 $__t2 $_RVALUE_CTX_BASE
  _wrap_str_lit __t3 $__str_267
  _string_concat3 __t1 $__t1 $__t2 $__t3
  _append_glo_decl __ $__t1
  _cgc_add_enclosing_switch __ $_in_tail_position
  : $((_nest_level += 1))
  _get_child node $node 1
  if _get_op __t1 $node; [ $__t1 = $_CASE_KW ] ; then
    _new_ast2 node $__LBRACE__ $node 0
  fi
  if [ $node = 0 ] || { _get_op __t1 $node; [ $__t1 != $__LBRACE__ ]; } ; then
    defstr __str_268 "comp_statement: switch without body"
    _fatal_error __ $__str_268
  fi
  while [ $node != 0 ] && { _get_op __t1 $node; [ $__t1 = $__LBRACE__ ]; }; do
    _get_child statement $node 0
    _get_child node $node 1
    _make_switch_pattern __t1 $statement
    _append_glo_decl __ $__t1
    statement=$_last_stmt
    : $((_nest_level += 1))
    _in_tail_position=0
    if _comp_statement __t1 $statement $_STMT_CTX_SWITCH; [ $((!__t1)) != 0 ] ; then
      while [ $node != 0 ] && { _get_op __t1 $node; [ $__t1 = $__LBRACE__ ]; }; do
        _get_child statement $node 0
        _get_child node $node 1
        if _comp_statement __t1 $statement $_STMT_CTX_SWITCH; [ $__t1 != 0 ] ; then
          break
        fi
      done
    fi
    : $((_nest_level -= 1))
    defstr __str_269 ";;"
    _wrap_str_lit __t1 $__str_269
    _append_glo_decl __ $__t1
  done
  : $((_nest_level -= 1))
  defstr __str_270 "esac"
  _wrap_str_lit __t1 $__str_270
  _append_glo_decl __ $__t1
  _cgc_locals=$start_cgc_locals
  : $(($1 = 0))
  endlet $1 __t3 __t2 __t1 start_cgc_locals statement node
}

: $((__t3 = __t2 = __t1 = else_if = else_node = start_cgc_locals = termination_rhs = termination_lhs = start_glo_decl_idx = stmt_ctx = node = 0))
_comp_if() { let node $2; let stmt_ctx $3
  let start_glo_decl_idx; let termination_lhs; let termination_rhs; let start_cgc_locals; let else_node; let else_if; let __t1; let __t2; let __t3
  termination_lhs=0
  termination_rhs=0
  start_cgc_locals=$_cgc_locals
  _get_child else_node $node 2
  else_if=$((stmt_ctx & _STMT_CTX_ELSE_IF))
  stmt_ctx=$((stmt_ctx & ~ _STMT_CTX_ELSE_IF))
  defstr __str_271 "elif "
  defstr __str_272 "if "
  defstr __str_273 " ; then"
  _wrap_str_lit __t1 $((else_if ? __str_271 : __str_272))
  _get_child __t2 $node 0
  _comp_rvalue __t2 $__t2 $((else_if ? _RVALUE_CTX_TEST_ELSEIF : _RVALUE_CTX_TEST))
  _wrap_str_lit __t3 $__str_273
  _string_concat3 __t1 $__t1 $__t2 $__t3
  _append_glo_decl __ $__t1
  : $((_nest_level += 1))
  start_glo_decl_idx=$_glo_decl_ix
  _get_child __t1 $node 1
  _comp_statement termination_lhs $__t1 $stmt_ctx
  if _any_active_glo_decls __t1 $start_glo_decl_idx; [ $((!__t1)) != 0 ] ; then
    _append_glo_decl __ $((-__COLON__))
  fi
  : $((_nest_level -= 1))
  if [ $else_node != 0 ] ; then
    if _get_op __t1 $else_node; [ $__t1 = $_IF_KW ] ; then
      _comp_if termination_rhs $else_node $((stmt_ctx | _STMT_CTX_ELSE_IF))
    else
      defstr __str_34 "else"
      _wrap_str_lit __t1 $__str_34
      _append_glo_decl __ $__t1
      : $((_nest_level += 1))
      start_glo_decl_idx=$_glo_decl_ix
      _comp_statement termination_rhs $else_node $((stmt_ctx & ~ _STMT_CTX_ELSE_IF))
      if _any_active_glo_decls __t1 $start_glo_decl_idx; [ $((!__t1)) != 0 ] ; then
        _append_glo_decl __ $((-__COLON__))
      fi
      : $((_nest_level -= 1))
    fi
  fi
  if [ $((! else_if)) != 0 ] ; then
    defstr __str_274 "fi"
    _wrap_str_lit __t1 $__str_274
    _append_glo_decl __ $__t1
  fi
  if [ $((stmt_ctx & _STMT_CTX_SWITCH)) != 0 ] && [ $((termination_lhs ^ termination_rhs)) != 0 ] ; then
    defstr __str_275 "Early break out of a switch case is unsupported"
    _fatal_error __ $__str_275
  fi
  _cgc_locals=$start_cgc_locals
  : $(($1 = termination_lhs && termination_rhs))
  endlet $1 __t3 __t2 __t1 else_if else_node start_cgc_locals termination_rhs termination_lhs start_glo_decl_idx stmt_ctx node
}

: $((__t2 = __t1 = loop_binding = always_returns = start_glo_decl_idx = start_cgc_locals = stmt_ctx = last_line = loop_end_stmt = body = cond = 0))
_comp_loop() { let cond $2; let body $3; let loop_end_stmt $4; let last_line $5; let stmt_ctx $6
  let start_cgc_locals; let start_glo_decl_idx; let always_returns; let loop_binding; let __t1; let __t2
  start_cgc_locals=$_cgc_locals
  always_returns=0
  _cgc_add_enclosing_loop __
  loop_binding=$_cgc_locals
  if [ $loop_end_stmt != 0 ] ; then
    : $((_$((_heap + loop_binding + 2)) = _glo_decl_ix))
    _comp_statement __ $loop_end_stmt $stmt_ctx
    _undo_glo_decls __ $((_$((_heap + loop_binding + 2))))
    : $((_$((_heap + loop_binding + 3)) = _glo_decl_ix))
  fi
  defstr __str_276 "while "
  defstr __str_277 "; do"
  _wrap_str_lit __t1 $__str_276
  _wrap_str_lit __t2 $__str_277
  _string_concat3 __t1 $__t1 $((cond ? cond : -__COLON__)) $__t2
  _append_glo_decl __ $__t1
  : $((_nest_level += 1))
  start_glo_decl_idx=$_glo_decl_ix
  _comp_statement always_returns $body $stmt_ctx
  _append_glo_decl __ $last_line
  _replay_glo_decls __ $((_$((_heap + loop_binding + 2)))) $((_$((_heap + loop_binding + 3))))
  if _any_active_glo_decls __t1 $start_glo_decl_idx; [ $((!__t1)) != 0 ] ; then
    _append_glo_decl __ $((-__COLON__))
  fi
  : $((_nest_level -= 1))
  defstr __str_278 "done"
  _wrap_str_lit __t1 $__str_278
  _append_glo_decl __ $__t1
  _cgc_locals=$start_cgc_locals
  : $(($1 = (cond == -__COLON__) && always_returns))
  endlet $1 __t2 __t1 loop_binding always_returns start_glo_decl_idx start_cgc_locals stmt_ctx last_line loop_end_stmt body cond
}

: $((__t1 = binding = 0))
_comp_break() {
  let binding; let __t1
  _cgc_lookup_enclosing_loop_or_switch binding $_cgc_locals
  if [ $binding = 0 ] ; then
    defstr __str_279 "comp_statement: break not in loop or switch"
    _fatal_error __ $__str_279
  fi
  if [ $((_$((_heap + binding + 1)))) = $_BINDING_LOOP ] ; then
    defstr __str_29 "break"
    _wrap_str_lit __t1 $__str_29
    _append_glo_decl __ $__t1
  fi
  : $(($1 = 1))
  endlet $1 __t1 binding
}

: $((__t1 = binding = 0))
_comp_continue() {
  let binding; let __t1
  _cgc_lookup_enclosing_loop binding $_cgc_locals
  if [ $binding = 0 ] ; then
    defstr __str_280 "comp_statement: continue not in loop"
    _fatal_error __ $__str_280
  fi
  _replay_glo_decls __ $((_$((_heap + binding + 2)))) $((_$((_heap + binding + 3))))
  defstr __str_31 "continue"
  _wrap_str_lit __t1 $__str_31
  _append_glo_decl __ $__t1
  : $(($1 = 0))
  endlet $1 __t1 binding
}

: $((__t3 = __t2 = __t1 = loop_depth = binding = return_value = 0))
_comp_return() { let return_value $2
  let binding; let loop_depth; let __t1; let __t2; let __t3
  _cgc_lookup_enclosing_loop_or_switch binding $_cgc_locals
  _cgc_loop_depth loop_depth $binding
  if [ $return_value != 0 ] ; then
    if _get_op __t1 $return_value; [ $__t1 = $__LPAREN__ ] ; then
      _new_dollar_ident __t1 1
      _comp_fun_call __ $return_value $__t1
    else
      defstr __str_281 ": \$((\$1 = "
      defstr __str_226 "))"
      _wrap_str_lit __t1 $__str_281
      _comp_rvalue __t2 $return_value $_RVALUE_CTX_ARITH_EXPANSION
      _wrap_str_lit __t3 $__str_226
      _string_concat3 __t1 $__t1 $__t2 $__t3
      _append_glo_decl __ $__t1
    fi
  fi
  if [ $binding != 0 ] && [ $((_$((_heap + binding + 1)))) = $_BINDING_SWITCH ] ; then
    _in_tail_position=$((_in_tail_position | _$((_heap + binding + 2))))
  fi
  if [ $_in_tail_position != 0 ] && [ $binding != 0 ] ; then
    if [ $loop_depth -ge 2 ] ; then
      defstr __str_282 "break "
      _wrap_str_lit __t1 $__str_282
      _wrap_int __t2 $loop_depth
      _string_concat __t1 $__t1 $__t2
      _append_glo_decl __ $__t1
    elif [ $loop_depth = 1 ] ; then
      defstr __str_29 "break"
      _wrap_str_lit __t1 $__str_29
      _append_glo_decl __ $__t1
    fi
  elif [ $((! _in_tail_position)) != 0 ] ; then
    _append_glo_decl_fixup __t1
    _cons _rest_loc_var_fixups $__t1 $_rest_loc_var_fixups
    defstr __str_37 "return"
    _wrap_str_lit __t1 $__str_37
    _append_glo_decl __ $__t1
  fi
  : $(($1 = 1))
  endlet $1 __t3 __t2 __t1 loop_depth binding return_value
}

: $((__t2 = __t1 = spec = var_decl = node = 0))
_comp_var_decls() { let node $2
  let var_decl; let spec; let __t1; let __t2
  _get_child spec $node 1
  if [ $spec = $_EXTERN_KW ] || [ $spec = $_STATIC_KW ] ; then
    defstr __str_283 "Extern and static storage class specifier not supported on local variables"
    _fatal_error __ $__str_283
  fi
  _get_child node $node 0
  while [ $node != 0 ]; do
    _car var_decl $node
    _assert_var_decl_is_safe __ $var_decl 1
    _add_var_to_local_env __ $var_decl $_BINDING_VAR_LOCAL
    if _get_child __t1 $var_decl 2; [ $__t1 != 0 ] ; then
      _get_child __t1 $var_decl 0
      _get_child __t2 $var_decl 2
      _comp_assignment __ $__t1 $__t2
    fi
    _cdr node $node
  done
  endlet $1 __t2 __t1 spec var_decl node
}

: $((__t4 = __t3 = __t2 = __t1 = str = op = stmt_ctx = node = 0))
_comp_statement() { let node $2; let stmt_ctx $3
  let op; let str; let __t1; let __t2; let __t3; let __t4
  if [ $node = 0 ] ; then
    : $(($1 = 0))
    endlet $1 __t4 __t3 __t2 __t1 str op stmt_ctx node
    return
  fi
  _get_op op $node
  _gensym_ix=0
  if [ $op = $_IF_KW ] ; then
    _comp_if $1 $node $stmt_ctx
  elif [ $op = $_WHILE_KW ] ; then
    _get_child __t1 $node 0
    _comp_rvalue __t1 $__t1 $_RVALUE_CTX_TEST
    _get_child __t2 $node 1
    _comp_loop $1 $__t1 $__t2 0 0 $stmt_ctx
  elif [ $op = $_DO_KW ] ; then
    defstr __str_284 ":"
    _wrap_str_lit __t1 $__str_284
    _get_child __t2 $node 0
    defstr __str_285 " || break"
    _get_child __t3 $node 1
    _comp_rvalue __t3 $__t3 $_RVALUE_CTX_TEST
    _wrap_str_lit __t4 $__str_285
    _string_concat __t3 $__t3 $__t4
    _comp_loop $1 $__t1 $__t2 0 $__t3 $stmt_ctx
  elif [ $op = $_FOR_KW ] ; then
    _get_child __t1 $node 0
    _comp_statement __ $__t1 $_STMT_CTX_DEFAULT
    str=$((-__COLON__))
    if _get_child __t1 $node 1; [ $__t1 != 0 ] ; then
      _get_child __t1 $node 1
      _comp_rvalue str $__t1 $_RVALUE_CTX_TEST
    fi
    _get_child __t1 $node 3
    _get_child __t2 $node 2
    _comp_loop $1 $str $__t1 $__t2 0 $stmt_ctx
  elif [ $op = $_SWITCH_KW ] ; then
    _comp_switch $1 $node
  elif [ $op = $_BREAK_KW ] ; then
    _comp_break $1
  elif [ $op = $_CONTINUE_KW ] ; then
    _comp_continue $1
  elif [ $op = $_RETURN_KW ] ; then
    _get_child __t1 $node 0
    _comp_return $1 $__t1
  elif [ $op = $__LPAREN__ ] ; then
    _comp_fun_call __ $node 0
    : $(($1 = 0))
  elif [ $op = $__LBRACE__ ] ; then
    _comp_body $1 $node $stmt_ctx
  elif [ $op = $__EQ__ ] ; then
    _get_child __t1 $node 0
    _get_child __t2 $node 1
    _comp_assignment __ $__t1 $__t2
    : $(($1 = 0))
  elif [ $op = $__COLON__ ] ; then
    defstr __str_286 "#_ "
    _wrap_str_lit __t1 $__str_286
    _get_child __t2 $node 0
    _get_val __t2 $__t2
    _wrap_str_pool __t2 $__t2
    _string_concat3 __t1 $__t1 $__t2 $((-__COLON__))
    _append_glo_decl __ $__t1
    _get_child __t1 $node 1
    _comp_statement $1 $__t1 $stmt_ctx
  elif [ $op = $_GOTO_KW ] ; then
    defstr __str_287 "goto statements not supported"
    _fatal_error __ $__str_287
    : $(($1 = 0))
  elif { _get_op __t1 $node; [ $__t1 = $_CASE_KW ]; } || { _get_op __t1 $node; [ $__t1 = $_DEFAULT_KW ]; } ; then
    defstr __str_288 "case/default must be at the beginning of a switch conditional block"
    _fatal_error __ $__str_288
    : $(($1 = 0))
  elif [ $op = $_DECLS ] ; then
    _comp_var_decls __ $node
    : $(($1 = 0))
  else
    _comp_rvalue str $node $_RVALUE_CTX_BASE
    if [ $_contains_side_effects != 0 ] ; then
      defstr __str_289 ": "
      _wrap_str_lit __t1 $__str_289
      _string_concat __t1 $__t1 $str
      _append_glo_decl __ $__t1
    fi
    : $(($1 = 0))
  fi
  endlet $1 __t4 __t3 __t2 __t1 str op stmt_ctx node
}

: $((__t3 = __t2 = __t1 = start_glo_decl_idx = save_loc_vars_fixup = decl = params_ix = function_comment = let_params_text = params = fun_type = name_symbol = body = fun_decl = node = 0))
_comp_glo_fun_decl() { let node $2
  let fun_decl; let body; let name_symbol; let fun_type; let params; let let_params_text; let function_comment; let params_ix; let decl; let save_loc_vars_fixup; let start_glo_decl_idx; let __t1; let __t2; let __t3
  _get_child fun_decl $node 0
  _get_child body $node 1
  _get_child __t1 $fun_decl 0
  _get_val name_symbol $__t1
  _get_child fun_type $fun_decl 1
  _get_child params $fun_type 1
  let_params_text=0
  function_comment=0
  params_ix=2
  if [ $body = -1 ] ; then
    endlet $1 __t3 __t2 __t1 start_glo_decl_idx save_loc_vars_fixup decl params_ix function_comment let_params_text params fun_type name_symbol body fun_decl node
    return
  fi
  _handle_function_params __ $params
  if [ $name_symbol = $_MAIN_ID ] ; then
    _main_defined=1
    if [ $params != 0 ] ; then
      _runtime_use_make_argv=1
    fi
  fi
  _let_params let_params_text $params
  while [ $params != 0 ]; do
    _car decl $params
    if _get_child __t1 $decl 1; _is_constant_type __t1 $__t1; [ $__t1 != 0 ] ; then
      defstr __str_290 ": \$"
      _get_child __t1 $decl 0
      _get_val __t1 $__t1
      _wrap_str_pool __t1 $__t1
      _wrap_str_lit __t2 $__str_290
      _wrap_int __t3 $params_ix
      _string_concat3 __t1 $__t1 $__t2 $__t3
      defstr __str_291 ", "
      _wrap_str_lit __t2 $__str_291
      _concatenate_strings_with function_comment $function_comment $__t1 $__t2
    fi
    _cdr params $params
    : $((params_ix += 1))
  done
  if [ $function_comment != 0 ] ; then
    defstr __str_292 " # "
    _wrap_str_lit __t1 $__str_292
    _string_concat function_comment $__t1 $function_comment
  fi
  defstr __str_293 "() {"
  _function_name __t1 $name_symbol
  _wrap_str_lit __t2 $__str_293
  _string_concat4 __t1 $__t1 $__t2 $let_params_text $function_comment
  _append_glo_decl __ $__t1
  _in_tail_position=1
  : $((_nest_level += 1))
  start_glo_decl_idx=$_glo_decl_ix
  _append_glo_decl_fixup save_loc_vars_fixup
  _comp_body __ $body $_STMT_CTX_DEFAULT
  _cgc_locals=$_cgc_locals_fun
  _restore_local_vars __t1 $((params_ix - 1))
  _append_glo_decl __ $__t1
  _save_local_vars __t1
  _fixup_glo_decl __ $save_loc_vars_fixup $__t1
  while [ $_rest_loc_var_fixups != 0 ]; do
    _car __t1 $_rest_loc_var_fixups
    _restore_local_vars __t2 $((params_ix - 1))
    _fixup_glo_decl __ $__t1 $__t2
    _cdr _rest_loc_var_fixups $_rest_loc_var_fixups
  done
  if _any_active_glo_decls __t1 $start_glo_decl_idx; [ $((!__t1)) != 0 ] ; then
    _append_glo_decl __ $((-__COLON__))
  fi
  : $((_nest_level -= 1))
  defstr __str_294 "}\n"
  _wrap_str_lit __t1 $__str_294
  _append_glo_decl __ $__t1
  endlet $1 __t3 __t2 __t1 start_glo_decl_idx save_loc_vars_fixup decl params_ix function_comment let_params_text params fun_type name_symbol body fun_decl node
}

: $((__t3 = __t2 = __t1 = args = init_len = arr_len = init = type = name = node = 0))
_comp_glo_var_decl() { let node $2
  let name; let type; let init; let arr_len; let init_len; let args; let __t1; let __t2; let __t3
  _get_child name $node 0
  _get_child type $node 1
  _get_child init $node 2
  args=0
  if _get_op __t1 $type; [ $__t1 = $__LPAREN__ ] ; then
    endlet $1 __t3 __t2 __t1 args init_len arr_len init type name node
    return
  fi
  _assert_var_decl_is_safe __ $node 0
  if _get_op __t1 $type; [ $__t1 = $__LBRACK__ ] ; then
    _get_child arr_len $type 1
    if [ $init != 0 ] && { _get_op __t1 $init; [ $__t1 = $_STRING ]; } ; then
      _get_val __t1 $init
      _symbol_len __t1 $__t1
      init_len=$((__t1 + 1))
      if [ $arr_len != 0 ] && [ $arr_len -lt $init_len ] ; then
        defstr __str_295 "Array type is too small for initializer"
        _fatal_error __ $__str_295
      fi
      _get_val __t1 $init
      _comp_defstr __ $name $__t1 $(((arr_len != 0) ? arr_len : init_len))
    else
      if [ $init != 0 ] ; then
        if _get_op __t1 $init; [ $__t1 != $_INITIALIZER_LIST ] ; then
          defstr __str_296 "Array declaration with invalid initializer"
          _fatal_error __ $__str_296
        fi
        _get_child init $init 0
        _runtime_use_initialize=1
        _initializer_list_len init_len $init
        _comp_initializer_list args $init $arr_len
        if [ $arr_len = 0 ] ; then
          arr_len=$init_len
        elif [ $arr_len -lt $init_len ] ; then
          defstr __str_295 "Array type is too small for initializer"
          _fatal_error __ $__str_295
        fi
      fi
      if [ $arr_len = 0 ] ; then
        defstr __str_297 "Array declaration without size or initializer list"
        _fatal_error __ $__str_297
      fi
      _runtime_defarr __
      defstr __str_298 "defarr "
      _wrap_str_lit __t1 $__str_298
      _get_val __t2 $name
      _global_var __t2 $__t2
      _wrap_int __t3 $arr_len
      _string_concat4 __t1 $__t1 $__t2 $((-__SPACE__)) $__t3
      _concatenate_strings_with __t1 $__t1 $args $((-__SPACE__))
      _append_glo_decl __ $__t1
    fi
  else
    if [ $init = 0 ] ; then
      _new_ast0 init $_INTEGER 0
    fi
    _comp_assignment __ $name $init
  fi
  endlet $1 __t3 __t2 __t1 args init_len arr_len init type name node
}

: $((__t2 = __t1 = rhs = constant_name = 0))
_comp_assignment_constant() { let constant_name $2; let rhs $3
  let __t1; let __t2
  defstr __str_299 "readonly "
  _wrap_str_lit __t1 $__str_299
  _comp_rvalue __t2 $rhs $_RVALUE_CTX_BASE
  _string_concat4 __t1 $__t1 $constant_name $((-__EQ__)) $__t2
  _append_glo_decl __ $__t1
  endlet $1 __t2 __t1 rhs constant_name
}

: $((__t3 = __t2 = __t1 = cas = cases = ident = 0))
_comp_enum_cases() { let ident $2; let cases $3
  let cas; let __t1; let __t2; let __t3
  if [ $ident != 0 ] ; then
    defstr __str_286 "#_ "
    defstr __str_300 " enum declaration"
    _wrap_str_lit __t1 $__str_286
    _get_val __t2 $ident
    _wrap_str_pool __t2 $__t2
    _wrap_str_lit __t3 $__str_300
    _string_concat3 __t1 $__t1 $__t2 $__t3
    _append_glo_decl __ $__t1
  else
    defstr __str_301 "#_ Enum declaration"
    _wrap_str_lit __t1 $__str_301
    _append_glo_decl __ $__t1
  fi
  while [ $cases != 0 ]; do
    _car cas $cases
    _get_child __t1 $cas 0
    _get_val __t1 $__t1
    _global_var __t1 $__t1
    _get_child __t2 $cas 1
    _comp_assignment_constant __ $__t1 $__t2
    _cdr cases $cases
  done
  endlet $1 __t3 __t2 __t1 cas cases ident
}

: $((__t3 = __t2 = __t1 = field_type = offset = decl = members = ident = 0))
_comp_struct() { let ident $2; let members $3
  let decl; let offset; let field_type; let __t1; let __t2; let __t3
  _new_ast0 offset $_INTEGER 0
  if [ $ident != 0 ] ; then
    defstr __str_286 "#_ "
    defstr __str_302 " struct member declarations"
    _wrap_str_lit __t1 $__str_286
    _get_val __t2 $ident
    _wrap_str_pool __t2 $__t2
    _wrap_str_lit __t3 $__str_302
    _string_concat3 __t1 $__t1 $__t2 $__t3
    _append_glo_decl __ $__t1
  else
    defstr __str_303 "#_ Struct member declarations"
    _wrap_str_lit __t1 $__str_303
    _append_glo_decl __ $__t1
  fi
  while [ $members != 0 ]; do
    _car decl $members
    _cdr members $members
    _get_child field_type $decl 1
    if { _get_op __t1 $field_type; [ $__t1 = $__LBRACK__ ]; } || { _get_op __t1 $field_type; [ $__t1 = $_STRUCT_KW ]; } ; then
      defstr __str_304 "Nested structures not supported by shell backend. Use a reference type instead."
      _fatal_error __ $__str_304
    fi
    _get_child __t1 $decl 0
    _struct_member_var __t1 $__t1
    _comp_assignment_constant __ $__t1 $offset
    _get_val __t1 $offset
    _set_val __ $offset $((__t1 - 1))
  done
  if [ $ident != 0 ] ; then
    _struct_sizeof_var __t1 $ident
    _comp_assignment_constant __ $__t1 $offset
  fi
  _append_glo_decl __ 0
  endlet $1 __t3 __t2 __t1 field_type offset decl members ident
}

: $((__t3 = __t2 = __t1 = type = 0))
_handle_enum_struct_union_type_decl() { let type $2
  let __t1; let __t2; let __t3
  if _get_op __t1 $type; [ $__t1 = $_ENUM_KW ] ; then
    _get_child __t1 $type 1
    _get_child __t2 $type 2
    _comp_enum_cases __ $__t1 $__t2
  elif _get_op __t3 $type; [ $__t3 = $_STRUCT_KW ] ; then
    _get_child __t1 $type 1
    _get_child __t2 $type 2
    _comp_struct __ $__t1 $__t2
  elif _get_op __t3 $type; [ $__t3 = $_UNION_KW ] ; then
    defstr __str_305 "handle_enum_struct_union_type_decl: union not supported"
    _fatal_error __ $__str_305
  fi
  endlet $1 __t3 __t2 __t1 type
}

: $((__t1 = type = decl = decls = node = 0))
_handle_typedef() { let node $2
  let decls; let decl; let type; let __t1
  _get_child decls $node 0
  _car decl $decls
  _get_child type $decl 1
  _get_type_specifier __t1 $type
  _handle_enum_struct_union_type_decl __ $__t1
  endlet $1 __t1 type decl decls node
}

: $((__t1 = op = declarations = node = 0))
_comp_glo_decl() { let node $2
  let declarations; let op; let __t1
  _get_op op $node
  _fun_gensym_ix=0
  if [ $op = $_DECLS ] ; then
    if _get_child __t1 $node 1; [ $__t1 = $_EXTERN_KW ] ; then
      endlet $1 __t1 op declarations node
      return
    fi
    _get_child declarations $node 0
    while [ $declarations != 0 ]; do
      _car __t1 $declarations
      _comp_glo_var_decl __ $__t1
      _cdr declarations $declarations
    done
  elif [ $op = $_FUN_DECL ] ; then
    _comp_glo_fun_decl __ $node
  elif [ $op = $_TYPEDEF_KW ] ; then
    _handle_typedef __ $node
  elif [ $op = $_ENUM_KW ] || [ $op = $_STRUCT_KW ] || [ $op = $_UNION_KW ] ; then
    _handle_enum_struct_union_type_decl __ $node
  else
    defstr __str_306 "comp_glo_decl: unexpected declaration"
    _fatal_error __ $__str_306
  fi
  endlet $1 __t1 op declarations node
}

: $((__t1 = c = 0))
_codegen_end() {
  let c; let __t1
  c=0
  if [ $_any_character_used != 0 ] ; then
    printf "#_ Character constants\n"
    while [ $c -lt 256 ]; do
      if [ $((_$((_characters_useds + (c / 16))) & (1 << (c % 16)))) != 0 ] ; then
        printf "readonly "
        _character_ident __t1 $c
        _print_text __ $__t1
        printf "="
        printf "%d" $c
        printf "\n"
      fi
      : $((c += 1))
    done
  fi
  printf "#_ Runtime library\n"
  _produce_runtime __
  if [ $_main_defined != 0 ] ; then
    printf "__code=0; # Exit code\n"
    if [ $_runtime_use_make_argv != 0 ] ; then
      printf "make_argv \$((\$# + 1)) \"\$0\" \"\$@\" # Setup argc/argv\n"
      printf "_main __code \$((\$# + 1)) \$__argv\n"
    else
      printf "_main __code\n"
    fi
    printf "exit \$__code\n"
  fi
  endlet $1 __t1 c
}

: $((__t2 = __t1 = counter = res = ident = env = 0))
_initialize_function_variables() {
  let env; let ident; let res; let counter; let __t1; let __t2
  env=$_cgc_locals_fun
  res=0
  counter=$_fun_gensym_ix
  while [ $counter -gt 0 ]; do
    _new_fresh_ident ident $counter
    _format_special_var __t1 $ident 0
    defstr __str_204 " = "
    _wrap_str_lit __t2 $__str_204
    _concatenate_strings_with res $res $__t1 $__t2
    : $((counter -= 1))
  done
  while [ $env != 0 ]; do
    ident=$((_$((_heap + env + 2))))
    if [ $((_$((_heap + env + 1)))) != $_BINDING_PARAM_LOCAL ] || { _is_constant_type __t1 $((_$((_heap + env + 4)))); [ $((!__t1)) != 0 ]; } ; then
      _local_var __t1 $ident
      defstr __str_204 " = "
      _wrap_str_lit __t2 $__str_204
      _concatenate_strings_with res $res $__t1 $__t2
    fi
    env=$((_$((_heap + env))))
  done
  if [ $res != 0 ] ; then
    defstr __str_263 ": \$(("
    _wrap_str_lit __t1 $__str_263
    defstr __str_307 " = 0))"
    _wrap_str_lit __t2 $__str_307
    _string_concat3 res $__t1 $res $__t2
  fi
  : $(($1 = res))
  endlet $1 __t2 __t1 counter res ident env
}

_codegen_begin() {
  _malloc _text_pool $((1000000 * 1))
  _malloc _characters_useds $((16 * 1))
  _malloc _preallocated_fresh_idents $((10 * 1))
  _malloc _preallocated_dollar_idents $((10 * 1))
  _malloc _glo_decls $((100000 * 1))
  _init_comp_context __
  printf "#!/bin/sh\n"
  printf "set -e -u -f\n"
  printf "LC_ALL=C\n\n"
}

: $((__t1 = var_init_fixup = decl = 0))
_codegen_glo_decl() { let decl $2
  let var_init_fixup; let __t1
  _glo_decl_ix=0
  _text_alloc=1
  : $((_cgc_locals = _cgc_locals_fun = 0))
  _cgc_fs=1
  _append_glo_decl_fixup var_init_fixup
  _comp_glo_decl __ $decl
  _initialize_function_variables __t1
  _fixup_glo_decl __ $var_init_fixup $__t1
  _print_glo_decls __
  endlet $1 __t1 var_init_fixup decl
}

: $((acc = value_symbol = macro_symbol = start = opt = 0))
_handle_macro_D() { let opt $2
  let start; let macro_symbol; let value_symbol; let acc
  start=$opt
  _begin_symbol __
  while [ $((_$opt)) != 0 ] && [ $((_$opt)) != $__EQ__ ]; do
    _accum_symbol_char __ $((_$opt))
    : $((opt += 1))
  done
  _end_symbol macro_symbol
  _set_symbol_type __ $macro_symbol $_MACRO
  if [ $((_$opt)) = $__EQ__ ] ; then
    : $((opt += 1))
    if [ $((_$opt)) = $__DQUOTE__ ] ; then
      : $((opt += 1))
      start=$opt
      while [ $((_$opt)) != 0 ] && [ $((_$opt)) != $__DQUOTE__ ]; do
        : $((opt += 1))
      done
      if [ $((_$opt)) = 0 ] ; then
        defstr __str_308 "Unterminated string literal"
        _fatal_error __ $__str_308
      fi
      : $((_$opt = 0))
      _intern_str value_symbol $start
      : $((_$opt = __DQUOTE__))
      _set_builtin_string_macro __ $macro_symbol $value_symbol
    elif [ $__0__ -le $((_$opt)) ] && [ $((_$opt)) -le $__9__ ] ; then
      acc=0
      while [ $__0__ -le $((_$opt)) ] && [ $((_$opt)) -le $__9__ ]; do
        acc=$((acc * 10))
        acc=$((acc + (_$opt - __0__)))
        : $((opt += 1))
      done
      if [ $((_$opt)) != 0 ] ; then
        defstr __str_309 "Invalid macro definition value"
        _fatal_error __ $__str_309
      fi
      _set_builtin_int_macro __ $macro_symbol $acc
    elif [ $((_$opt)) = $__NUL__ ] ; then
      _set_builtin_empty_macro __ $macro_symbol
    else
      defstr __str_309 "Invalid macro definition value"
      _fatal_error __ $__str_309
    fi
  else
    _set_builtin_int_macro __ $macro_symbol 1
  fi
  endlet $1 acc value_symbol macro_symbol start opt
}

: $((opt = 0))
_handle_macro_U() { let opt $2
  _init_ident __ $_IDENTIFIER $opt
  endlet $1 opt
}

_newline_accumulated=0
: $((c = 0))
_drop_rest_of_line() { # fd: $2
  let c
  while { _read_char c $2; [ $c != -1 ]; } && [ $c != $__LF__ ]; do
    :
  done
  _newline_accumulated=0
  endlet $1 c
}

: $((c = prefix = 0))
_output_rest_of_line() { let prefix $3 # fd: $2
  let c
  while [ $_newline_accumulated -gt 0 ]; do
    printf "\n"
    : $((_newline_accumulated -= 1))
  done
  if [ $prefix != 0 ] ; then
    _putstr __ $prefix
  fi
  while { _read_char c $2; [ $c != -1 ]; } && [ $c != $__LF__ ]; do
    printf %b \\0$((c/64))$((c/8%8))$((c%8))
  done
  if [ $c = $__LF__ ] ; then
    printf "\n"
  fi
  endlet $1 c prefix
}

: $((sh_fp = c = 0))
_extract_c_code_from_annotated_file() { # filename: $2
  let c; let sh_fp
  _open sh_fp $2 0 0
  if [ $sh_fp -lt 0 ] ; then
    defstr __str_310 "could not open .sh file for reading"
    _fatal_error __ $__str_310
    endlet $1 sh_fp c
    return
  fi
  _drop_rest_of_line __ $sh_fp
  while _read_char c $sh_fp; [ $c != -1 ]; do
    if [ $c = $__LF__ ] ; then
      : $((_newline_accumulated += 1))
    elif [ $c = $__HASH__ ] ; then
      _read_char c $sh_fp
      if [ $c = $__SPACE__ ] ; then
        _output_rest_of_line __ $sh_fp 0
      elif [ $c = $__HASH__ ] ; then
        defstr __str_311 "//"
        _output_rest_of_line __ $sh_fp $__str_311
        if [ $c = $__LF__ ] ; then
          printf "\n"
        fi
      elif [ $c = $__LF__ ] ; then
        printf "\n"
      else
        _drop_rest_of_line __ $sh_fp
      fi
    else
      _drop_rest_of_line __ $sh_fp
    fi
  done
  _close __ $sh_fp
  endlet $1 sh_fp c
}

: $((decl = i = argv_ = argc = 0))
_main() { let argc $2; let argv_ $3
  let i; let decl
  i=1
  _malloc _include_stack $((10 * 5 * 1))
  _malloc _string_pool $((250000 * 1))
  _malloc _heap $((786432 * 1))
  _malloc _if_macro_stack $((20 * 1))
  _malloc _macro_stack $((180 * 1))
  _malloc _io_buf 1
  _init_ident_table __
  _init_pnut_macros __
  while [ $i -lt $argc ]; do
    if [ $((_$((_$((argv_ + i)) + 0)))) = $__MINUS__ ] ; then
      if [ 0 != 0 ] ; then
        :
      elif [ $((_$((_$((argv_ + i)) + 1)))) = $__D__ ] ; then
        if [ $((_$((_$((argv_ + i)) + 2)))) = 0 ] ; then
          if [ $((_$((argv_ + i + 1)))) = 0 ] ; then
            defstr __str_312 "missing macro name for -D option"
            _fatal_error __ $__str_312
          fi
          : $((i += 1))
          _handle_macro_D __ $((_$((argv_ + i))))
        else
          _handle_macro_D __ $((_$((argv_ + i)) + 2))
        fi
      elif [ $((_$((_$((argv_ + i)) + 1)))) = $__U__ ] ; then
        if [ $((_$((_$((argv_ + i)) + 2)))) = 0 ] ; then
          if [ $((_$((argv_ + i + 1)))) = 0 ] ; then
            defstr __str_313 "missing macro name for -U option"
            _fatal_error __ $__str_313
          fi
          : $((i += 1))
          _handle_macro_U __ $((_$((argv_ + i))))
        else
          _handle_macro_U __ $((_$((argv_ + i)) + 2))
        fi
      elif [ $((_$((_$((argv_ + i)) + 1)))) = $__I__ ] ; then
        if [ $_include_search_path != 0 ] ; then
          defstr __str_314 "only one include path allowed"
          _fatal_error __ $__str_314
        fi
        if [ $((_$((_$((argv_ + i)) + 2)))) = 0 ] ; then
          if [ $((_$((argv_ + i + 1)))) = 0 ] ; then
            defstr __str_315 "missing path for -I option"
            _fatal_error __ $__str_315
          fi
          : $((i += 1))
          _include_search_path=$((_$((argv_ + i))))
        else
          _include_search_path=$((_$((argv_ + i)) + 2))
        fi
      elif [ $((_$((_$((argv_ + i)) + 1)))) = $__C__ ] ; then
        if [ $((_$((_$((argv_ + i)) + 2)))) = 0 ] ; then
          if [ $((_$((argv_ + i + 1)))) = 0 ] ; then
            defstr __str_316 "missing input file name for -C option"
            _fatal_error __ $__str_316
          fi
          : $((i += 1))
          _extract_c_code_from_annotated_file __ $((_$((argv_ + i))))
        else
          _extract_c_code_from_annotated_file __ $((_$((argv_ + i)) + 2))
        fi
        : $(($1 = 0))
        endlet $1 decl i argv_ argc
        return
      else
        printf "Option "
        _putstr __ $((_$((argv_ + i))))
        printf "\n"
        defstr __str_317 "unknown option"
        _fatal_error __ $__str_317
      fi
    else
      _include_file __ $((_$((argv_ + i)))) 0
    fi
    : $((i += 1))
  done
  if [ $_fd = -1 ] ; then
    printf "Usage: "
    _putstr __ $((_$((argv_ + 0))))
    printf " <filename>\n"
    defstr __str_318 "no input file"
    _fatal_error __ $__str_318
  fi
  _ch=$__LF__
  _codegen_begin __
  _get_tok __
  while [ $_tok != -1 ]; do
    _parse_declaration decl 0
    _codegen_glo_decl __ $decl
  done
  _codegen_end __
  : $(($1 = 0))
  endlet $1 decl i argv_ argc
}

#_ Character constants
readonly __NUL__=0
readonly __BEL__=7
readonly __BS__=8
readonly __HT__=9
readonly __LF__=10
readonly __VT__=11
readonly __FF__=12
readonly __CR__=13
readonly __SPACE__=32
readonly __EXCL__=33
readonly __DQUOTE__=34
readonly __HASH__=35
readonly __DOLLAR__=36
readonly __PERCENT__=37
readonly __AMP__=38
readonly __QUOTE__=39
readonly __LPAREN__=40
readonly __RPAREN__=41
readonly __STAR__=42
readonly __PLUS__=43
readonly __COMMA__=44
readonly __MINUS__=45
readonly __PERIOD__=46
readonly __SLASH__=47
readonly __0__=48
readonly __7__=55
readonly __9__=57
readonly __COLON__=58
readonly __SEMICOLON__=59
readonly __LT__=60
readonly __EQ__=61
readonly __GT__=62
readonly __QUESTION__=63
readonly __A__=65
readonly __C__=67
readonly __D__=68
readonly __I__=73
readonly __U__=85
readonly __X__=88
readonly __Z__=90
readonly __LBRACK__=91
readonly __BACKSLASH__=92
readonly __RBRACK__=93
readonly __CARET__=94
readonly __UNDERSCORE__=95
readonly __BACKTICK__=96
readonly __a__=97
readonly __b__=98
readonly __c__=99
readonly __d__=100
readonly __f__=102
readonly __i__=105
readonly __l__=108
readonly __n__=110
readonly __o__=111
readonly __r__=114
readonly __s__=115
readonly __t__=116
readonly __u__=117
readonly __v__=118
readonly __x__=120
readonly __z__=122
readonly __LBRACE__=123
readonly __BAR__=124
readonly __RBRACE__=125
readonly __TILDE__=126
#_ Runtime library
__ALLOC=1 # Starting heap at 1 because 0 is the null pointer.

_malloc() { # $2 = object size
  : $((_$__ALLOC = $2)) # Track object size
  : $(($1 = $__ALLOC + 1))
  : $((__ALLOC += $2 + 1))
}

__c2i_0=48
__c2i_1=49
__c2i_2=50
__c2i_3=51
__c2i_4=52
__c2i_5=53
__c2i_6=54
__c2i_7=55
__c2i_8=56
__c2i_9=57
__c2i_a=97
__c2i_b=98
__c2i_c=99
__c2i_d=100
__c2i_e=101
__c2i_f=102
__c2i_g=103
__c2i_h=104
__c2i_i=105
__c2i_j=106
__c2i_k=107
__c2i_l=108
__c2i_m=109
__c2i_n=110
__c2i_o=111
__c2i_p=112
__c2i_q=113
__c2i_r=114
__c2i_s=115
__c2i_t=116
__c2i_u=117
__c2i_v=118
__c2i_w=119
__c2i_x=120
__c2i_y=121
__c2i_z=122
__c2i_A=65
__c2i_B=66
__c2i_C=67
__c2i_D=68
__c2i_E=69
__c2i_F=70
__c2i_G=71
__c2i_H=72
__c2i_I=73
__c2i_J=74
__c2i_K=75
__c2i_L=76
__c2i_M=77
__c2i_N=78
__c2i_O=79
__c2i_P=80
__c2i_Q=81
__c2i_R=82
__c2i_S=83
__c2i_T=84
__c2i_U=85
__c2i_V=86
__c2i_W=87
__c2i_X=88
__c2i_Y=89
__c2i_Z=90
char_to_int() {
  case $1 in
    [[:alnum:]]) __c=$((__c2i_$1)) ;;
    ' ') __c=32 ;;
    '!') __c=33 ;;
    '"') __c=34 ;;
    '#') __c=35 ;;
    '$') __c=36 ;;
    '%') __c=37 ;;
    '&') __c=38 ;;
    "'") __c=39 ;;
    '(') __c=40 ;;
    ')') __c=41 ;;
    '*') __c=42 ;;
    '+') __c=43 ;;
    ',') __c=44 ;;
    '-') __c=45 ;;
    '.') __c=46 ;;
    '/') __c=47 ;;
    ':') __c=58 ;;
    ';') __c=59 ;;
    '<') __c=60 ;;
    '=') __c=61 ;;
    '>') __c=62 ;;
    '?') __c=63 ;;
    '@') __c=64 ;;
    '[') __c=91 ;;
    '\') __c=92 ;;
    ']') __c=93 ;;
    '^') __c=94 ;;
    '_') __c=95 ;;
    '`') __c=96 ;;
    '{') __c=123 ;;
    '|') __c=124 ;;
    '}') __c=125 ;;
    '~') __c=126 ;;
    *)
      __c=$(printf "%d" "'$1"); __c=$((__c > 0 ? __c : 256 + __c)) ;;
  esac
}

next_sub_buffer() {
  if [ -z "$__us_buf256" ]; then
    if [ ${#__str} -ge 256 ]; then
      __temp="${__str#????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????}"
      __us_buf256="${__str%"$__temp"}"
      __str="$__temp"
    else
      __us_buf256="$__str"
      __str=
    fi
  fi
  if [ -z "$__us_buf16" ]; then
    if [ ${#__us_buf256} -ge 16 ]; then
      __temp="${__us_buf256#????????????????}"
      __us_buf16="${__us_buf256%"$__temp"}"
      __us_buf256="$__temp"
    else
      __us_buf16="$__us_buf256"
      __us_buf256=
    fi
  fi
}
unpack_escaped_string() { # $1 = string, $2 = size (optional)
  __str="$1"
  # Allocates enough space for all characters, assuming that no character is escaped
  _malloc __addr $((${2:-${#__str} + 1}))
  __ptr=$__addr
  __end=$((__ptr + ${2:-${#__str} + 1})) # End of allocated memory
  __us_buf16=
  __us_buf256=
  while [ ! -z "$__str" ] || [ ! -z "$__us_buf256" ] ; do
    next_sub_buffer
    while [ ! -z "$__us_buf16" ]; do
      case "$__us_buf16" in
        '\'*)
          __us_buf16="${__us_buf16#?}" # Remove the current char from $__us_buf16
          if [ -z "$__us_buf16" ]; then next_sub_buffer; fi
          case "$__us_buf16" in
            '0'*) __c=0 ;;
            'a'*) __c=7 ;;
            'b'*) __c=8 ;;
            'f'*) __c=12 ;;
            'n'*) __c=10 ;;
            'r'*) __c=13 ;;
            't'*) __c=9 ;;
            'v'*) __c=11 ;;
            '\'*) __c=92 ;;
            '"'*) __c=34 ;;
            "'"*) __c=39 ;;
            '?'*) __c=63 ;;
            '$'*) __c=36 ;; # Not in C, used to escape variable expansion between double quotes
            *) echo "invalid escape in string: $__us_buf16"; exit 1 ;;
          esac
          __us_buf16="${__us_buf16#?}" # Remove the current char from $__us_buf16
          ;;
        *)
          char_to_int "${__us_buf16%"${__us_buf16#?}"}"
          __us_buf16="${__us_buf16#?}" # Remove the current char from $__us_buf16
          ;;
      esac
    : $((_$__ptr = __c))
    : $((__ptr += 1))
    done
  done
  while [ $__ptr -le $__end ]; do
    : $((_$__ptr = 0))
    : $((__ptr += 1))
  done
}

#_ Define a string, and return a reference to it in the varible taken as argument.
#_ If the variable is already defined, this function does nothing.
#_ Note that it's up to the caller to ensure that no 2 strings share the same variable.
defstr() { # $1 = variable name, $2 = string, $3 = size (optional)
  set +u # Necessary to allow the variable to be empty
  if [ $(($1)) -eq 0 ]; then
    unpack_escaped_string "$2" $3
    : $(($1 = __addr))
  fi
  set -u
}

_free() { # $2 = object to free
  __ptr=$(($2 - 1))          # Start of object
  __end=$((__ptr + _$__ptr)) # End of object
  while [ $__ptr -lt $__end ]; do
    unset "_$__ptr"
    : $((__ptr += 1))
  done
  : $(($1 = 0))              # Return 0
}

_put_pstr() {
  : $(($1 = 0)); shift # Return 0
  __addr=$1; shift
  while [ $((__c = _$__addr)) != 0 ]; do
    printf %b \\0$((__c/64))$((__c/8%8))$((__c%8))
    : $((__addr += 1))
  done
}

#_ Unpack a Shell string into an appropriately sized buffer
unpack_string_to_buf() { # $1: Shell string, $2: Buffer, $3: Ends with EOF?
  __fgetc_buf="$1"
  __buffer=$2
  __ends_with_eof=${3:-1}
  __fgetc_buf16=
  __stdin_buf256=
  __continue=1
  while [ $__continue != 0 ] ; do
    if [ -z "$__stdin_buf256" ]; then
      if [ ${#__fgetc_buf} -ge 256 ]; then
        __temp="${__fgetc_buf#????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????}"
        __stdin_buf256="${__fgetc_buf%"$__temp"}"
        __fgetc_buf="$__temp"
      else
        __stdin_buf256="$__fgetc_buf"
        __fgetc_buf=
      fi
    fi
    if [ -z "$__fgetc_buf16" ]; then
      if [ ${#__stdin_buf256} -ge 16 ]; then
        __temp="${__stdin_buf256#????????????????}"
        __fgetc_buf16="${__stdin_buf256%"$__temp"}"
        __stdin_buf256="$__temp"
      else
        __fgetc_buf16="$__stdin_buf256"
        __stdin_buf256=
        __continue=0
      fi
    fi
    while [ ! -z "$__fgetc_buf16" ]; do
      case "$__fgetc_buf16" in
        " "*) : $((_$__buffer = 32))  ;;
        "e"*) : $((_$__buffer = 101)) ;;
        "="*) : $((_$__buffer = 61))  ;;
        "t"*) : $((_$__buffer = 116)) ;;
        ";"*) : $((_$__buffer = 59))  ;;
        "i"*) : $((_$__buffer = 105)) ;;
        ")"*) : $((_$__buffer = 41))  ;;
        "("*) : $((_$__buffer = 40))  ;;
        "n"*) : $((_$__buffer = 110)) ;;
        "s"*) : $((_$__buffer = 115)) ;;
        "l"*) : $((_$__buffer = 108)) ;;
        "+"*) : $((_$__buffer = 43))  ;;
        "p"*) : $((_$__buffer = 112)) ;;
        "a"*) : $((_$__buffer = 97))  ;;
        "r"*) : $((_$__buffer = 114)) ;;
        "f"*) : $((_$__buffer = 102)) ;;
        "d"*) : $((_$__buffer = 100)) ;;
        "*"*) : $((_$__buffer = 42))  ;;
        *)
          char_to_int "${__fgetc_buf16%"${__fgetc_buf16#?}"}"
          : $((_$__buffer = __c))
          ;;
      esac
      __fgetc_buf16="${__fgetc_buf16#?}"  # Remove the first character
      : $((__buffer += 1))              # Move to the next buffer position
    done
  done

  if [ $__ends_with_eof -eq 0 ]; then # Ends with newline and not EOF?
    : $((_$__buffer = 10))            # Line ends with newline
    : $((__buffer += 1))
  fi
  : $((_$__buffer = 0))               # Then \0
}

refill_buffer() { # $1: fd
  __fd=$1
  __buffer=$((__buffer_fd$__fd))

  IFS=
  __ends_with_eof=0
  read -r __temp_buf <&$__fd || __ends_with_eof=1

  # Check that the buffer is large enough to unpack the line
  __buflen=$((__buflen_fd$__fd - 2)) # Minus 2 to account for newline and \0
  __len=${#__temp_buf}
  if [ $__len -gt $__buflen ]; then
    # Free buffer and reallocate a new one double the line size
    __buflen=$((__len * 2))
    _free __ $__buffer
    _malloc __buffer $__buflen
    : $((__buffer_fd$__fd = __buffer))
    : $((__buflen_fd$__fd = __buflen))
  fi
  unpack_string_to_buf "$__temp_buf" $__buffer $__ends_with_eof
}

read_byte() { # $2: fd
  __fd=$2
  : $((__buffer=__buffer_fd$__fd))
  : $((__cursor=__cursor_fd$__fd))
  # The cursor is at the end of the buffer, we need to read the next line
  if [ $((_$((__buffer + __cursor)))) -eq 0 ]; then
    # Buffer has been read completely, read next line
    refill_buffer $__fd
    __cursor=0 # Reset cursor and reload buffer
    : $((__buffer=__buffer_fd$__fd))
    if [ $((_$((__buffer + __cursor)))) -eq 0 ]; then
      : $(($1 = -1)) # EOF
      return
    fi
  fi
  : $(($1 = _$((__buffer + __cursor))))
  : $((__cursor_fd$__fd = __cursor + 1))  # Increment cursor
}

_malloc __buffer_fd0 1000   # Allocate buffer
: $((_$__buffer_fd0 = 0))   # Init buffer to ""
: $((__cursor_fd0 = 0))     # Make buffer empty
: $((__buflen_fd0 = 1000))  # Init buffer length
__state_fd0=0 # stdin
__state_fd1=1 # stdout
__state_fd2=2 # stderr
__state_fd3=-1
__state_fd4=-1
__state_fd5=-1
__state_fd6=-1
__state_fd7=-1
__state_fd8=-1
__state_fd9=-1

_open() { # $2: filename, $3: flags, $4: mode
  # Get available fd
  __fd=0
  while [ $__fd -lt 10 ]; do
    if [ $((__state_fd$__fd)) -lt 0 ]; then
      break
    fi
    : $((__fd += 1))
  done
  if [ $__fd -gt 9 ] ; then
    # Some shells don't support fd > 9
    echo "No more file descriptors available to open $(_put_pstr __ $2)" ; exit 1
  else
    # Because the file must be read line-by-line, and string
    # values can't be assigned to dynamic variables, each line
    # is read and then unpacked in the buffer.
    _malloc __addr 1000                 # Allocate buffer
    : $((_$__addr = 0))                 # Init buffer to ""
    : $((__buffer_fd$__fd = __addr))    # Buffer address
    : $((__cursor_fd$__fd = 0))         # Buffer cursor
    : $((__buflen_fd$__fd = 1000))      # Buffer length
    : $((__state_fd$__fd = $3))         # Mark the fd as opened
    __res=$(_put_pstr __ $2)
    if [ $3 = 0 ] ; then
      case $__fd in
        0) exec 0< "$__res" ;; 1) exec 1< "$__res" ;; 2) exec 2< "$__res" ;;
        3) exec 3< "$__res" ;; 4) exec 4< "$__res" ;; 5) exec 5< "$__res" ;;
        6) exec 6< "$__res" ;; 7) exec 7< "$__res" ;; 8) exec 8< "$__res" ;;
        9) exec 9< "$__res" ;;
      esac
    elif [ $3 = 1 ] ; then
      case $__fd in
        0) exec 0> "$__res" ;; 1) exec 1> "$__res" ;; 2) exec 2> "$__res" ;;
        3) exec 3> "$__res" ;; 4) exec 4> "$__res" ;; 5) exec 5> "$__res" ;;
        6) exec 6> "$__res" ;; 7) exec 7> "$__res" ;; 8) exec 8> "$__res" ;;
        9) exec 9> "$__res" ;;
      esac
    elif [ $3 = 2 ] ; then
      case $__fd in
        0) exec 0>> "$__res" ;; 1) exec 1>> "$__res" ;; 2) exec 2>> "$__res" ;;
        3) exec 3>> "$__res" ;; 4) exec 4>> "$__res" ;; 5) exec 5>> "$__res" ;;
        6) exec 6>> "$__res" ;; 7) exec 7>> "$__res" ;; 8) exec 8>> "$__res" ;;
        9) exec 9>> "$__res" ;;
      esac
    else
      echo "Unknown file mode" ; exit 1
    fi
  fi
  : $(($1 = __fd))
}

_read() { : $((__fd = $2)) $((__buf = $3)) $((__count = $4))
  : $((__i = 0))
  while [ $__i -lt $__count ] ; do
    read_byte __byte $__fd
    if [ $__byte -lt 0 ] ; then break; fi
    : $((_$((__buf + __i)) = __byte))
    : $((__i += 1))
  done
  : $(($1 = __i))
}

_close() { # $2: fd
  __fd=$2
  __buf=$((__buffer_fd$__fd))  # Get buffer
  _free __ $__buf              # Release buffer
  : $((__state_fd$__fd = -1))  # Mark the fd as closed
  case $__fd in
    0) exec 0<&- ;; 1) exec 1<&- ;; 2) exec 2<&- ;;
    3) exec 3<&- ;; 4) exec 4<&- ;; 5) exec 5<&- ;;
    6) exec 6<&- ;; 7) exec 7<&- ;; 8) exec 8<&- ;;
    9) exec 9<&- ;;
  esac
  : $(($1 = 0))
}

make_argv() {
  __argc=$1; shift;
  _malloc __argv $((__argc + 1)) # Allocate enough space for all elements and null terminator.
  __argv_ptr=$__argv

  while [ $# -ge 1 ]; do
    _malloc _$__argv_ptr $((${#1} + 1))
    unpack_string_to_buf "$1" $((_$__argv_ptr)) 1
    : $((__argv_ptr += 1))
    shift
  done
  : $((_$__argv_ptr = 0)) # Null-terminate the argv array
}

#_ Local variables
__=0
__SP=0
let() { # $1: variable name, $2: value (optional)
  : $((__$((__SP += 1))=$1)) # Push
  : $(($1=${2-0}))           # Init
}
endlet() { # $1: return variable
           # $2...: function local variables
  __ret=$1 # Don't overwrite return value
  : $((__tmp = $__ret))
  while [ $# -ge 2 ]; do
    : $(($2 = __$(((__SP -= 1) + 1)))) # Pop
    shift;
  done
  : $(($__ret=__tmp))   # Restore return value
}

_isatty() { # $2: fd
  [ -t $2 ] && : $(($1 = 1)) || : $(($1 = 0))
}

__code=0; # Exit code
make_argv $(($# + 1)) "$0" "$@" # Setup argc/argv
_main __code $(($# + 1)) $__argv
exit $__code
