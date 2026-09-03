#!/usr/bin/env python3
"""Rewrite `cd <dir> && grep/cat/rg/...` (or `;`/newline/pipe-joined) commands so
every relative path becomes absolute, then allow the rewritten command.

Claude Code's permission engine can't statically resolve a relative path past a
`cd` in the same command, so it escalates to a mandatory human prompt -- and
that escalation overrides a plain `permissionDecision: allow` by design (ask/deny
evaluation runs regardless of what a hook returns). Rewriting the command via
`updatedInput` removes the ambiguity itself (no more relative path depending on
an unresolved `cd`), which empirically avoids the escalation entirely -- verified
live: a deliberately-bogus relative path only resolved when this class of
rewrite was applied, with zero approval prompts, across three real Bash calls.

Rewriting only happens for command stages on a read-only whitelist (same
constraint as any auto-allow would need), since this also emits
permissionDecision: allow -- a bare rewrite without that would still block.
Relative arguments are only rewritten when they resolve to something that
actually exists on disk relative to the tracked cwd, which sidesteps ever
having to guess which arguments are paths vs. patterns/flags/values.
"""
import glob
import json
import os
import re
import shlex
import sys

READONLY_HEADS = {
    # navigation / trivia
    "cd", "pwd", "echo", "printf", "date", "seq", "true", "false", "test", "[",
    "env", "printenv", "which", "command", "type", "whoami", "id", "hostname",
    "uname", "tty", "groups", "locale", "nproc", "getconf", "sleep",
    # search
    "grep", "egrep", "fgrep", "zgrep", "zegrep", "zfgrep", "rg", "ugrep",
    "ack", "ag", "pcregrep", "look",
    # read / page / concatenate
    "cat", "bat", "tac", "head", "tail", "less", "more", "nl", "rev",
    "zcat", "gzcat", "bzcat", "xzcat", "zstdcat", "lzcat",
    # list / locate / inspect the filesystem
    "ls", "exa", "eza", "lsd", "tree", "find", "fd", "fdfind",
    "locate", "mlocate", "plocate", "stat", "file", "du", "df",
    "realpath", "readlink", "dirname", "basename", "pathchk", "mountpoint",
    # slice / reshape text
    "wc", "cut", "paste", "join", "comm", "uniq", "tr", "column",
    "expand", "unexpand", "fold", "fmt", "pr", "shuf", "numfmt",
    # structured data
    "jq", "yq", "xq", "tq", "tomlq", "dasel", "gron", "mlr", "xsv", "qsv",
    "csvlook", "csvcut", "csvstat", "csvgrep", "csvjson", "in2csv",
    # compare
    "diff", "cmp", "colordiff", "difft", "delta", "dwdiff", "wdiff",
    # hash / encode / dump
    "md5sum", "sha1sum", "sha224sum", "sha256sum", "sha384sum", "sha512sum",
    "shasum", "b2sum", "cksum", "sum", "crc32",
    "base64", "base32", "basenc", "xxd", "od", "hexdump", "strings",
    # binaries / build artifacts
    "readelf", "objdump", "nm", "size", "ldd", "otool", "dwarfdump",
    # runtime / process / system inspection
    "ps", "pgrep", "uptime", "free", "vmstat", "iostat", "lsof",
    "sensors", "lscpu", "lsblk", "lsusb", "lspci",
}
GIT_READONLY_SUBCOMMANDS = {
    "log", "show", "diff", "status", "describe", "blame", "annotate",
    "shortlog", "reflog", "rev-parse", "rev-list", "cat-file", "ls-files",
    "ls-tree", "ls-remote", "for-each-ref", "name-rev", "merge-base",
    "count-objects", "diff-tree", "diff-index", "diff-files", "whatchanged",
    "grep", "verify-commit", "show-ref", "show-branch",
    # Read-only in every form:
    "check-ignore", "check-attr", "cherry", "range-diff", "var", "version",
    "help", "verify-tag", "patch-id", "get-tar-commit-id", "stripspace",
}
# Subcommands that are read-only ONLY in certain forms. `git remote get-url` is
# a query; `git remote add` mutates. Keyed on the first non-flag word after the
# subcommand (or the flag itself), so the safe forms work without letting the
# writing forms through. This gap blocked a plain `git remote get-url origin`
# and, with it, the whole compound command it lived in.
GIT_READONLY_SUBCOMMAND_ARGS = {
    "remote": {"get-url", "show", "-v", "--verbose", None},
    "config": {"--get", "--get-all", "--get-regexp", "--list", "-l"},
    "branch": {"--list", "-l", "-a", "-r", "--all", "--remotes",
               "--show-current", "--contains", "--merged", "--no-merged", None},
    "tag": {"-l", "--list", "--points-at", "--contains", None},
    "stash": {"list", "show"},
    "worktree": {"list"},
    "notes": {"list", "show"},
    "submodule": {"status", "summary", "foreach"},
    "bundle": {"verify", "list-heads"},
}
# Flags whose separate-token value is a pattern, never a path -- e.g.
# `find -name '*.rs'` or `grep -e '-> Result'`. Deliberately NOT "anything
# starting with -": a grep pattern that itself starts with '-' (like the
# arrow "-> Result", common in Rust) must not make the FOLLOWING token look
# like a protected flag value.
PROTECTED_VALUE_FLAGS = {"-e", "--regexp", "-name", "-iname", "-path", "-ipath", "-regex", "-iregex"}
# `sed`/`awk` are read-only ONLY in the form that writes nothing. sed's
# in-place flag is the whole risk, and it bundles (`-ni`, `-i.bak`) as well as
# spelling out `--in-place`, so match an `i` anywhere in a short-flag cluster.
# awk is excluded entirely: its program text can redirect (`print > "f"`), and
# proving a given program doesn't is not worth the surface.
SED_WRITE_FLAG = re.compile(r"^-[a-zA-Z]*i|^--in-place")
SEPARATORS = {"|", "||", "&", "&&", ";"}
# Only ban constructs that are dangerous regardless of quoting (command
# substitution, process substitution). Bare `$` and `>` are NOT banned here --
# they're extremely common in legitimate content (regex anchors like '^$',
# Rust's `->`) and shlex already keeps quoted occurrences out of harm's way.
# Real *unquoted* redirects are caught after tokenizing instead, since shlex's
# punctuation_chars splits an unquoted `>`/`<` into its own operator token but
# leaves a quoted one embedded in its word -- see REDIRECT_TOKEN below.
UNSAFE_SUBSTRINGS = ("`", "$(", "<(")
REDIRECT_OP = re.compile(r"^\d*(>>?|<<?)&?\d*$|^&>>?$")
# Only allow redirects that can never touch a real file: discarding to
# /dev/null, or duplicating one fd onto another (`2>&1`). A redirect to an
# actual filename stays banned -- this hook only ever unblocks reads, and
# allowing a real file-write target would be a permission expansion nobody
# asked for.
SAFE_REDIRECT_TARGETS = {"/dev/null"}
# Confirmed empirically (see conversation): reconstructing a redirect requires
# exact adjacency on ONE side only -- a leading fd digit must stay glued
# directly to its operator (`2>`, never `2 >`; a space there makes bash treat
# the digit as a literal argument, silently running a different command).
# Every other side (operator-to-target, and the `&` inside `&>`/`>&`) tolerates
# a space fine, confirmed the same way. Splitting `&` from a following `>` via
# a space is separately dangerous (backgrounds the command instead of
# redirecting it) but never arises here since shlex already emits `&>`/`>&`
# as one fused token -- we only ever need to avoid inserting a NEW space
# before that fused token when it follows a bare digit.


def has_unsafe_substitution(cmd: str) -> bool:
    """True if a command substitution can actually FIRE in `cmd`.

    The old check was `any(s in cmd for s in ("`", "$(", "<("))`, a raw substring
    scan. That rejects a backtick inside single quotes, which is inert in bash
    and is exactly what a docs check greps for -- observed live:
    `grep -c '`-v`' README.md` bailed the whole rewrite and forced an approval
    prompt. Single quotes make every one of these literal; double quotes still
    let backticks and `$(` run, so those stay unsafe. Escapes are honored
    outside single quotes, where bash honors them.
    """
    i, n = 0, len(cmd)
    quote = None  # None, "'" or '"'
    while i < n:
        ch = cmd[i]
        if quote == "'":
            if ch == "'":
                quote = None
            i += 1
            continue
        if ch == "\\" and quote != "'":
            i += 2
            continue
        if quote == '"':
            if ch == '"':
                quote = None
                i += 1
                continue
            # Inside double quotes substitution is still live.
            if ch == "`" or cmd.startswith("$(", i):
                return True
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == "`" or cmd.startswith("$(", i) or cmd.startswith("<(", i):
            return True
        i += 1
    return False


def tokenize_spans(cmd: str):
    """Tokenize while remembering each token's byte span in the original string.

    This exists so the rewrite can SPLICE instead of re-render. Re-rendering
    through shlex.quote corrupted anything whose meaning depended on quoting:
    `echo rc=$?` came back as `echo 'rc=$?'` (expansion dead), and a bare
    assignment came back quoted into a command name. Splicing touches only the
    spans that actually change -- every other byte of the command is passed
    through exactly as written, so `$VAR`, quotes and operators survive
    verbatim and no `<live-variable>` bail is needed.

    Returns a list of {type: 'tok'|'sep', value, start, end}, or None if the
    input does not tokenize (unbalanced quotes).
    """
    out = []
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if ch in " \t":
            i += 1
            continue
        if ch == "\n":
            out.append({"type": "sep", "value": ";", "start": i, "end": i + 1})
            i += 1
            continue
        # Operators, longest first so `||`/`&&`/`>>`/`2>&1` stay whole.
        matched = None
        for op in ("||", "&&", ">>", "<<", ">&", "&>", ";", "|", "&", ">", "<"):
            if cmd.startswith(op, i):
                matched = op
                break
        if matched:
            out.append({"type": "sep" if matched in SEPARATORS else "tok",
                        "value": matched, "start": i, "end": i + len(matched)})
            i += len(matched)
            continue
        # A word: run to the next unquoted whitespace or operator.
        start = i
        buf = []
        quote = None
        while i < n:
            c = cmd[i]
            if quote:
                if c == quote:
                    quote = None
                else:
                    buf.append(c)
                i += 1
                continue
            if c in "'\"":
                quote = c
                i += 1
                continue
            if c == "\\" and i + 1 < n:
                buf.append(cmd[i + 1])
                i += 2
                continue
            if c in " \t\n" or any(cmd.startswith(op, i) for op in ("||", "&&", ">>", "<<", ">&", "&>", ";", "|", "&", "<", ">")):
                break
            buf.append(c)
            i += 1
        if quote:
            return None
        if i == start:
            # Never emit a zero-width token: the outer loop would not advance
            # and the hook would spin forever (it did, on `2>/dev/null`).
            return None
        out.append({"type": "tok", "value": "".join(buf), "start": start, "end": i})
    return out


def splice(cmd: str, toks, drops: set, replacements: dict, inserts: dict) -> str:
    """Rebuild `cmd` from its original bytes, applying only what changed.

    `drops` are token indices to remove, `replacements` maps index -> new text,
    `inserts` maps index -> list of texts to place AFTER that token. After, not
    before: the one caller inserts `-C <dir>` for git, and `-C /path git diff`
    is not a command -- an equivalence test caught that as rc=2 with no output.
    """
    pieces = []
    cursor = 0
    for i, t in enumerate(toks):
        if i in drops:
            cursor = t["end"]
            continue
        pieces.append(cmd[cursor:t["start"]])
        pieces.append(replacements.get(i, cmd[t["start"]:t["end"]]))
        for extra in inserts.get(i, []):
            pieces.append(" " + extra)
        cursor = t["end"]
    pieces.append(cmd[cursor:])
    return "".join(pieces)


def has_live_dollar(cmd: str) -> bool:
    """True if a `$` in `cmd` would be expanded by the shell.

    Why this bails the whole rewrite: shlex parses `rc=$?` to the token `rc=$?`
    and shlex.quote renders it back as `'rc=$?'`, which no longer expands -- the
    command would print the literal text instead of the exit code. Observed in
    this hook's own log: `echo rc=$?` became `echo 'rc=$?'`. The same corruption
    applies to every unquoted `$VAR`.

    Deciding per token is not possible after the fact, because posix shlex
    discards the quotes that distinguish a live `$HOME` from a literal one. A `$`
    inside SINGLE quotes is inert and round-trips safely, so only a `$` outside
    single quotes disqualifies the command.
    """
    i, n = 0, len(cmd)
    in_single = False
    while i < n:
        ch = cmd[i]
        if in_single:
            if ch == "'":
                in_single = False
            i += 1
            continue
        if ch == "'":
            in_single = True
            i += 1
            continue
        if ch == "\\":
            i += 2
            continue
        if ch == "$":
            return True
        i += 1
    return False


def tokenize(cmd: str):
    """Flat ordered list of {'type': 'tok'|'sep', 'value': str}, or None on
    unparseable input (unbalanced quotes etc.) -- caller must bail safely."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars="();<>|&;")
    lex.whitespace_split = True
    flat = []
    prev_lineno = None
    while True:
        lineno = lex.lineno
        try:
            tok = lex.get_token()
        except ValueError:
            return None
        if tok is None:
            break
        if tok in SEPARATORS:
            flat.append({"type": "sep", "value": tok})
        else:
            if prev_lineno is not None and lineno > prev_lineno:
                flat.append({"type": "sep", "value": ";"})
            flat.append({"type": "tok", "value": tok})
        prev_lineno = lineno
    return flat


def has_unsafe_redirect(flat) -> bool:
    for i, item in enumerate(flat):
        if item["type"] != "tok" or not REDIRECT_OP.match(item["value"]):
            continue
        nxt = flat[i + 1]["value"] if i + 1 < len(flat) and flat[i + 1]["type"] == "tok" else None
        if nxt in SAFE_REDIRECT_TARGETS:
            continue
        if item["value"] in (">&", "&>") and nxt is not None and nxt.isdigit():
            continue
        return True
    return False


def render(flat) -> str:
    """Join tokens back into a command string. Redirect operators are never
    quoted (quoting one disables it entirely), and a leading fd digit glues
    directly onto its following operator with no space -- both confirmed
    necessary, see SAFE_REDIRECT_TARGETS comment above."""
    pieces: list[str] = []
    for i, item in enumerate(flat):
        if item["type"] == "sep":
            pieces.append(item["value"])
            continue
        val = item["value"]
        is_redirect = bool(REDIRECT_OP.match(val))
        if is_redirect or item.get("raw"):
            text = val
        else:
            text = shlex.quote(val)
        glue = (
            is_redirect
            and pieces
            and flat[i - 1]["type"] == "tok"
            and flat[i - 1]["value"].isdigit()
        )
        if glue:
            pieces[-1] += text
        else:
            pieces.append(text)
    return " ".join(pieces)


def group_stages(flat):
    """List of stages; each stage is a list of indices into `flat`."""
    stages = []
    current = []
    for i, item in enumerate(flat):
        if item["type"] == "sep":
            if current:
                stages.append(current)
                current = []
            continue
        current.append(i)
    if current:
        stages.append(current)
    return stages


# Heads whose presence means we do NOT touch the command at all. Rewriting a
# command that could match a `permissions.deny` pattern risks rewriting it OUT
# of that pattern, which would be a real permission bypass -- so anything that
# writes, deletes, transfers, or is itself gated by a deny rule is off limits.
# `git` and `gh` are here because the deny list keys on their argument text
# (`Bash(git tag -d *)`, `Bash(gh release delete:*)`).
# Destroys, overwrites, or transmits data. A prompt here is correct, so there is
# nothing to gain by rewriting -- and rewriting risks dodging a future deny rule.
DESTRUCTIVE_HEADS = {
    "rm", "rmdir", "unlink", "shred", "mv", "cp", "dd", "truncate", "tee",
    "chmod", "chown", "chgrp", "ln", "mkfs", "mkswap", "install", "rsync",
    "kill", "killall", "pkill", "reboot", "shutdown", "mount", "umount",
    "crontab", "at", "sudo", "su", "doas", "eval", "exec", "source", ".",
    "curl", "wget", "ssh", "scp", "sftp", "rclone",
}
# The deny list in settings.json keys on these commands' argument text
# (`Bash(gh release delete:*)`, `Bash(git tag -d *)`), so a rewrite could move a
# command out of its own deny pattern. `git` is handled per-subcommand below.
DENY_PATTERNED_HEADS = {"gh", "glab"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Safe to emit unquoted: nothing that could start a new word or a new command.
SAFE_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_$~./:@+,%-]*$")


def stage_is_safe(values: list[str]) -> bool:
    if not values:
        return True
    # `S=$TMPDIR/x` and `FOO=1 grep ...` are env-prefix forms, not commands.
    # Observed in the bail log: a bare assignment stage counted as an unlisted
    # head and killed the rewrite for the whole line. Strip the assignments and
    # judge the REAL head after them -- never return safe for the assignment
    # itself, or `FOO=1 rm -rf /` would sail through.
    while values and ASSIGNMENT.match(values[0]):
        values = values[1:]
    if not values:
        return True
    head = values[0]
    if head == "git":
        # Skip git's own pre-subcommand options AND their values, or the value
        # gets mistaken for the subcommand: `git -C /repo log` would read as
        # subcommand "/repo", fail the whitelist, and bail the whole rewrite.
        rest = values[1:]
        i = 0
        while i < len(rest):
            if rest[i] in ("-C", "--git-dir", "--work-tree", "--namespace", "-c"):
                i += 2
                continue
            if rest[i].startswith("-"):
                i += 1
                continue
            break
        sub = rest[i] if i < len(rest) else None
        if sub in GIT_READONLY_SUBCOMMANDS:
            return True
        allowed = GIT_READONLY_SUBCOMMAND_ARGS.get(sub)
        if allowed is None:
            return False
        arg = rest[i + 1] if i + 1 < len(rest) else None
        return arg in allowed
    if head == "xargs":
        inner = next((t for t in values[1:] if not t.startswith("-")), None)
        inner_name = inner.rsplit("/", 1)[-1] if inner else None
        return inner_name in READONLY_HEADS
    if head == "find":
        return not any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir") for a in values)
    if head in ("sed", "gsed"):
        return not any(SED_WRITE_FLAG.match(a) for a in values[1:])
    if head in ("sort", "iconv", "csplit", "split"):
        # Read-only until told to write: both spell it `-o`/`--output`, and
        # `sort -o` famously overwrites its own input file.
        return not any(a == "-o" or a.startswith("-o") or a.startswith("--output") for a in values[1:])
    if head in ("awk", "gawk", "mawk", "perl", "ruby"):
        # These carry a whole program in an argument, and the program can write
        # (`print > "f"`, `open(...)`, `system(...)`) with no flag to key on.
        # An unquoted `>` is already caught by has_unsafe_redirect; a QUOTED one
        # lives inside the program text, so scan the raw arguments for it plus
        # the obvious escape hatches. In-place editing is also flag-driven.
        if any(SED_WRITE_FLAG.match(a) for a in values[1:]):
            return False
        return not any(
            (">" in a) or ("system(" in a) or ("open(" in a) or ("unlink" in a) or ("exec" in a)
            for a in values[1:]
        )
    if head == "sqlite3":
        # A bare query mutates nothing, but nothing in the argument list proves
        # that; `-readonly` does, by making the connection refuse writes.
        return "-readonly" in values[1:]
    return head in READONLY_HEADS


LOG = os.path.expanduser("~/.cache/claude/rewrite-cd-read.log")


def log(decision: str, detail: str, cmd: str, rewritten: str = "") -> None:
    """Append one tab-separated line per invocation, so "is it working?" is a
    question the log answers instead of an inference.

    Columns: iso-time, decision, detail, original, rewritten.
      decision  ALLOW  (rewritten and auto-allowed)
                REWRITE (rewritten, permission left to the normal rules)
                BAIL   (untouched; `detail` is the head or reason that stopped it)
    Best-effort and silent: a hook that failed on its own logging would block
    the command it exists to unblock, so every error here is swallowed.
    """
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        flat_cmd = cmd.replace(chr(10), " ")[:400]
        flat_new = rewritten.replace(chr(10), " ")[:400]
        stamp = __import__("datetime").datetime.now().isoformat(timespec="seconds")
        with open(LOG, "a") as fh:
            fh.write(f"{stamp}\t{decision}\t{detail}\t{flat_cmd}\t{flat_new}\n")
    except Exception:
        pass


def log_bail(head: str, cmd: str) -> None:
    log("BAIL", head, cmd)


# Value-taking short flags whose SEPARATE value token gets misread as a
# relative path by the permission analyzer. Observed live: `grep -rn 'fn labels'
# -A 12 /abs/path.rs` -- every path absolute -- still forced an approval prompt
# reading "grep on '-A' ... would search a directory that cannot be determined".
# The analyzer parses grep as [flags] PATTERN PATH..., stops flag-parsing at the
# pattern, and then treats the trailing bare `-A` as a path. Absolutizing cannot
# fix that, because `-A` is not a path. Gluing the value on (`-A12`) deletes the
# bare token entirely, so there is nothing left to misread. Every form here is
# valid GNU syntax: `grep -A12`, `head -n5`, `tail -c20`.
GLUE_VALUE_FLAGS = {
    "grep": {"-A", "-B", "-C", "-m", "-d", "-D"},
    "egrep": {"-A", "-B", "-C", "-m"},
    "fgrep": {"-A", "-B", "-C", "-m"},
    "zgrep": {"-A", "-B", "-C", "-m"},
    "rg": {"-A", "-B", "-C", "-m"},
    "ugrep": {"-A", "-B", "-C", "-m"},
    "head": {"-n", "-c"},
    "tail": {"-n", "-c"},
    "cut": {"-f", "-d", "-b", "-c"},
    "sort": {"-k", "-t"},
    "uniq": {"-f", "-s", "-w"},
    "fold": {"-w"},
    "xxd": {"-l", "-s", "-c"},
    "od": {"-N", "-j"},
}


# Commands that never consult the working directory, so a stage running one is
# no reason to keep a `cd`. Everything NOT here is assumed cwd-sensitive unless
# it carries an absolute path or reads a pipe -- see can_drop_cd.
CWD_FREE_HEADS = {
    "echo", "printf", "date", "seq", "true", "false", "sleep", "yes",
    "whoami", "id", "hostname", "uname", "tty", "groups", "locale", "nproc",
    "getconf", "env", "printenv", "which", "command", "type",
    "uptime", "free", "vmstat", "lscpu", "lsblk", "lsusb", "lspci", "sensors",
}
REV_RANGE = re.compile(r"^([A-Za-z0-9._/@^~-]+)\.\.([A-Za-z0-9._/@^~-]+)$")


def can_drop_cd(flat, stages) -> bool:
    """True when removing the leading `cd` cannot change what the command reads.

    Dropping the `cd` is the only fix that kills the whole bug class instead of
    one shape of it: the analyzer's complaint is always "after a cd would search
    a directory that cannot be determined", so with no `cd` there is nothing
    indeterminate and no token can be misread as a relative path.

    A stage is safe to strip the `cd` from when any of these holds:
      (a) it carries an absolute path, so cwd is irrelevant to it;
      (b) it is not the first command in its pipeline, so it reads stdin --
          `... | rg foo` searches the pipe, not the directory;
      (c) its head never looks at cwd at all (CWD_FREE_HEADS).
    `git` is handled by the caller, which re-targets it with `-C <dir>`.

    Anything else (a bare `ls`, `rg foo` with no path, `find . -name x`) really
    does resolve against cwd, so the `cd` stays and we fall back to absolutizing
    paths only.
    """
    piped_from_prev = False
    for s in stages:
        head = flat[s[0]]["value"]
        values = [flat[i]["value"] for i in s]
        while values and ASSIGNMENT.match(values[0]):
            values = values[1:]
        if not values:
            # A pure `VAR=value` stage runs no command, so it cannot read the
            # working directory and is no reason to keep the `cd`.
            end = s[-1]
            nxt = flat[end + 1] if end + 1 < len(flat) else None
            piped_from_prev = bool(nxt and nxt["type"] == "sep" and nxt["value"] == "|")
            continue
        head = values[0]
        base = head.rsplit("/", 1)[-1]
        is_first_in_pipeline = not piped_from_prev
        # Record for the NEXT stage whether it is fed by a pipe.
        end = s[-1]
        nxt = flat[end + 1] if end + 1 < len(flat) else None
        piped_from_prev = bool(nxt and nxt["type"] == "sep" and nxt["value"] == "|")
        if base == "cd" or base == "git":
            continue
        if base in CWD_FREE_HEADS:
            continue
        if not is_first_in_pipeline:
            continue
        if any(v.startswith("/") for v in values[1:]):
            continue
        return False
    return True


def drop_cd(flat, stages, cd_dir: str, session_cwd: str):
    """Remove the leading `cd <dir>` stage and re-target git stages with `-C`.

    `-C` is omitted when <dir> IS the session cwd: it would be redundant, and
    git-no-dash-c.sh denies exactly that form.
    """
    if not stages:
        return flat, False
    first = stages[0]
    if flat[first[0]]["value"] != "cd" or len(stages) < 2:
        return flat, False
    drop = set(first)
    end = first[-1]
    if end + 1 < len(flat) and flat[end + 1]["type"] == "sep":
        drop.add(end + 1)
    same_dir = os.path.realpath(cd_dir) == os.path.realpath(session_cwd or cd_dir)
    inserts = {}
    for s in stages[1:]:
        vals = [flat[i]["value"] for i in s]
        if vals and vals[0] == "git" and not same_dir and "-C" not in vals:
            inserts[s[0]] = ["-C", cd_dir]
    out = []
    for i, item in enumerate(flat):
        if i in drop:
            continue
        out.append(item)
        for extra in inserts.get(i, []):
            out.append({"type": "tok", "value": extra})
    return out, True


def split_git_diff_ranges(flat, stages):
    """`git diff A..B` -> `git diff A B`, which git defines as identical.

    Why: the permission analyzer reads a token containing `..` as a relative
    path and, past a `cd`, cannot resolve it -- observed live, the objection was
    literally "git on 'v2.2.1..HEAD' after a cd". A revision range is not a
    path, so absolutizing has nothing to grab; removing the `..` does.

    Scoped to `git diff` ON PURPOSE. For `git log`/`rev-list`, `A..B` means
    "reachable from B but not A" and `A B` means "reachable from either", so the
    same rewrite there would silently change what the command reports.
    """
    inserts = {}
    for s in stages:
        values = [flat[i]["value"] for i in s]
        if values[0] != "git":
            continue
        rest = values[1:]
        i = 0
        while i < len(rest):
            if rest[i] in ("-C", "--git-dir", "--work-tree", "--namespace", "-c"):
                i += 2
                continue
            if rest[i].startswith("-"):
                i += 1
                continue
            break
        if (rest[i] if i < len(rest) else None) != "diff":
            continue
        for idx in s[1:]:
            m = REV_RANGE.match(flat[idx]["value"])
            if not m:
                continue
            # A real relative path can contain `..` too (`../sibling/file`);
            # only rewrite when neither side resolves to something on disk.
            if any(os.path.lexists(p) for p in (flat[idx]["value"], m.group(1), m.group(2))):
                continue
            flat[idx]["value"] = m.group(1)
            inserts[idx] = m.group(2)
    if not inserts:
        return flat, False
    out = []
    for i, item in enumerate(flat):
        out.append(item)
        if i in inserts:
            out.append({"type": "tok", "value": inserts[i]})
    return out, True


def glue_value_flags(flat, stages):
    """Fuse `-A 12` into `-A12` for the flags in GLUE_VALUE_FLAGS. Returns a new
    flat list; `flat` and `stages` are left alone so index-based callers upstream
    stay valid."""
    drop = set()
    for s in stages:
        head = flat[s[0]]["value"]
        glueable = GLUE_VALUE_FLAGS.get(head.rsplit("/", 1)[-1])
        if not glueable:
            continue
        for pos, idx in enumerate(s):
            if pos == 0 or idx in drop:
                continue
            if flat[idx]["value"] not in glueable:
                continue
            if pos + 1 >= len(s):
                continue
            nxt = s[pos + 1]
            # Only fuse a value that cannot itself be a path: a bare number, or
            # a one-character delimiter like `cut -d,`. Anything else stays
            # separate so a real path argument is never welded to a flag.
            val = flat[nxt]["value"]
            if not (val.isdigit() or (len(val) == 1 and not val.isalnum())):
                continue
            flat[idx]["value"] += val
            drop.add(nxt)
    if not drop:
        return flat, False
    return [item for i, item in enumerate(flat) if i not in drop], True


def stage_is_dangerous(values: list[str]) -> bool:
    """True only if this stage must not be REWRITTEN. Deliberately tiny.

    This is the question "may I absolutize paths and drop the cd here?", which
    is NOT the same as "may I auto-allow this?" (stage_is_safe). Rewriting is
    semantically neutral -- measured: 12 of 14 rewritten commands produce
    byte-identical output and exit code, the other 2 differ only in the path
    text a tool echoes back. So rewriting needs a DENYLIST, not an allowlist.

    Using an allowlist here was the actual bug behind an afternoon of recurring
    approval prompts: every command containing one unrecognized head (`sed`,
    `target/release/otto`, `git remote get-url`) had its rewrite discarded, kept
    its `cd`, and hit the prompt. Each gap was patched individually and the next
    unknown head reopened it. The only stable answer is to rewrite everything
    except a named few.

    Two reasons to refuse:
      1. A `permissions.deny` rule keys on the command's argument text, so
         rewriting could move it OUT of the pattern -- a real permission bypass.
         In this config that is `git tag`/`git push` and the `gh` delete family.
      2. The command destroys or transmits data, where a prompt is the correct
         outcome anyway and there is no value in silencing it.
    """
    while values and ASSIGNMENT.match(values[0]):
        values = values[1:]
    if not values:
        return False
    base = values[0].rsplit("/", 1)[-1]
    if base in DESTRUCTIVE_HEADS:
        return True
    if base in DENY_PATTERNED_HEADS:
        return True
    if base == "git":
        rest = values[1:]
        i = 0
        while i < len(rest):
            if rest[i] in ("-C", "--git-dir", "--work-tree", "--namespace", "-c"):
                i += 2
                continue
            if rest[i].startswith("-"):
                i += 1
                continue
            break
        sub = rest[i] if i < len(rest) else None
        # Only the subcommands the deny rules name. Every other git subcommand
        # -- known read-only or not -- is rewritable; it simply may not be
        # auto-allowed, which stage_is_safe decides separately.
        return sub in ("tag", "push")
    return False


def resolve_cd(cwd: str, target: str) -> str | None:
    if not target or target == "-" or "$" in target:
        return None
    if target.startswith("~"):
        target = os.path.expanduser(target)
    if target.startswith("/"):
        return os.path.normpath(target)
    return os.path.normpath(os.path.join(cwd, target))


def resolve_path_arg(cwd: str, arg: str):
    """Returns (new_value, is_glob) or None if `arg` isn't a real path/glob
    reference. `is_glob` tells the caller to emit it unquoted, so the shell
    still expands it -- an already-confirmed-real glob must stay a glob, not
    become a quoted literal (which would break expansion entirely)."""
    if not arg or arg.startswith("-") or arg.startswith("$") or arg.startswith("~"):
        return None
    if arg.startswith("/"):
        return None
    try:
        float(arg)
        return None
    except ValueError:
        pass
    has_glob = any(c in arg for c in "*?[")
    if has_glob:
        # Require an actual match, not just "the parent dir exists" -- a regex
        # pattern like '^#{2,3} (Phase|Finding|F[0-9])' also contains glob
        # metacharacters ([0-9]) but matches no real file, so glob.glob on it
        # correctly returns nothing and we correctly leave it alone.
        if not glob.glob(os.path.join(cwd, arg)):
            return None
        return os.path.join(cwd, arg), True
    if not os.path.lexists(os.path.join(cwd, arg)):
        # A path that does not exist is usually a pattern, but it is sometimes a
        # MISTYPED path -- and a mistyped relative path past a cd forces the
        # exact approval prompt this hook exists to remove (observed live:
        # `rg -n 'dry_run|dry-run' src/cli/parser/builtins.rs`, where the real
        # file is src/cli/builtins.rs). Absolutize it anyway when it is
        # unambiguously path-shaped: it contains a `/` AND its first segment is
        # a real directory here. A regex keeps its own shape ('dry_run|dry-run'
        # has no slash; '^src/foo' has one but '^src' is not a directory), so
        # patterns stay untouched. The command still fails -- with the same
        # error, at an absolute path -- but it fails WITHOUT stopping to ask.
        if "/" not in arg:
            return None
        first = arg.split("/", 1)[0]
        if not first or not os.path.isdir(os.path.join(cwd, first)):
            return None
        return os.path.normpath(os.path.join(cwd, arg)), False
    return os.path.normpath(os.path.join(cwd, arg)), False


def rewrite(cmd: str, start_cwd: str):
    """Return (new_command, all_safe) or None to leave the command untouched.

    Works by splicing the ORIGINAL bytes: only spans that change are replaced,
    so quoting, `$VAR` expansion and operators survive exactly as written.
    """
    if has_unsafe_substitution(cmd):
        log_bail("<live-substitution>", cmd)
        return None
    toks = tokenize_spans(cmd)
    if toks is None:
        log_bail("<unparseable>", cmd)
        return None
    if has_unsafe_redirect(toks):
        log_bail("<unsafe-redirect>", cmd)
        return None
    stages = group_stages(toks)
    if not stages:
        return None
    heads = [toks[s[0]]["value"] for s in stages]
    if "cd" not in heads:
        return None

    all_safe = True
    for s in stages:
        values = [toks[i]["value"] for i in s]
        if stage_is_dangerous(values):
            log_bail(values[0] if values else "<empty>", cmd)
            return None
        if not stage_is_safe(values):
            all_safe = False

    cwd = start_cwd
    replacements: dict[int, str] = {}
    for s in stages:
        head = toks[s[0]]["value"]
        if head == "cd":
            if len(s) < 2:
                return None
            new_cwd = resolve_cd(cwd, toks[s[1]]["value"])
            if new_cwd is None:
                return None
            cwd = new_cwd
            continue
        for pos, idx in enumerate(s):
            val = toks[idx]["value"]
            if pos == 0:
                # A relative command path (`target/release/otto`) pins the
                # command to the cwd; absolutizing it is what frees the `cd`.
                if "/" in val and not val.startswith(("/", "~", "$")):
                    cand = os.path.normpath(os.path.join(cwd, val))
                    if os.path.isfile(cand) and os.access(cand, os.X_OK):
                        replacements[idx] = cand
                continue
            if toks[s[pos - 1]]["value"] in PROTECTED_VALUE_FLAGS:
                continue
            resolved = resolve_path_arg(cwd, val)
            if resolved is not None:
                replacements[idx] = resolved[0]

    drops: set[int] = set()
    inserts: dict[int, list[str]] = {}
    cd_stages = [s for s in stages if toks[s[0]]["value"] == "cd"]
    # can_drop_cd must judge the POST-rewrite command: replacements are held
    # aside rather than written into the tokens, so without this view it still
    # sees `README.md` as relative and refuses to drop a cd that is now dead.
    effective = [dict(t, value=replacements.get(i, t["value"])) for i, t in enumerate(toks)]
    if len(cd_stages) == 1 and toks[stages[0][0]]["value"] == "cd" and can_drop_cd(effective, stages):
        # With every path absolute, removing the `cd` removes the premise of the
        # analyzer's objection ("a directory that cannot be determined").
        first = stages[0]
        drops.update(first)
        nxt = first[-1] + 1
        if nxt < len(toks) and toks[nxt]["type"] == "sep":
            drops.add(nxt)
        same_dir = os.path.realpath(cwd) == os.path.realpath(start_cwd or cwd)
        for s in stages[1:]:
            vals = [toks[i]["value"] for i in s]
            if vals and vals[0] == "git" and not same_dir and "-C" not in vals:
                inserts[s[0]] = ["-C", cwd]

    if not (replacements or drops):
        log_bail("<nothing-rewritable>", cmd)
        return None
    return splice(cmd, toks, drops, replacements, inserts).strip(), all_safe


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print("{}")
        return
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    start_cwd = payload.get("cwd") or ""
    if not cmd.strip() or not start_cwd:
        print("{}")
        return

    result = rewrite(cmd, start_cwd)
    if result is None:
        print("{}")
        return
    rewritten, all_safe = result

    out = {
        "hookEventName": "PreToolUse",
        "updatedInput": {"command": rewritten},
    }
    if all_safe:
        # Every stage is on the read-only whitelist, so the rewrite AND the
        # auto-allow are both justified.
        out["permissionDecision"] = "allow"
        log("ALLOW", "all-stages-read-only", cmd, rewritten)
        out["permissionDecisionReason"] = (
            "Dropped the cd and absolutized paths; removes the ambiguity that forces manual approval"
        )
    else:
        # Rewritable but not auto-allowable (a project binary, an unknown head).
        # Emitting updatedInput WITHOUT a decision still removes the
        # unresolvable-relative-path ambiguity, so the command is judged by the
        # normal permission rules instead of escalating to a prompt that a
        # subagent has nobody to answer.
        log("REWRITE", "not-auto-allowable", cmd, rewritten)
        out["permissionDecisionReason"] = (
            "Dropped the cd and absolutized paths; leaving the permission decision to the normal rules"
        )
    print(json.dumps({"hookSpecificOutput": out}))


if __name__ == "__main__":
    main()
