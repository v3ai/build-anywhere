// sh-float.c: floating point for the POSIX shell backend.
// Added by build-anywhere; BSD 2-Clause, like the rest of pnut.
//
// Shell arithmetic only has integers. A double is kept as its IEEE-754 bit
// pattern in a 64-bit shell integer, and floating-point operations are
// calls to a software floating-point library compiled with the program
// (build-anywhere's seed/pnut-libc/float.c). Before a top-level declaration
// is compiled, the pass below works out the type of every expression and
// rewrites what involves a double:
//
//   a + b, a - b, a * b, a / b      ba_dadd(a, b), ba_dsub, ba_dmul, ba_ddiv
//   -a                              ba_dneg(a)
//   a < b, a <= b, a == b, ...      ba_dlt(a, b), ba_dle, ba_deq (NaN-aware)
//   if (a), !a, a && b              ba_dtrue(a)
//   int <-> double                  ba_itod(i), ba_dtoi(d), on assignment,
//                                   arguments, return values and casts
//   printf("%.3f", x)               printf("%s", ba_dfmt(x, 'f', flags, -1, 3))
//
// float and long double are computed as double. Code without floating point
// is not changed.

ast fl_ty;             // type of the expression fl_expr last returned
ast fl_ret_ty;         // return type of the function being compiled
ast fl_t_int;
ast fl_t_double;
ast fl_t_charp;
bool fl_initialized = false;

int FL_DADD_ID; int FL_DSUB_ID; int FL_DMUL_ID; int FL_DDIV_ID; int FL_DNEG_ID;
int FL_DLT_ID; int FL_DLE_ID; int FL_DEQ_ID; int FL_DTRUE_ID;
int FL_ITOD_ID; int FL_DTOI_ID; int FL_DFMT_ID; int FL_BITS_ID; int FL_FROM_BITS_ID; int FL_SEL_ID;

// Types of globals and functions (by identifier) and struct definitions
// (by tag, stored as -tag), in an open-addressing hash table.
#define FL_HASH 8192
int fl_g_key[FL_HASH];
ast fl_g_val[FL_HASH];
int fl_g_count = 0;

// Types of the locals and parameters in scope.
#define FL_LOCALS 1000
int fl_l_key[FL_LOCALS];
ast fl_l_val[FL_LOCALS];
int fl_nl = 0;

void fl_init() {
  fl_initialized = true;
  fl_t_int = new_ast0(INT_KW, 0);
  fl_t_double = new_ast0(DOUBLE_KW, 0);
  fl_t_charp = new_ast2('*', 0, new_ast0(CHAR_KW, 0));
  FL_DADD_ID  = init_ident(IDENTIFIER, "ba_dadd");
  FL_DSUB_ID  = init_ident(IDENTIFIER, "ba_dsub");
  FL_DMUL_ID  = init_ident(IDENTIFIER, "ba_dmul");
  FL_DDIV_ID  = init_ident(IDENTIFIER, "ba_ddiv");
  FL_DNEG_ID  = init_ident(IDENTIFIER, "ba_dneg");
  FL_DLT_ID   = init_ident(IDENTIFIER, "ba_dlt");
  FL_DLE_ID   = init_ident(IDENTIFIER, "ba_dle");
  FL_DEQ_ID   = init_ident(IDENTIFIER, "ba_deq");
  FL_DTRUE_ID = init_ident(IDENTIFIER, "ba_dtrue");
  FL_ITOD_ID  = init_ident(IDENTIFIER, "ba_itod");
  FL_DTOI_ID  = init_ident(IDENTIFIER, "ba_dtoi");
  FL_DFMT_ID  = init_ident(IDENTIFIER, "ba_dfmt");
  FL_SEL_ID   = init_ident(IDENTIFIER, "ba_sel");
  // ba_bits(d) and ba_from_bits(i) reinterpret a double as its bits and
  // back; they generate no code
  FL_BITS_ID  = init_ident(IDENTIFIER, "ba_bits");
  FL_FROM_BITS_ID = init_ident(IDENTIFIER, "ba_from_bits");
}

int fl_hash_slot(int key) {
  int h = key;
  if (h < 0) h = -h;
  h = h % FL_HASH;
  while (fl_g_key[h] != 0 && fl_g_key[h] != key) {
    h = (h + 1) % FL_HASH;
  }
  return h;
}

void fl_g_put(int key, ast val) {
  int h = fl_hash_slot(key);
  if (fl_g_key[h] == 0) {
    fl_g_count += 1;
    if (fl_g_count >= FL_HASH - 1) fatal_error("too many global declarations");
  }
  fl_g_key[h] = key;
  fl_g_val[h] = val;
}

ast fl_g_get(int key) {
  int h = fl_hash_slot(key);
  if (fl_g_key[h] == 0) return 0;
  return fl_g_val[h];
}

void fl_l_put(int key, ast val) {
  if (fl_nl >= FL_LOCALS) fatal_error("too many local variables");
  fl_l_key[fl_nl] = key;
  fl_l_val[fl_nl] = val;
  fl_nl += 1;
}

ast fl_lookup(int ident) {
  int i = fl_nl - 1;
  while (i >= 0) {
    if (fl_l_key[i] == ident) return fl_l_val[i];
    i -= 1;
  }
  return fl_g_get(ident);
}

bool fl_is_dbl(ast t) {
  int op;
  if (t == 0) return false;
  op = get_op(t);
  return op == DOUBLE_KW || op == FLOAT_KW;
}

bool fl_is_ptr(ast t) {
  int op;
  if (t == 0) return false;
  op = get_op(t);
  return op == '*' || op == '[';
}

// An arithmetic type other than double: what ba_dtoi converts to.
bool fl_is_int(ast t) {
  int op;
  if (t == 0) return true;
  op = get_op(t);
  return op == INT_KW || op == CHAR_KW || op == SHORT_KW || op == LONG_KW || op == ENUM_KW;
}

ast fl_pointee(ast t) {
  if (t == 0) return 0;
  if (get_op(t) == '*') return get_child(t, 1);
  if (get_op(t) == '[') return get_child(t, 0);
  return 0;
}

// Record the struct definitions that appear in a type.
void fl_note_type(ast t) {
  int op;
  ast members;
  while (t != 0) {
    op = get_op(t);
    if (op == '*') {
      t = get_child(t, 1);
    } else if (op == '[') {
      t = get_child(t, 0);
    } else if (op == '(') {
      t = get_child(t, 0);
    } else if (op == STRUCT_KW || op == UNION_KW) {
      members = get_child(t, 2);
      if (members != 0 && get_child(t, 1) != 0) {
        if (fl_g_get(-get_val(get_child(t, 1))) == t) return; // already seen
        fl_g_put(-get_val(get_child(t, 1)), t);
      }
      while (members != 0) {
        fl_note_type(get_child(car(members), 1));
        members = tail(members);
      }
      return;
    } else {
      return;
    }
  }
}

// Type of member `ident` of the struct or union type t, or 0.
ast fl_member(ast t, int ident) {
  ast members;
  ast decl;
  ast r;
  int op;
  if (t == 0) return 0;
  op = get_op(t);
  if (op != STRUCT_KW && op != UNION_KW) return 0;
  members = get_child(t, 2);
  if (members == 0 && get_child(t, 1) != 0) {
    t = fl_g_get(-get_val(get_child(t, 1)));
    if (t == 0) return 0;
    members = get_child(t, 2);
  }
  while (members != 0) {
    decl = car(members);
    if (get_child(decl, 0) == 0) { // anonymous struct or union member
      r = fl_member(get_child(decl, 1), ident);
      if (r != 0) return r;
    } else if (get_val(get_child(decl, 0)) == ident) {
      return get_child(decl, 1);
    }
    members = tail(members);
  }
  return 0;
}

ast fl_call1(int id, ast a) {
  return new_ast2('(', new_ast0(IDENTIFIER, id), cons(a, 0));
}

ast fl_call2(int id, ast a, ast b) {
  return new_ast2('(', new_ast0(IDENTIFIER, id), cons(a, cons(b, 0)));
}

// A double literal from its four 16-bit pieces.
ast fl_lit(int b0, int b1, int b2, int b3) {
  int obj = alloc_obj(4);
  heap[obj] = b0;
  heap[obj + 1] = b1;
  heap[obj + 2] = b2;
  heap[obj + 3] = b3;
  return new_ast0(DOUBLE_LIT, obj);
}

// The literal (double) n, when e is an integer constant n; otherwise 0.
ast fl_int_lit_to_dbl(ast e) {
  int op = get_op(e);
  int v;
  int neg = 0;
  int n = 0;
  int i;
  int d;
  if (op == INTEGER) {
    v = get_val(e);           // INTEGER nodes hold the negated value
  } else if (op == CHARACTER) {
    v = -get_val(e);
  } else if (op == '-' && get_nb_children(e) == 1 && get_op(get_child(e, 0)) == INTEGER) {
    v = -get_val(get_child(e, 0));
  } else {
    return 0;
  }
  // v is minus the value; digits are taken from the non-positive side so
  // that the most negative int works too
  if (v > 0) {
    neg = 1;
    v = -v;
  }
  while (v != 0) {
    d = -(v % 10);
    fl_digits[n] = d;
    n += 1;
    v = v / 10;
  }
  i = 0;
  while (i < n / 2) { // reverse
    d = fl_digits[i];
    fl_digits[i] = fl_digits[n - 1 - i];
    fl_digits[n - 1 - i] = d;
    i += 1;
  }
  fl_convert(fl_digits, n, 0, 0, neg);
  return fl_lit(fl_bits[0], fl_bits[1], fl_bits[2], fl_bits[3]);
}

// Convert expression e of type from to type to.
ast fl_conv(ast e, ast from, ast to) {
  ast lit;
  if (e == 0) return e;
  if (fl_is_dbl(to) && !fl_is_dbl(from) && !fl_is_ptr(from)) {
    lit = fl_int_lit_to_dbl(e);
    if (lit != 0) return lit;
    return fl_call1(FL_ITOD_ID, e);
  }
  if (fl_is_dbl(from) && !fl_is_dbl(to) && fl_is_int(to)) {
    return fl_call1(FL_DTOI_ID, e);
  }
  return e;
}

ast fl_neg(ast e) {
  int b3;
  if (get_op(e) == DOUBLE_LIT) {
    b3 = heap[get_val(e) + 3];
    // -0.0 has no decimal shell literal, so negating 0.0 stays a call
    if (b3 != 0 || heap[get_val(e)] != 0 || heap[get_val(e) + 1] != 0 || heap[get_val(e) + 2] != 0) {
      return fl_lit(heap[get_val(e)], heap[get_val(e) + 1], heap[get_val(e) + 2], b3 ^ 32768);
    }
  }
  return fl_call1(FL_DNEG_ID, e);
}

ast fl_expr(ast e);
ast fl_expr_unused(ast e);

// Whether expression e contains a function call.
bool fl_has_call(ast e) {
  int op;
  int nb;
  int i;
  if (e == 0) return false;
  op = get_op(e);
  if (op == '(') return true;
  if (op == SIZEOF_KW) return false;
  if (op == CAST) return fl_has_call(get_child(e, 1));
  nb = get_nb_children(e);
  i = 0;
  while (i < nb) {
    if (fl_has_call(get_child(e, i))) return true;
    i += 1;
  }
  return false;
}

// e in a condition: a double tests against 0.0.
// pnut cannot compile !(a && b) in a test when a or b calls a function, which
// comparisons of doubles do: push the ! inside, !a || !b.
ast fl_test_form(ast e) {
  int op;
  ast c;
  if (e == 0) return e;
  op = get_op(e);
  if ((op == AMP_AMP || op == BAR_BAR) && get_nb_children(e) == 2) {
    set_child(e, 0, fl_test_form(get_child(e, 0)));
    set_child(e, 1, fl_test_form(get_child(e, 1)));
    return e;
  }
  if (op == '!' && get_nb_children(e) == 1) {
    c = get_child(e, 0);
    op = get_op(c);
    if ((op == AMP_AMP || op == BAR_BAR) && get_nb_children(c) == 2 && fl_has_call(c)) {
      if (op == AMP_AMP) op = BAR_BAR;
      else op = AMP_AMP;
      return new_ast2(op, fl_test_form(new_ast1('!', get_child(c, 0))),
                          fl_test_form(new_ast1('!', get_child(c, 1))));
    }
    if (op == '!' && get_nb_children(c) == 1) return fl_test_form(get_child(c, 0));
  }
  return e;
}

ast fl_cond(ast e) {
  if (e == 0) return 0;
  e = fl_expr(e);
  if (fl_is_dbl(fl_ty)) e = fl_call1(FL_DTRUE_ID, e);
  fl_ty = fl_t_int;
  return fl_test_form(e);
}

ast fl_binop(int id, ast a, ast at, ast b, ast bt) {
  return fl_call2(id, fl_conv(a, at, fl_t_double), fl_conv(b, bt, fl_t_double));
}

ast fl_printf(ast params);

// Arguments of a call to a function of type fun_type (0 if unknown).
ast fl_args(ast args, ast fun_type) {
  ast params = 0;
  ast res = 0;
  ast last = 0;
  ast a;
  ast pt;
  ast cell;
  if (fun_type != 0 && get_op(fun_type) == '(') params = get_child(fun_type, 1);
  while (args != 0) {
    a = fl_expr(car(args));
    if (params != 0) {
      pt = get_child(car(params), 1);
      a = fl_conv(a, fl_ty, pt);
      params = tail(params);
    }
    cell = cons(a, 0);
    if (res == 0) res = cell; else set_child(last, 1, cell);
    last = cell;
    args = tail(args);
  }
  return res;
}

// Lower a ++/-- on a double: pre is ++x/--x, value_unused when the value of
// the expression is not used.
ast fl_incdec(ast e, int op, ast t, bool value_unused) {
  int id = FL_DADD_ID;
  int back = FL_DSUB_ID;
  ast one = fl_lit(0, 0, 0, 16368); // 1.0
  ast assign;
  if (op == MINUS_MINUS_PRE || op == MINUS_MINUS_POST) {
    id = FL_DSUB_ID;
    back = FL_DADD_ID;
  }
  assign = new_ast2('=', e, fl_call2(id, e, one));
  if (op == PLUS_PLUS_PRE || op == MINUS_MINUS_PRE || value_unused) return assign;
  return new_ast2(',', assign, fl_call2(back, e, one));
}

ast fl_expr_go(ast e, bool value_unused) {
  int op;
  int nb;
  ast a;
  ast b;
  ast c;
  ast at;
  ast bt;
  ast t;
  int id;

  if (e == 0) { fl_ty = fl_t_int; return 0; }
  op = get_op(e);
  nb = get_nb_children(e);

  if (op == DOUBLE_LIT) {
    fl_ty = fl_t_double;
    if (heap[get_val(e) + 3] == 32768 && heap[get_val(e)] == 0 && heap[get_val(e) + 1] == 0 && heap[get_val(e) + 2] == 0) {
      return fl_call1(FL_DNEG_ID, fl_lit(0, 0, 0, 0)); // -0.0
    }
    return e;
  }
  if (op == IDENTIFIER) {
    fl_ty = fl_lookup(get_val(e));
    if (fl_ty == 0) fl_ty = fl_t_int;
    return e;
  }
  if (op == STRING) { fl_ty = fl_t_charp; return e; }
  if (nb == 0) { fl_ty = fl_t_int; return e; } // integer and character literals

  if (op == SIZEOF_KW) { fl_ty = fl_t_int; return e; }

  if (op == CAST) {
    t = get_child(get_child(e, 0), 1); // the cast's DECL holds the type
    a = fl_expr(get_child(e, 1));
    if (get_op(t) == VOID_KW) {
      set_child(e, 1, a);
    } else if (fl_is_dbl(t) || fl_is_dbl(fl_ty)) {
      a = fl_conv(a, fl_ty, t);
      if (fl_is_dbl(t)) { fl_ty = t; return a; }
      set_child(e, 1, a);
    } else {
      set_child(e, 1, a);
    }
    fl_ty = t;
    return e;
  }

  if (nb == 1) {
    if (op == PLUS_PLUS_PRE || op == MINUS_MINUS_PRE || op == PLUS_PLUS_POST || op == MINUS_MINUS_POST) {
      a = fl_expr(get_child(e, 0));
      if (fl_is_dbl(fl_ty)) return fl_incdec(a, op, fl_ty, value_unused);
      set_child(e, 0, a);
      return e;
    }
    a = fl_expr(get_child(e, 0));
    at = fl_ty;
    if (op == '-') {
      if (fl_is_dbl(at)) return fl_neg(a);
      set_child(e, 0, a);
      fl_ty = fl_t_int;
      return e;
    }
    if (op == '+') { return a; }
    if (op == '!') {
      if (fl_is_dbl(at)) a = fl_call1(FL_DTRUE_ID, a);
      set_child(e, 0, a);
      fl_ty = fl_t_int;
      return e;
    }
    if (op == '*') {
      set_child(e, 0, a);
      fl_ty = fl_pointee(at);
      if (fl_ty == 0) fl_ty = fl_t_int;
      return e;
    }
    if (op == '&') {
      set_child(e, 0, a);
      fl_ty = new_ast2('*', 0, at);
      return e;
    }
    set_child(e, 0, a); // ~
    fl_ty = fl_t_int;
    return e;
  }

  if (op == '?') {
    // pnut cannot call functions in the branches of ?:. Floating-point
    // operations have no side effects, so when only they add calls the
    // expression becomes ba_sel(c, a, b), which evaluates both branches.
    id = 0;
    if (fl_has_call(get_child(e, 1)) || fl_has_call(get_child(e, 2))) id = 1;
    c = fl_cond(get_child(e, 0));
    a = fl_expr(get_child(e, 1));
    at = fl_ty;
    b = fl_expr(get_child(e, 2));
    bt = fl_ty;
    if (fl_is_dbl(at) || fl_is_dbl(bt)) {
      a = fl_conv(a, at, fl_t_double);
      b = fl_conv(b, bt, fl_t_double);
      fl_ty = fl_t_double;
    } else if (fl_is_ptr(at)) {
      fl_ty = at;
    } else {
      fl_ty = bt;
    }
    if (!id && (fl_has_call(a) || fl_has_call(b))) {
      return new_ast2('(', new_ast0(IDENTIFIER, FL_SEL_ID), cons(c, cons(a, cons(b, 0))));
    }
    set_child(e, 0, c);
    set_child(e, 1, a);
    set_child(e, 2, b);
    return e;
  }

  if (op == '(') { // function call
    a = get_child(e, 0);
    t = 0;
    if (get_op(a) == IDENTIFIER) {
      if ((get_val(a) == FL_BITS_ID || get_val(a) == FL_FROM_BITS_ID) && get_child(e, 1) != 0) {
        b = fl_expr(car(get_child(e, 1)));
        if (get_val(a) == FL_BITS_ID) fl_ty = fl_t_int; else fl_ty = fl_t_double;
        return b;
      }
      t = fl_lookup(get_val(a));
      if (t != 0 && get_op(t) == '*') t = get_child(t, 1); // function pointer
      if (get_val(a) == PRINTF_ID && get_child(e, 1) != 0 && get_op(car(get_child(e, 1))) == STRING) {
        set_child(e, 1, fl_printf(get_child(e, 1)));
        fl_ty = fl_t_int;
        return e;
      }
    }
    set_child(e, 1, fl_args(get_child(e, 1), t));
    if (t != 0 && get_op(t) == '(') fl_ty = get_child(t, 0);
    else fl_ty = fl_t_int;
    return e;
  }

  if (op == '.' || op == ARROW) {
    a = fl_expr(get_child(e, 0));
    at = fl_ty;
    if (op == ARROW) at = fl_pointee(at);
    set_child(e, 0, a);
    fl_ty = fl_member(at, get_val(get_child(e, 1)));
    if (fl_ty == 0) fl_ty = fl_t_int;
    return e;
  }

  if (op == AMP_AMP || op == BAR_BAR) {
    set_child(e, 0, fl_cond(get_child(e, 0)));
    set_child(e, 1, fl_cond(get_child(e, 1)));
    fl_ty = fl_t_int;
    return e;
  }

  if (op == ',') {
    set_child(e, 0, fl_expr_unused(get_child(e, 0)));
    b = fl_expr_go(get_child(e, 1), value_unused);
    set_child(e, 1, b);
    return e;
  }

  a = fl_expr(get_child(e, 0));
  at = fl_ty;
  b = fl_expr(get_child(e, 1));
  bt = fl_ty;

  if (op == '=') {
    set_child(e, 0, a);
    set_child(e, 1, fl_conv(b, bt, at));
    fl_ty = at;
    return e;
  }

  if (op == PLUS_EQ || op == MINUS_EQ || op == STAR_EQ || op == SLASH_EQ) {
    if (fl_is_dbl(at) || fl_is_dbl(bt)) {
      if (op == PLUS_EQ) id = FL_DADD_ID;
      else if (op == MINUS_EQ) id = FL_DSUB_ID;
      else if (op == STAR_EQ) id = FL_DMUL_ID;
      else id = FL_DDIV_ID;
      fl_ty = at;
      return new_ast2('=', a, fl_conv(fl_binop(id, a, at, b, bt), fl_t_double, at));
    }
  }

  if (op == '[') {
    set_child(e, 0, a);
    set_child(e, 1, b);
    if (fl_is_ptr(at)) fl_ty = fl_pointee(at);
    else if (fl_is_ptr(bt)) fl_ty = fl_pointee(bt);
    else fl_ty = fl_t_int;
    if (fl_ty == 0) fl_ty = fl_t_int;
    return e;
  }

  if (fl_is_dbl(at) || fl_is_dbl(bt)) {
    if (op == '+') { fl_ty = fl_t_double; return fl_binop(FL_DADD_ID, a, at, b, bt); }
    if (op == '-') { fl_ty = fl_t_double; return fl_binop(FL_DSUB_ID, a, at, b, bt); }
    if (op == '*') { fl_ty = fl_t_double; return fl_binop(FL_DMUL_ID, a, at, b, bt); }
    if (op == '/') { fl_ty = fl_t_double; return fl_binop(FL_DDIV_ID, a, at, b, bt); }
    fl_ty = fl_t_int;
    if (op == '<')      return fl_binop(FL_DLT_ID, a, at, b, bt);
    if (op == '>')      return fl_binop(FL_DLT_ID, b, bt, a, at);
    if (op == LT_EQ)    return fl_binop(FL_DLE_ID, a, at, b, bt);
    if (op == GT_EQ)    return fl_binop(FL_DLE_ID, b, bt, a, at);
    if (op == EQ_EQ)    return fl_binop(FL_DEQ_ID, a, at, b, bt);
    if (op == EXCL_EQ)  return new_ast1('!', fl_binop(FL_DEQ_ID, a, at, b, bt));
    // %, shifts and bitwise operators do not take doubles; leave as is
  }

  set_child(e, 0, a);
  set_child(e, 1, b);
  if (op == '+' && fl_is_ptr(at)) fl_ty = at;
  else if (op == '+' && fl_is_ptr(bt)) fl_ty = bt;
  else if (op == '-' && fl_is_ptr(at) && !fl_is_ptr(bt)) fl_ty = at;
  else if (op == '=' || op == PLUS_EQ || op == MINUS_EQ) fl_ty = at;
  else fl_ty = fl_t_int;
  return e;
}

ast fl_expr(ast e) {
  return fl_expr_go(e, false);
}

ast fl_expr_unused(ast e) {
  return fl_expr_go(e, true);
}

// printf with a literal format: each %f, %e, %g (and %F, %E, %G) becomes
// %s, its argument a call to ba_dfmt(value, conversion, flags, width,
// precision) that formats it.
ast fl_printf(ast params) {
  char *f = symbol_buf(get_val(car(params)));
  ast args = tail(params);
  ast res = 0;
  ast last = 0;
  ast width;
  ast prec;
  ast a;
  ast cell;
  int flags;
  int n;
  int conv;
  bool changed = false;
  char *spec;

  // First pass: does the format have a floating-point conversion or a
  // length modifier (which the shell's printf rejects)?
  spec = f;
  while (*spec != 0) {
    if (*spec == '%') {
      spec += 1;
      while (*spec == '-' || *spec == '+' || *spec == ' ' || *spec == '#' || *spec == '0'
          || *spec == '*' || *spec == '.' || *spec == 'l' || *spec == 'L' || *spec == 'h'
          || *spec == 'z' || *spec == 'j' || *spec == 't' || ('0' <= *spec && *spec <= '9')) {
        if (*spec == 'l' || *spec == 'L' || *spec == 'h' || *spec == 'z' || *spec == 'j' || *spec == 't') changed = true;
        spec += 1;
      }
      if (*spec == 'f' || *spec == 'F' || *spec == 'e' || *spec == 'E' || *spec == 'g' || *spec == 'G') changed = true;
      if (*spec == 0) break;
    }
    spec += 1;
  }
  if (!changed) return fl_args(params, 0);

  begin_symbol();
  while (*f != 0) {
    if (*f != '%') {
      accum_symbol_char(*f);
      f += 1;
      continue;
    }
    spec = f;
    f += 1;
    if (*f == '%') {
      accum_symbol_char('%');
      accum_symbol_char('%');
      f += 1;
      continue;
    }
    flags = 0;
    width = 0;
    prec = 0;
    while (*f == '-' || *f == '+' || *f == ' ' || *f == '#' || *f == '0') {
      if (*f == '-') flags = flags | 1;
      if (*f == '+') flags = flags | 2;
      if (*f == ' ') flags = flags | 4;
      if (*f == '#') flags = flags | 8;
      if (*f == '0') flags = flags | 16;
      f += 1;
    }
    if (*f == '*') {
      if (args != 0) { width = car(args); args = tail(args); }
      f += 1;
    } else {
      n = -1;
      while ('0' <= *f && *f <= '9') {
        if (n < 0) n = 0;
        n = n * 10 + *f - '0';
        f += 1;
      }
      width = new_ast0(INTEGER, -n);
    }
    if (*f == '.') {
      f += 1;
      if (*f == '*') {
        if (args != 0) { prec = car(args); args = tail(args); }
        f += 1;
      } else {
        n = 0;
        while ('0' <= *f && *f <= '9') {
          n = n * 10 + *f - '0';
          f += 1;
        }
        prec = new_ast0(INTEGER, -n);
      }
    } else {
      prec = new_ast0(INTEGER, 1);   // -1: no precision
    }
    while (*f == 'l' || *f == 'L' || *f == 'h' || *f == 'z' || *f == 'j' || *f == 't') f += 1;
    conv = *f;
    if (conv != 0) f += 1;
    if (conv == 'f' || conv == 'F' || conv == 'e' || conv == 'E' || conv == 'g' || conv == 'G') {
      accum_symbol_char('%');
      accum_symbol_char('s');
      a = 0;
      if (args != 0) { a = fl_expr(car(args)); args = tail(args); a = fl_conv(a, fl_ty, fl_t_double); }
      if (a == 0) a = fl_lit(0, 0, 0, 0);
      width = fl_expr(width);
      prec = fl_expr(prec);
      a = new_ast2('(', new_ast0(IDENTIFIER, FL_DFMT_ID),
            cons(a, cons(new_ast0(INTEGER, -conv), cons(new_ast0(INTEGER, -flags),
            cons(width, cons(prec, 0))))));
      cell = cons(a, 0);
      if (res == 0) res = cell; else set_child(last, 1, cell);
      last = cell;
    } else {
      // Any other conversion is copied without its length modifier, with
      // the arguments it takes
      while (spec < f) {
        if (*spec != 'l' && *spec != 'L' && *spec != 'h' && *spec != 'z' && *spec != 'j' && *spec != 't') {
          accum_symbol_char(*spec);
        }
        if (*spec == '*' && args != 0) {
          cell = cons(fl_expr(car(args)), 0);
          if (res == 0) res = cell; else set_child(last, 1, cell);
          last = cell;
          args = tail(args);
        }
        spec += 1;
      }
      if (conv != 0 && args != 0) {
        a = fl_expr(car(args));
        if (fl_is_dbl(fl_ty)) a = fl_call1(FL_DTOI_ID, a);
        cell = cons(a, 0);
        if (res == 0) res = cell; else set_child(last, 1, cell);
        last = cell;
        args = tail(args);
      }
    }
  }
  a = new_ast0(STRING, end_symbol());
  while (args != 0) { // extra arguments
    cell = cons(fl_expr(car(args)), 0);
    if (res == 0) res = cell; else set_child(last, 1, cell);
    last = cell;
    args = tail(args);
  }
  return cons(a, res);
}

ast fl_stmt(ast s);
void fl_stmt_child(ast s, int i);

// pnut only allows && and || with function calls in tests: a value such as
// `return a < b && b < c;` on doubles is turned into an if statement.
bool fl_needs_test(ast e) {
  int op;
  if (e == 0) return false;
  op = get_op(e);
  if (op == '!' && get_nb_children(e) == 1) return fl_needs_test(get_child(e, 0));
  if (op != AMP_AMP && op != BAR_BAR) return false;
  return fl_has_call(e);
}

void fl_local_decls(ast decls) {
  ast decl;
  ast t;
  ast init;
  decls = get_child(decls, 0);
  while (decls != 0) {
    decl = car(decls);
    t = get_child(decl, 1);
    fl_note_type(t);
    if (get_child(decl, 0) != 0) fl_l_put(get_val(get_child(decl, 0)), t);
    init = get_child(decl, 2);
    if (init != 0 && get_op(init) != INITIALIZER_LIST) {
      init = fl_expr(init);
      set_child(decl, 2, fl_conv(init, fl_ty, t));
    }
    decls = tail(decls);
  }
}

ast fl_stmt(ast s) {
  int op;
  int saved;
  ast rest;
  ast r;
  if (s == 0) return s;
  op = get_op(s);
  if (op == '{') {
    saved = fl_nl;
    rest = s;
    while (rest != 0) {
      fl_stmt_child(rest, 0);
      rest = get_child(rest, 1);
    }
    fl_nl = saved;
  } else if (op == DECLS) {
    fl_local_decls(s);
  } else if (op == IF_KW) {
    set_child(s, 0, fl_cond(get_child(s, 0)));
    fl_stmt_child(s, 1);
    fl_stmt_child(s, 2);
  } else if (op == WHILE_KW) {
    set_child(s, 0, fl_cond(get_child(s, 0)));
    fl_stmt_child(s, 1);
  } else if (op == DO_KW) {
    fl_stmt_child(s, 0);
    set_child(s, 1, fl_cond(get_child(s, 1)));
  } else if (op == FOR_KW) {
    saved = fl_nl;
    if (get_child(s, 0) != 0 && get_op(get_child(s, 0)) == DECLS) fl_local_decls(get_child(s, 0));
    else set_child(s, 0, fl_expr_unused(get_child(s, 0)));
    set_child(s, 1, fl_cond(get_child(s, 1)));
    set_child(s, 2, fl_expr_unused(get_child(s, 2)));
    fl_stmt_child(s, 3);
    fl_nl = saved;
  } else if (op == SWITCH_KW) {
    set_child(s, 0, fl_expr(get_child(s, 0)));
    fl_stmt_child(s, 1);
  } else if (op == CASE_KW) {
    fl_stmt_child(s, 1);
  } else if (op == DEFAULT_KW) {
    fl_stmt_child(s, 0);
  } else if (op == ':') {
    fl_stmt_child(s, 1);
  } else if (op == RETURN_KW) {
    if (get_child(s, 0) != 0) {
      r = fl_expr(get_child(s, 0));
      if (fl_needs_test(r)) {
        return new_ast3(IF_KW, r,
          new_ast1(RETURN_KW, fl_conv(new_ast0(INTEGER, -1), fl_t_int, fl_ret_ty)),
          new_ast1(RETURN_KW, fl_conv(new_ast0(INTEGER, 0), fl_t_int, fl_ret_ty)));
      }
      set_child(s, 0, fl_conv(r, fl_ty, fl_ret_ty));
    }
  } else if (op == TYPEDEF_KW || op == STRUCT_KW || op == UNION_KW || op == ENUM_KW) {
    if (op == TYPEDEF_KW) fl_note_type(get_child(car(get_child(s, 0)), 1));
    else fl_note_type(s);
  }
  return s;
}

// A statement in child i of s; a bare expression statement is lowered too.
void fl_stmt_child(ast s, int i) {
  ast c = get_child(s, i);
  int op;
  if (c == 0) return;
  op = get_op(c);
  if (op == '{' || op == DECLS || op == IF_KW || op == WHILE_KW || op == DO_KW || op == FOR_KW
   || op == SWITCH_KW || op == CASE_KW || op == DEFAULT_KW || op == RETURN_KW || op == ':'
   || op == GOTO_KW || op == BREAK_KW || op == CONTINUE_KW || op == TYPEDEF_KW
   || op == STRUCT_KW || op == UNION_KW || op == ENUM_KW) {
    set_child(s, i, fl_stmt(c));
  } else {
    c = fl_expr_unused(c);
    if (get_op(c) == '=' && fl_needs_test(get_child(c, 1))) {
      c = new_ast3(IF_KW, get_child(c, 1),
            new_ast2('=', get_child(c, 0), new_ast0(INTEGER, -1)),
            new_ast2('=', get_child(c, 0), new_ast0(INTEGER, 0)));
    }
    set_child(s, i, c);
  }
}

// Initializers of a global: constants only, so conversions are folded.
ast fl_glo_init(ast init, ast t) {
  ast lst;
  ast elem;
  ast lit;
  if (init == 0) return 0;
  if (get_op(init) == INITIALIZER_LIST) {
    if (get_op(t) == '[') t = get_child(t, 0);
    lst = get_child(init, 0);
    while (lst != 0) {
      set_child(lst, 0, fl_glo_init(car(lst), t));
      lst = tail(lst);
    }
    return init;
  }
  if (fl_is_dbl(t)) {
    if (get_op(init) == '-' && get_nb_children(init) == 1 && get_op(get_child(init, 0)) == DOUBLE_LIT) {
      return fl_neg(get_child(init, 0));
    }
    lit = fl_int_lit_to_dbl(init);
    if (lit != 0) return lit;
  }
  init = fl_expr(init);
  return fl_conv(init, fl_ty, t);
}

void fl_lower_glo_decl(ast node) {
  int op = get_op(node);
  ast decls;
  ast decl;
  ast t;
  ast params;
  ast body;

  if (!fl_initialized) fl_init();
  fl_nl = 0;

  if (op == DECLS) {
    decls = get_child(node, 0);
    while (decls != 0) {
      decl = car(decls);
      t = get_child(decl, 1);
      fl_note_type(t);
      if (get_op(t) == '(') {
        params = get_child(t, 1);
        while (params != 0) {
          fl_note_type(get_child(car(params), 1));
          params = tail(params);
        }
      }
      fl_g_put(get_val(get_child(decl, 0)), t);
      if (get_op(t) != '(') set_child(decl, 2, fl_glo_init(get_child(decl, 2), t));
      decls = tail(decls);
    }
  } else if (op == FUN_DECL) {
    decl = get_child(node, 0);
    t = get_child(decl, 1);
    fl_note_type(t);
    fl_g_put(get_val(get_child(decl, 0)), t);
    body = get_child(node, 1);
    if (body == 0 || body == -1) return;
    params = get_child(t, 1);
    while (params != 0) {
      fl_note_type(get_child(car(params), 1));
      if (get_child(car(params), 0) != 0) {
        fl_l_put(get_val(get_child(car(params), 0)), get_child(car(params), 1));
      }
      params = tail(params);
    }
    fl_ret_ty = get_child(t, 0);
    fl_stmt(body);
    fl_nl = 0;
  } else if (op == TYPEDEF_KW) {
    fl_note_type(get_child(car(get_child(node, 0)), 1));
  } else if (op == STRUCT_KW || op == UNION_KW) {
    fl_note_type(node);
  }
}

// Shell text of a double literal: its bit pattern as a decimal integer.
text fl_lit_text(ast node) {
  int obj = get_val(node);
  int p0 = heap[obj];
  int p1 = heap[obj + 1];
  int p2 = heap[obj + 2];
  int p3 = heap[obj + 3];
  int neg = 0;
  int r;
  int cur;
  text t = 0;
  if (p3 >= 32768) { // negative as a signed 64-bit integer: two's complement
    neg = 1;
    p0 = 65535 - p0; p1 = 65535 - p1; p2 = 65535 - p2; p3 = 65535 - p3;
    p0 += 1;
    if (p0 == 65536) { p0 = 0; p1 += 1; }
    if (p1 == 65536) { p1 = 0; p2 += 1; }
    if (p2 == 65536) { p2 = 0; p3 += 1; }
  }
  if ((p0 | p1 | p2 | p3) == 0) return wrap_char('0');
  while ((p0 | p1 | p2 | p3) != 0) { // divide by 10, collecting digits
    cur = p3;            p3 = cur / 10; r = cur % 10;
    cur = r * 65536 + p2; p2 = cur / 10; r = cur % 10;
    cur = r * 65536 + p1; p1 = cur / 10; r = cur % 10;
    cur = r * 65536 + p0; p0 = cur / 10; r = cur % 10;
    cur = '0' + r;             // wrap_char is a macro: give it a variable
    t = string_concat(wrap_char(cur), t);
  }
  if (neg) t = string_concat(wrap_char('-'), t);
  return t;
}
