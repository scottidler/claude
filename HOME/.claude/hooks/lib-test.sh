#!/bin/bash
# lib-test.sh: fixture matrix for lib.sh.
#
# Every function gets a positive and a negative case, and every masker also gets
# a byte-length assertion: a mask whose output is a different length than its
# input silently invalidates every offset a caller takes on it.
#
# Masked bytes are rendered as '@' so the expectations read as text, so no
# fixture may contain a literal '@'. Expected masks are built with mk(), which
# emits one '@' per byte of the span that is supposed to disappear, rather than
# a hand-counted run.
#
# Run directly, or via: lib.sh --self-test
set -u
export LC_ALL=C
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pass=0
fail=0

eq() { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      want [%s]\n      got  [%s]\n' "$1" "$2" "$3"
  fi
}

vis() { sed -e 's/\x01/@/g'; }
mk() { printf '%s' "$1" | sed -e 's/./@/g'; }

case_mask() { # case_mask <masker> <label> <input> <expected>
  local f="$1" label="$2" in="$3" want="$4" nin nout
  eq "$label" "$want" "$(printf '%s' "$in" | "$f" | vis)"
  nin=$(printf '%s' "$in" | wc -c)
  nout=$(printf '%s' "$in" | "$f" | wc -c)
  eq "$label [byte length preserved]" "$nin" "$nout"
}

case_h() { case_mask mask_heredoc "$@"; }
case_s() { case_mask mask_squote "$@"; }
case_d() { case_mask mask_dquote "$@"; }
case_c() { case_mask mask_comment "$@"; }
case_o() { case_mask mask_optarg "$@"; }

case_stmts() { # case_stmts <label> <input> <expected, statements joined by |>
  eq "$1" "$3" "$(printf '%s' "$2" | stmts | tr '\0' '|' | sed -e 's/|$//' | vis)"
}

case_flag() { # case_flag <label> <input> <long> <short> <expected>
  eq "$1" "$5" "$(printf '%s' "$2" | flag_value "$3" "$4")"
}

case_cmdword() { # case_cmdword <label> <input> <word> <expected rc>
  local rc=0
  printf '%s' "$2" | cmdword_is "$3" || rc=1
  eq "$1" "$4" "$rc"
}

case_cd() { # case_cd <label> <input> <expected>
  eq "$1" "$3" "$(printf '%s' "$2" | cd_target)"
}

case_cdat() { # case_cdat <label> <input> <n> <expected>
  eq "$1" "$4" "$(printf '%s' "$2" | cd_at "$3")"
}

case_args() { # case_args <label> <input> <expected, arguments joined by |>
  eq "$1" "$3" "$(printf '%s' "$2" | args | tr '\n' '|' | sed -e 's/|$//' | vis)"
}

SQ=\'
TAGS="--ta""gs"
SECRET="SOME_""TOKEN"

echo "=== mask_heredoc ==="
case_h 'a quoted opener is not a heredoc, and the next line survives (problem 2a)' \
  "$(printf 'echo "<<EOF"\ngit push %s' "$TAGS")" \
  "$(printf 'echo "<<EOF"\ngit push %s' "$TAGS")"
case_h 'body and terminator masked, opener line kept, next command kept' \
  "$(printf 'cat > x.md <<EOF\nbump the manifest\nEOF\ngit status')" \
  "$(printf 'cat > x.md <<EOF\n%s\n%s\ngit status' "$(mk 'bump the manifest')" "$(mk 'EOF')")"
case_h 'an indented terminator closes a <<- heredoc' \
  "$(printf 'cat <<-EOF\n\tbody\n\tEOF\ngit status')" \
  "$(printf 'cat <<-EOF\n%s\n%s\ngit status' "$(mk "$(printf '\tbody')")" "$(mk "$(printf '\tEOF')")")"
case_h 'two openers on one line are consumed in order' \
  "$(printf 'cat <<A <<B\none\nA\ntwo\nB\ngit status')" \
  "$(printf 'cat <<A <<B\n%s\n%s\n%s\n%s\ngit status' "$(mk one)" "$(mk A)" "$(mk two)" "$(mk B)")"
case_h 'a quoted delimiter still opens a heredoc' \
  "$(printf 'cat <<%sEOF%s\nbody\nEOF\nls' "$SQ" "$SQ")" \
  "$(printf 'cat <<%sEOF%s\n%s\n%s\nls' "$SQ" "$SQ" "$(mk body)" "$(mk EOF)")"
case_h 'a herestring is not a heredoc' \
  "$(printf 'grep -q foo <<< "$body"\ngit status')" \
  "$(printf 'grep -q foo <<< "$body"\ngit status')"
case_h 'a command with no heredoc is untouched' 'git status' 'git status'
case_h 'byte length survives a composite input' \
  "$(printf 'cat <<EOF # c\n%sbody%s\nEOF\necho "x" %s' "$SQ" "$SQ" "$TAGS")" \
  "$(printf 'cat <<EOF # c\n%s\n%s\necho "x" %s' "$(mk "${SQ}body${SQ}")" "$(mk EOF)" "$TAGS")"

echo "=== mask_squote ==="
case_s 'a single-quoted span is masked and the bare word beside it survives' \
  "echo ${SQ}the manifest${SQ} && manifest -l y" \
  "echo ${SQ}$(mk 'the manifest')${SQ} && manifest -l y"
case_s 'a -c argument is a nested statement, never masked data' \
  "bash -c ${SQ}echo hi${SQ}" \
  "bash -c ${SQ}echo hi${SQ}"
case_s 'a backslash-escaped dollar is masked, both bytes' \
  "echo \\\$$SECRET" \
  "echo $(mk '\$')$SECRET"
case_s 'double-quoted content is not squote business' \
  'echo "the manifest"' \
  'echo "the manifest"'
case_s 'a command with no single quotes is untouched' 'git status' 'git status'

echo "=== mask_dquote ==="
case_d 'a double-quoted word is neutralized for the bare-word gates' \
  'echo "manifest"' \
  "echo \"$(mk manifest)\""
case_d 'the same word bare stays visible' 'manifest -l x' 'manifest -l x'
case_d 'single-quoted content is not dquote business' \
  "echo ${SQ}manifest${SQ}" \
  "echo ${SQ}manifest${SQ}"
case_d 'a command substitution inside double quotes is executed, so it survives' \
  'echo "$(manifest -l x)"' \
  'echo "$(manifest -l x)"'
case_d 'a quoted flag IS a flag, which is why option gates skip this masker' \
  "git push origin \"$TAGS\"" \
  "git push origin \"$(mk "$TAGS")\""

echo "=== mask_comment ==="
case_c 'a trailing comment is masked' \
  "git status # push the $TAGS" \
  "git status $(mk "# push the $TAGS")"
case_c 'a hash inside double quotes is not a comment' 'echo "a # b"' 'echo "a # b"'
case_c 'a hash that does not start a word is not a comment' 'ls a#b' 'ls a#b'
case_c 'a comment ends at the newline and the next line survives' \
  "$(printf '# leading comment\ngit status')" \
  "$(printf '%s\ngit status' "$(mk '# leading comment')")"
case_c 'a hash inside single quotes is not a comment' \
  "echo ${SQ}# not a comment${SQ}" \
  "echo ${SQ}# not a comment${SQ}"

echo "=== mask_optarg ==="
case_o 'a flag named inside a -m value is prose' \
  'git tag -a v1 -m "added --force"' \
  "git tag -a v1 -m \"$(mk 'added --force')\""
case_o 'the -C target is never masked, git overloads that flag' \
  'git -C /tmp status' \
  'git -C /tmp status'
case_o 'the --message=value form is masked after the equals' \
  'git commit --message=--force' \
  "git commit --message=$(mk '--force')"
case_o 'a -F value is masked' 'git commit -F body.txt' "git commit -F $(mk body.txt)"
case_o 'a flag in flag position is left alone' \
  'git push origin --force' \
  'git push origin --force'
case_o 'git switch -C keeps its branch name visible' \
  'git switch -C feature-x' \
  'git switch -C feature-x'

echo "=== stmts ==="
case_stmts 'a quoted semicolon does not split, a bare one does' \
  'git commit -m "a;b" ; ls' \
  'git commit -m "a;b"|ls'
case_stmts 'splits on && || | & and newlines' \
  "$(printf 'a && b || c | d & e\nf')" \
  'a|b|c|d|e|f'
case_stmts 'a subshell is yielded as its own statement and neutralized in the outer' \
  "git push origin \"\$(git describe $TAGS)\"" \
  "git push origin \"\$($(mk "git describe $TAGS"))\"|git describe $TAGS"
case_stmts 'a bash -c argument is yielded as its own statement' \
  "bash -c ${SQ}echo hi${SQ}" \
  "bash -c ${SQ}$(mk 'echo hi')${SQ}|echo hi"
case_stmts 'a variable inside a -c argument reaches the nested statement intact' \
  "bash -c ${SQ}echo \$X${SQ}" \
  "bash -c ${SQ}$(mk 'echo $X')${SQ}|echo \$X"
case_stmts 'an sh -c argument is yielded too' \
  "sh -c ${SQ}ls /tmp${SQ}" \
  "sh -c ${SQ}$(mk 'ls /tmp')${SQ}|ls /tmp"
case_stmts 'a backtick body is yielded as its own statement' \
  'echo `git describe`' \
  "echo \`$(mk 'git describe')\`|git describe"
case_stmts 'a heredoc body is never a statement' \
  "$(printf 'cat <<EOF\nbump 1.0\nEOF\ngit status')" \
  'cat <<EOF|git status'
case_stmts 'a single-quoted && does not split' \
  "echo ${SQ}a && b${SQ}" \
  "echo ${SQ}a && b${SQ}"

echo "=== flag_value ==="
case_flag 'recovers a quoted value verbatim' \
  'gh pr create --title "fix(x): a b" --body z' --title -t 'fix(x): a b'
case_flag 'recovers the equals form' \
  'gh pr create --title=hello-world' --title -t 'hello-world'
case_flag 'returns the RAW text, unexpanded variable and all' \
  'gh pr create --body-file "$TMPDIR/b.md"' --body-file -F '$TMPDIR/b.md'
case_flag 'recovers a short-form value' \
  'gh pr create -t short-title' --title -t 'short-title'
case_flag 'earlier multibyte text does not shift the value' \
  'echo "caffè latte ☕" && gh pr create --title "the right title"' --title -t 'the right title'
case_flag 'an absent flag returns empty' \
  'gh pr create --body z' --title -t ''
case_flag 'a flag inside a heredoc body is not the flag' \
  "$(printf 'cat <<EOF\n--title fake\nEOF\ngh pr create --title real')" --title -t 'real'

echo "=== cmdword_is ==="
case_cmdword 'git in command position matches' 'git push origin main' git 0
case_cmdword 'git inside a grep argument does not match' \
  "grep -n \"git push $TAGS\" notes.md" git 1
case_cmdword 'a hook name starting with git does not match' \
  '~/.claude/hooks/git-release-guard.sh --help' git 1
case_cmdword 'env assignments, a wrapper and a path prefix are allowed' \
  'FOO=1 sudo /usr/bin/git status' git 0
case_cmdword 'manifest in command position matches' 'manifest -l x' manifest 0
case_cmdword 'manifest as an argument does not match' 'echo manifest' manifest 1

echo "=== cd_target ==="
case_cd 'picks the last of three' 'cd /a && cd /b && cd /c && bump' '/c'
case_cd 'no cd returns empty' 'bump --no-tag' ''
case_cd 'quotes are stripped from the target' 'cd "/tmp/with space" && bump' '/tmp/with space'
case_cd 'a cd inside a quoted string is not a cd' 'echo "cd /nope" && bump' ''

echo "=== cd_at ==="
CDCHAIN='cd /a && x && cd /b && y && cd /c && z'
case_cdat 'the cd in effect at the statement between the second and third' "$CDCHAIN" 4 '/b'
case_cdat 'the cd in effect at the second statement' "$CDCHAIN" 2 '/a'
case_cdat 'nothing is in effect at the first statement' "$CDCHAIN" 1 ''
case_cdat 'the last cd is in effect at the final statement' "$CDCHAIN" 6 '/c'

echo "=== args ==="
case_args 'a quoted path holding a space stays one argument, quotes dropped' \
  'git checkout -- "src/a b.rs" other.rs' \
  'git|checkout|--|src/a b.rs|other.rs'
case_args 'a whole -m message is one argument, so a word in it is never an operand' \
  'git tag -a v1 -m "switch -c bad/name"' \
  'git|tag|-a|v1|-m|switch -c bad/name'
case_args 'an unexpanded dollar survives, which is what lets a gate refuse it' \
  'git checkout -- $HOME/x' \
  'git|checkout|--|$HOME/x'
case_args 'a mask byte survives as its own argument' \
  "git checkout -b ${SQ}$(printf '\001\001')${SQ}" \
  'git|checkout|-b|@@'
case_args 'an empty command yields nothing' '' ''

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
