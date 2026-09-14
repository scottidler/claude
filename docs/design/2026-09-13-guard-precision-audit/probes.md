# Differential probes: baseline 8ee8f60 vs current db3e2ab

Method. This repo has no tags, so the baseline is commit `8ee8f60`. Each guard's
baseline copy was extracted with `git show 8ee8f60:HOME/.claude/hooks/<g>.sh` into
`$TMPDIR`. Every probe fed the SAME PreToolUse JSON to the baseline copy and to the
live file on the branch, and compared `.hookSpecificOutput.permissionDecision`.
No live `git tag`, `git push`, `git checkout <branch>`, or `git reset` was run
against any real repo. Two fixture repos were created under `$TMPDIR`.

Repro shape:

```
jq -nc --arg c '<COMMAND>' --arg cwd "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
  | bash HOME/.claude/hooks/git-release-guard.sh
```

## git-release-guard.sh, session cwd = repo root

| command | 8ee8f60 | db3e2ab | verdict |
|---|---|---|---|
| `git push origin --tags` | deny | deny | SAME |
| `git push origin "--tags"` | deny | deny | SAME (design contract holds) |
| `git push origin '--tags'` | deny | deny | SAME |
| `echo $(git push origin --tags)` | deny | deny | SAME (nested stmt yielded) |
| `command git push origin --tags` | deny | deny | SAME |
| `sudo git push origin --tags` | deny | deny | SAME |
| `/usr/bin/git push origin --tags` | deny | deny | SAME |
| `GIT_DIR=. git push origin --tags` | deny | deny | SAME |
| `git push origin --tags &` | deny | deny | SAME |
| `git push origin --tags 2>&1 \| cat` | deny | deny | SAME |
| `git push origin --tags # comment` | deny | deny | SAME |
| `git push origin ${x:---tags}` | deny | deny | SAME |
| `echo hi; (cd /tmp && git push origin --tags)` | deny | deny | SAME |
| `echo hello-world && git push origin --tags` | deny | deny | SAME |
| `git tag -f -a v1 -m moved` | allow | deny | INTENDED (gap closed) |
| `git tag -fa v1 -m moved` | allow | deny | INTENDED (gap closed) |
| `git tag -a v9.9.9 -m probe` off main | allow | deny | INTENDED (gap closed) |
| `git tag --contains HEAD` | n/a | allow | INTENDED (list-mode allow) |
| `git checkout -- a.txt` dirty tree | deny | allow | INTENDED (disclosed over-reach fix) |
| `git restore a.txt` dirty tree | deny | allow | INTENDED (disclosed) |
| `git checkout -- "*"` | deny | deny | SAME (glob refusal) |
| `git checkout -- :/` | deny | deny | SAME |
| `git checkout -- $F/a.txt` | deny | deny | SAME (`$` refusal) |
| `git restore --staged a.txt` | deny | deny | SAME |
| `git restore --source=HEAD a.txt` | deny | deny | SAME |
| `(git push origin --tags)` | deny | allow | **REGRESSION** |
| `{ git push origin --tags; }` | deny | allow | **REGRESSION** |
| `true && (git push origin --tags)` | deny | allow | **REGRESSION** |
| `if git push origin --tags; then echo ok; fi` | deny | allow | **REGRESSION** |
| `if true; then git reset --hard; fi` | deny | allow | **REGRESSION** |
| `while git push origin --tags; do :; done` | deny | allow | **REGRESSION** |
| `until git push origin --tags; do :; done` | deny | allow | **REGRESSION** |
| `for x in 1; do git push origin --tags; done` | deny | allow | **REGRESSION** |
| `case x in x) git push origin --tags;; esac` | deny | allow | **REGRESSION** |
| `time git push origin --tags` | deny | allow | **REGRESSION** |
| `! git push origin --tags` | deny | allow | **REGRESSION** |
| `nohup git push origin --tags` | deny | allow | **REGRESSION** |
| `timeout 5 git push origin --tags` | deny | allow | **REGRESSION** |
| `coproc git push origin --tags` | deny | allow | **REGRESSION** |
| `eval "git push origin --tags"` | deny | allow | **REGRESSION** |
| `eval git push origin --tags` | deny | allow | **REGRESSION** |
| `xargs -I{} git push origin --tags </dev/null` | deny | allow | **REGRESSION** |
| `echo <(git push origin --tags)` | deny | allow | **REGRESSION** |
| `echo >(git push origin --tags)` | deny | allow | **REGRESSION** |
| `f(){ git push origin --tags; }; f` | deny | allow | **REGRESSION** |
| `\git tag -d v1` | deny | allow | **REGRESSION** |
| `{ git push --force origin main; }` | deny | allow | **REGRESSION** |
| `bash -c "(git push origin --tags)"` | deny | allow | **REGRESSION** |
| `bash -c "if true; then git push origin --tags; fi"` | deny | allow | **REGRESSION** |
| `(git reset --hard)` dirty tree | deny | allow | **REGRESSION** |
| `"git" push origin --tags` | allow | allow | SAME (pre-existing bypass, NOT a regression) |
| `"git" tag -fa v1 -m moved` | allow | allow | SAME (pre-existing bypass) |
| `git push origin --ta""gs` | allow | allow | SAME (pre-existing bypass) |
| `git push origin -"-tags"` | allow | allow | SAME (pre-existing bypass) |
| `g=git; $g push origin --tags` | allow | allow | SAME (pre-existing, unfixable statically) |
| `git push \<newline>origin --tags` | allow | allow | SAME (pre-existing) |

`git clean -fd` was probed twice. Against a fixture with modified-but-tracked files
only it allows on both sides (the gate correctly asks for untracked count, not
porcelain). Against a fixture holding an untracked file it denies. NOT a regression.

## manifest-scope-guard.sh

| command | 8ee8f60 | db3e2ab | verdict |
|---|---|---|---|
| `manifest apply` | deny | deny | SAME |
| `(manifest apply)` | allow | allow | SAME (pre-existing) |
| `if true; then manifest apply; fi` | deny | allow | **REGRESSION** |

## secret-echo-guard.sh

| command | 8ee8f60 | db3e2ab | verdict |
|---|---|---|---|
| `echo $GH_TOKEN` | deny | deny | SAME |
| `(echo $GITHUB_TOKEN)` | deny | deny | SAME |
| `if true; then echo $GITHUB_TOKEN; fi` | deny | deny | SAME |
| `eval "echo $GITHUB_TOKEN"` | deny | deny | SAME |
| `bash -c 'echo $GH_TOKEN'` | deny | deny | SAME |
| `sh -c 'echo $GH_TOKEN'` | deny | deny | SAME |
| `bash -lc 'echo $GH_TOKEN'` | deny | allow | **REGRESSION** |
| `bash -xc "echo $GH_TOKEN"` | deny | deny | SAME |
| `cat <<EOF` / `$GH_TOKEN` / `EOF` (unquoted delimiter) | allow | allow | SAME (pre-existing gap, now structural) |
| `echo "RIPGREP_CONFIG_PATH=$RIPGREP_CONFIG_PATH"` | deny | allow | INTENDED (AC2) |

## branch-name-guard.sh (new file, no baseline)

| command | db3e2ab |
|---|---|
| `git checkout -b feat/thing` | deny |
| `git switch -c feat/thing` | deny |
| `git branch feat/thing` | deny |
| `git checkout -b chore/bump-0.9.0` | deny |
| `git checkout -b fix-auth-bug` | allow |
| `(git checkout -b feat/thing)` | allow (bypass) |
| `if true; then git checkout -b feat/thing; fi` | allow (bypass) |
| `"git" checkout -b feat/thing` | allow (bypass) |
| `git checkout -bfix/x` | allow (bypass) |

## Library degradation (missing or broken lib.sh must never deny)

Copied five guards into a scratch dir and swapped `lib.sh` four ways, feeding
`git push origin --tags`:

| lib.sh state | git-release-guard | branch-name-guard | secret-echo-guard | manifest-scope-guard |
|---|---|---|---|---|
| absent | `{}` | `{}` | `{}` | `{}` |
| empty (sources OK, no functions) | `{}` + stderr noise | `{}` + stderr | `{}` + stderr | `{}` + stderr |
| syntax error | `{}` | `{}` | `{}` | `{}` |
| stub (`stmts(){ return 0; }`) | `{}` + stderr | `{}` | `{}` | `{}` |

Contract HOLDS: never a deny, always pass-through. Stderr noise only.

## --body-file expansion never evals

| command | result | side effect |
|---|---|---|
| `gh pr create --body-file "$TMPDIR/bf/body.md"` | allow | none |
| `gh pr create --body-file "$(touch /tmp/PWNED_REVIEW_PANEL; echo x)"` | allow | file NOT created |
| ``gh pr create --body-file "`touch /tmp/PWNED2; echo x`"`` | allow | file NOT created |

Confirmed with `ls /tmp/PWNED_REVIEW_PANEL /tmp/PWNED2` -> both "No such file".
The expansion at `git-release-guard.sh:523-530` is pure `${bf/#...}` substitution.
