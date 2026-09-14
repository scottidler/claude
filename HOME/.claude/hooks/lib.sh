#!/bin/bash
# lib.sh: shared, quote-aware command parsing for the PreToolUse Bash guards.
#
# Sourced, never run:
#   . "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }
# It defines functions and one variable and does nothing else, so a guard can
# source it before it has read its payload.
#
# The contract, and the reason every function below is one awk program: a guard
# MATCHES on a masked copy and EXTRACTS values from the original, and no offset
# ever crosses into bash. `grep -b -o` reports BYTE offsets while ${v:off:len}
# counts CHARACTERS, and the two diverge on the first multibyte character in a
# command. awk's index/substr share one index space, so the mask, the match and
# the slice all happen in here. LC_ALL=C is pinned so the answer does not depend
# on the machine's awk or locale (system awk is mawk 1.3.4).
#
# Every masker replaces the spans it neutralizes with a run of \x01 of the SAME
# BYTE LENGTH, so an offset taken on a mask is valid in the original. A newline
# is never masked: line structure is load-bearing for line-oriented callers and
# a newline carries nothing matchable.
#
# The rule the maskers obey, and the one that took three rounds to find: a
# masker may only erase a span the shell will never execute. Heredoc bodies,
# single-quoted data, and comments are inert. Subshell bodies, backtick bodies
# and the argument of `bash -c` are NOT: they are nested statements, so `stmts`
# yields them as statements of their own instead of any masker erasing them.
#
# Run directly, or via: lib.sh --self-test

IFS= read -r -d '' _LIB_AWK <<'LIBAWK'
BEGIN {
  RS = "\034"
  ORS = ""
  MK = sprintf("%c", 1)
  HDRE = "^<<-?[ \t]*(\"[^\"]*\"|'[^']*'|[A-Za-z_][A-Za-z0-9_-]*)"
  SEPCH = ";&|()<>"
}

{ if (NR > 1) buf = buf RS; buf = buf $0 }

# cls[i] is the class of byte i of the scanned text:
#   .  plain, unquoted code          q  a quote character itself
#   S  single-quoted content         c  single-quoted content that is a -c argument
#   D  double-quoted content         E  a backslash-escaped $ (both bytes)
#   H  heredoc body or terminator    #  comment
#   P  command substitution body ($( ) or backticks), which no masker may erase
function scan(s,   n, i, ch, nx, rest, tok, w, j) {
  n = length(s)
  delete cls
  delete nsb
  delete nse
  nsn = 0
  npend = 0
  q = 0
  sqcls = "S"
  i = 1
  while (i <= n) {
    ch = substr(s, i, 1)
    if (q == 1) {
      if (ch == "'") { cls[i] = "q"; q = 0 } else cls[i] = sqcls
      i++
      continue
    }
    if (q == 2) {
      if (ch == "\\") {
        nx = substr(s, i + 1, 1)
        if (nx == "$") { cls[i] = "E"; cls[i + 1] = "E" }
        else { cls[i] = "D"; if (i < n) cls[i + 1] = "D" }
        i += 2
        continue
      }
      if (ch == "\"") { cls[i] = "q"; q = 0; i++; continue }
      if (ch == "`") { i = subspan(s, i, n, "`"); continue }
      if (ch == "$" && substr(s, i + 1, 1) == "(") { i = subspan(s, i, n, ")"); continue }
      cls[i] = "D"
      i++
      continue
    }
    if (ch == "\\") {
      if (substr(s, i + 1, 1) == "$") { cls[i] = "E"; cls[i + 1] = "E" }
      else { cls[i] = "."; if (i < n) cls[i + 1] = "." }
      i += 2
      continue
    }
    if (ch == "'") { cls[i] = "q"; sqcls = dashc_before(s, i) ? "c" : "S"; q = 1; i++; continue }
    if (ch == "\"") { cls[i] = "q"; q = 2; i++; continue }
    if (ch == "`") { i = subspan(s, i, n, "`"); continue }
    if (ch == "$" && substr(s, i + 1, 1) == "(") { i = subspan(s, i, n, ")"); continue }
    if (ch == "#" && wordstart(s, i)) {
      while (i <= n && substr(s, i, 1) != "\n") { cls[i] = "#"; i++ }
      continue
    }
    if (ch == "<" && substr(s, i, 3) == "<<<") { cls[i] = "."; cls[i+1] = "."; cls[i+2] = "."; i += 3; continue }
    if (ch == "<" && substr(s, i, 2) == "<<") {
      rest = substr(s, i)
      if (match(rest, HDRE)) {
        tok = substr(rest, 1, RLENGTH)
        npend++
        pdash[npend] = (substr(tok, 3, 1) == "-") ? 1 : 0
        w = tok
        sub(/^<<-?[ \t]*/, "", w)
        gsub(/"/, "", w)
        gsub(/'/, "", w)
        pdelim[npend] = w
        for (j = i; j < i + RLENGTH; j++) cls[j] = "."
        i += RLENGTH
        continue
      }
      cls[i] = "."
      cls[i + 1] = "."
      i += 2
      continue
    }
    cls[i] = "."
    i++
    if (ch == "\n" && npend > 0) i = eatbodies(s, i, n)
  }
}

# A heredoc body and its terminator line are never statements (otto b428680,
# 2026-09-01: a wrapped commit-message line starting with "bump" was read as a
# command). The newline that ENDS the last terminator is plain, so the command
# on the next line stays a statement of its own.
function eatbodies(s, i, n,   j, line, t, k) {
  while (npend > 0 && i <= n) {
    j = i
    while (j <= n && substr(s, j, 1) != "\n") j++
    line = substr(s, i, j - i)
    for (k = i; k < j; k++) cls[k] = "H"
    t = line
    if (pdash[1]) sub(/^[ \t]+/, "", t)
    sub(/[ \t]+$/, "", t)
    if (t == pdelim[1]) {
      for (k = 1; k < npend; k++) { pdelim[k] = pdelim[k + 1]; pdash[k] = pdash[k + 1] }
      npend--
    }
    if (j > n) return j
    cls[j] = (npend == 0) ? "." : "H"
    i = j + 1
  }
  return i
}

function subspan(s, start, n, kind,   i, depth, ch, qq, bs) {
  if (kind == ")") {
    cls[start] = "."
    cls[start + 1] = "."
    i = start + 2
    bs = i
    depth = 1
    qq = 0
    while (i <= n) {
      ch = substr(s, i, 1)
      if (ch == "\\") { cls[i] = "P"; if (i < n) cls[i + 1] = "P"; i += 2; continue }
      if (qq == 1) { if (ch == "'") qq = 0; cls[i] = "P"; i++; continue }
      if (qq == 2) { if (ch == "\"") qq = 0; cls[i] = "P"; i++; continue }
      if (ch == "'") { qq = 1; cls[i] = "P"; i++; continue }
      if (ch == "\"") { qq = 2; cls[i] = "P"; i++; continue }
      if (ch == "(") depth++
      if (ch == ")") {
        depth--
        if (depth == 0) { cls[i] = "."; record_sub(bs, i - 1); return i + 1 }
      }
      cls[i] = "P"
      i++
    }
    record_sub(bs, n)
    return n + 1
  }
  cls[start] = "."
  i = start + 1
  bs = i
  while (i <= n) {
    ch = substr(s, i, 1)
    if (ch == "\\") { cls[i] = "P"; if (i < n) cls[i + 1] = "P"; i += 2; continue }
    if (ch == "`") { cls[i] = "."; record_sub(bs, i - 1); return i + 1 }
    cls[i] = "P"
    i++
  }
  record_sub(bs, n)
  return n + 1
}

function record_sub(a, b) {
  if (b < a) return
  nsn++
  nsb[nsn] = a
  nse[nsn] = b
}

function wordstart(s, i,   p) {
  if (i == 1) return 1
  p = substr(s, i - 1, 1)
  return (p == " " || p == "\t" || p == "\n" || p == ";" || p == "&" || p == "|" || p == "(")
}

function dashc_before(s, i,   j, e) {
  j = i - 1
  while (j >= 1 && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j--
  e = j
  while (j >= 1 && substr(s, j, 1) != " " && substr(s, j, 1) != "\t") j--
  return (substr(s, j + 1, e - j) == "-c")
}

function masked(s, set,   n, i, out, c) {
  n = length(s)
  out = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    out = out ((c != "\n" && index(set, cls[i]) > 0) ? MK : c)
  }
  return out
}

# tb[k]/te[k] are the byte bounds of token k; tsep[k] says a metacharacter (not
# just whitespace) came before it, so `-m ;` has no value token.
function tokenize(s,   n, i, c, brk) {
  delete tb
  delete te
  delete tsep
  tn = 0
  n = length(s)
  i = 1
  brk = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (cls[i] == "." && (c == " " || c == "\t")) { i++; continue }
    if (cls[i] == "." && (c == "\n" || index(SEPCH, c) > 0)) { brk = 1; i++; continue }
    tn++
    tb[tn] = i
    tsep[tn] = brk
    brk = 0
    while (i <= n) {
      c = substr(s, i, 1)
      if (cls[i] == "." && (c == " " || c == "\t" || c == "\n" || index(SEPCH, c) > 0)) break
      i++
    }
    te[tn] = i - 1
  }
}

function toktext(s, k) { return substr(s, tb[k], te[k] - tb[k] + 1) }

# The statement's arguments, one per line, quote characters dropped, so a gate
# can ask about an argument's ROLE instead of matching a substring: which
# operand is the tag NAME, whether every operand is a literal path, which token
# follows `checkout -b`. Splitting on UNQUOTED whitespace is what keeps a quoted
# path holding a space (or a whole `-m` message) as ONE argument.
#
# The CALLER chooses the input, which is the match-on-the-mask/extract-from-the-
# original contract with the decision left where it belongs: feed the ORIGINAL
# when a `$` or a backtick has to survive to be refused, feed a MASKED copy when
# a word inside a message-flag value must not be read as a name.
function args_out(s,   k) {
  for (k = 1; k <= tn; k++) printf "%s\n", tokword(s, k)
}

# The shell WORD a token expands to as far as quoting goes: the quote characters
# themselves drop out, so `--title="a b"` yields --title=a b and a value read
# back from `'x'"y"` is xy.
function tokword(s, k,   i, out) {
  out = ""
  for (i = tb[k]; i <= te[k]; i++) if (cls[i] != "q") out = out substr(s, i, 1)
  return out
}

function is_optflag(w) {
  return (w == "-m" || w == "--message" || w == "-F" || w == "--file" \
       || w == "--reuse-message" || w == "--reedit-message")
}

function optarg_eq(w,   f, i) {
  split("--message --file --reuse-message --reedit-message", f, " ")
  for (i = 1; i <= 4; i++) if (substr(w, 1, length(f[i]) + 1) == f[i] "=") return length(f[i]) + 1
  return 0
}

# `git tag -a v1 -m "added --force"` is a tag annotation that MENTIONS a flag,
# not a command that uses one. -C is deliberately absent from the flag set:
# git overloads it as `git -C <dir>`, `git commit -C <commit>` and
# `git switch -C <branch>`, and masking its value would hide a branch name.
function mask_optarg_text(s,   k, w, i, j, out, n, c) {
  delete om
  for (k = 1; k <= tn; k++) {
    if (cls[tb[k]] == "H" || cls[tb[k]] == "#" || cls[tb[k]] == "P") continue
    w = tokword(s, k)
    if (is_optflag(w)) {
      if (k < tn && !tsep[k + 1]) for (i = tb[k + 1]; i <= te[k + 1]; i++) om[i] = 1
      continue
    }
    if (optarg_eq(w) == 0) continue
    for (j = tb[k]; j <= te[k]; j++) if (substr(s, j, 1) == "=" && cls[j] != "q") break
    for (i = j + 1; i <= te[k]; i++) om[i] = 1
  }
  n = length(s)
  out = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    out = out ((c != "\n" && cls[i] != "q" && (i in om)) ? MK : c)
  }
  return out
}

function flag_value(s, lng, shrt,   k, w, e) {
  for (k = 1; k <= tn; k++) {
    if (cls[tb[k]] == "H" || cls[tb[k]] == "#" || cls[tb[k]] == "P") continue
    w = tokword(s, k)
    if ((lng != "" && w == lng) || (shrt != "" && w == shrt)) {
      if (k < tn && !tsep[k + 1]) return tokword(s, k + 1)
      return ""
    }
    if (lng != "") { e = length(lng) + 1; if (substr(w, 1, e) == lng "=") return substr(w, e + 1) }
    if (shrt != "") { e = length(shrt) + 1; if (substr(w, 1, e) == shrt "=") return substr(w, e + 1) }
  }
  return ""
}

function cd_last(s,   k, r) {
  r = ""
  for (k = 1; k < tn; k++) {
    if (cls[tb[k]] != ".") continue
    if (k > 1 && !tsep[k]) continue
    if (tokword(s, k) != "cd") continue
    if (tsep[k + 1]) continue
    r = tokword(s, k + 1)
  }
  return r
}

function first_word(s, k,   j, w) {
  j = k
  while (j > 1 && !tsep[j]) j--
  while (j <= tn) {
    w = tokword(s, j)
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w == "command" || w == "builtin" || w == "exec" || w == "sudo" || w == "env") { j++; continue }
    sub(/^.*\//, "", w)
    return w
  }
  return ""
}

# The argument of `bash -c` is a nested statement, not data: the child shell
# runs it. Neutralize the span in the enclosing statement and queue the body.
function find_dashc(s,   k, w, i) {
  delete dcm
  for (k = 1; k < tn; k++) {
    if (cls[tb[k]] == "H" || cls[tb[k]] == "#" || cls[tb[k]] == "P") continue
    if (tokword(s, k) != "-c") continue
    if (tsep[k + 1]) continue
    w = first_word(s, k)
    if (w != "bash" && w != "sh" && w != "zsh") continue
    for (i = tb[k + 1]; i <= te[k + 1]; i++) if (cls[i] != "q") dcm[i] = 1
    wn++
    wq[wn] = tokword(s, k + 1)
  }
}

function emit_piece(s, a, b,   i, c, out, bare) {
  if (b < a) return
  out = ""
  bare = ""
  for (i = a; i <= b; i++) {
    c = substr(s, i, 1)
    if (c != "\n" && (cls[i] == "P" || cls[i] == "H" || (i in dcm))) c = MK
    out = out c
    if (c != MK) bare = bare c
  }
  sub(/^[ \t\n]+/, "", out)
  sub(/[ \t\n]+$/, "", out)
  gsub(/[ \t\n]/, "", bare)
  if (out == "" || bare == "") return
  sn++
  st[sn] = out
}

function split_one(s,   n, i, c, a, k) {
  scan(s)
  tokenize(s)
  find_dashc(s)
  for (k = 1; k <= nsn; k++) { wn++; wq[wn] = substr(s, nsb[k], nse[k] - nsb[k] + 1) }
  n = length(s)
  a = 1
  i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (cls[i] == ".") {
      if (c == "\n" || c == ";") { emit_piece(s, a, i - 1); a = i + 1; i++; continue }
      if (c == "&" || c == "|") {
        if (substr(s, i + 1, 1) == c) { emit_piece(s, a, i - 1); a = i + 2; i += 2; continue }
        emit_piece(s, a, i - 1)
        a = i + 1
        i++
        continue
      }
    }
    i++
  }
  emit_piece(s, a, n)
}

# Statements in emission order: every top-level statement first, then the nested
# ones they yielded, breadth first. Nested bodies shrink strictly, so this ends.
function build_stmts(s,   qi) {
  delete st
  delete wq
  sn = 0
  wn = 1
  wq[1] = s
  qi = 1
  while (qi <= wn) {
    split_one(wq[qi])
    qi++
  }
}

function cmdword_ok(s, word,   t, re) {
  t = s
  sub(/^[ \t\n]+/, "", t)
  sub(/[ \t\n]+$/, "", t)
  re = "^([A-Za-z_][A-Za-z0-9_]*=[^ \t]+[ \t]+)*((command|builtin|exec|sudo|env)[ \t]+)*(/?[^ \t]*/)?" word "([ \t]|$)"
  return (t ~ re)
}

END {
  if (mode == "heredoc") { scan(buf); printf "%s", masked(buf, "H"); exit 0 }
  if (mode == "squote")  { scan(buf); printf "%s", masked(buf, "SE"); exit 0 }
  if (mode == "dquote")  { scan(buf); printf "%s", masked(buf, "D"); exit 0 }
  if (mode == "comment") { scan(buf); printf "%s", masked(buf, "#"); exit 0 }
  if (mode == "optarg")  { scan(buf); tokenize(buf); printf "%s", mask_optarg_text(buf); exit 0 }
  if (mode == "cmdword") { exit (cmdword_ok(buf, a1) ? 0 : 1) }
  if (mode == "args") {
    scan(buf)
    tokenize(buf)
    args_out(buf)
    exit 0
  }
  if (mode == "flagvalue") {
    scan(buf)
    tokenize(buf)
    v = flag_value(buf, a1, a2)
    if (v != "") printf "%s\n", v
    exit 0
  }
  if (mode == "cdtarget") {
    scan(buf)
    tokenize(buf)
    v = cd_last(buf)
    if (v != "") printf "%s\n", v
    exit 0
  }
  if (mode == "cdat") {
    build_stmts(buf)
    v = ""
    for (k = 1; k < a1 + 0 && k <= sn; k++) {
      scan(st[k])
      tokenize(st[k])
      t = cd_last(st[k])
      if (t != "") v = t
    }
    if (v != "") printf "%s\n", v
    exit 0
  }
  if (mode == "stmts") {
    build_stmts(buf)
    for (k = 1; k <= sn; k++) printf "%s%c", st[k], 0
    exit 0
  }
  exit 2
}
LIBAWK

_lib_run() { LC_ALL=C awk -v mode="$1" -v a1="${2-}" -v a2="${3-}" -- "$_LIB_AWK"; }

mask_heredoc() { _lib_run heredoc; }
mask_squote()  { _lib_run squote; }
mask_dquote()  { _lib_run dquote; }
mask_comment() { _lib_run comment; }
mask_optarg()  { _lib_run optarg; }

stmts()        { _lib_run stmts; }
args()         { _lib_run args; }
flag_value()   { _lib_run flagvalue "${1-}" "${2-}"; }
cd_target()    { _lib_run cdtarget; }
cd_at()        { _lib_run cdat "${1-}"; }
cmdword_is()   { _lib_run cmdword "${1-}"; }

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-test.sh"
fi
