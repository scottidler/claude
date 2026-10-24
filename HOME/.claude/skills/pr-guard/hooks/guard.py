#!/usr/bin/env python3
"""PreToolUse guard: deny top-level PR creation and name /pr:create instead.

Reads the PreToolUse hook JSON on stdin. Prints a deny decision to stdout, or
nothing to allow. Always exits 0 on a decision; a crash exits 1, which Claude
Code treats as a non-blocking hook error, so the guard fails open.

Denied (Bash and Monitor `tool_input.command`, and MCP tool names):
  gh pr create | gh pr new, gh stack submit, gh api POST repos/o/r/pulls,
  gh api graphql createPullRequest, curl POST api.github.com/repos/o/r/pulls,
  hub pull-request, mcp__*github*__create_pull_request | create_pr.

The command is parsed into statements, recursing into $( ), backticks, <( ),
`bash -c` / `sh -c` / `eval` strings, and the $( ) / backticks inside unquoted
heredoc bodies, since the shell runs all of those. Quoted arguments, comments
and quoted-delimiter heredoc bodies are data. A command whose quoting does not
balance is unparseable and allowed: the org contract check sees whatever PR
results.

PR_CREATE_ENFORCEMENT=off allows everything. PR_CREATE_GUARD_DEBUG=1 logs every
decision at DEBUG to stderr.

The parser is a Python port of scottidler/claude HOME/.claude/hooks/lib.sh
(statement splitting, comment and heredoc masking, `bash -c` / `eval`
recursion, the wrapper and reserved-word tables) and the rails plugin's
command-head scanner (HOME/.claude/skills/rails/hooks/index.ts).
"""

import json
import logging
import os
import re
import sys

log = logging.getLogger("pr.guard")

REASON = (
    "PR creation goes through /pr:create (pr@tatari-skills). Invoke Skill(pr:create) with this "
    "session's context; it writes the reviewer-first body, regroups commits, and opens the PR "
    "through scripts/create.py. Do not retry with another PR-creation command."
)
ENFORCEMENT_ENV = "PR_CREATE_ENFORCEMENT"
DEBUG_ENV = "PR_CREATE_GUARD_DEBUG"

SHELL_TOOLS = {"Bash", "Monitor"}
MCP_CREATE = re.compile(r"(?i)^mcp__.*github.*__(create_pull_request|create_pr)$")
PULLS_ENDPOINT = re.compile(r"^/?repos/[^/]+/[^/]+/pulls/?$")
CURL_PULLS_URL = re.compile(r"^(?:https?://)?api\.github\.com/repos/[^/]+/[^/]+/pulls/?$")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DASH_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")

# Stands in for a substitution's value inside a word: unknowable, never a match.
SUBSTITUTED = "\x01"
MAX_DEPTH = 16

# lib.sh's tables. RESERVED gains `{` `}` `function`, which lib.sh handles as
# statement boundaries instead; here a brace is a word the head walk steps over.
RESERVED = {
    "if", "then", "elif", "else", "fi", "do", "done", "while", "until", "for", "select",
    "case", "esac", "time", "coproc", "!", "{", "}", "function",
}
WRAPPERS = {"command", "builtin", "exec", "sudo", "env", "nohup", "time", "nice", "stdbuf", "timeout", "xargs"}
WRAPPER_VALUE_FLAGS = {"-u", "-n", "-I", "-k", "-s"}
TIMEOUT_DURATION = re.compile(r"^[0-9]+(\.[0-9]+)?[smhd]?$")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}

GH_API_VALUE_FLAGS = {
    "-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header", "--input",
    "-q", "--jq", "-t", "--template", "--hostname", "-p", "--preview", "--cache",
}
GH_API_BODY_FLAGS = {"-f", "--raw-field", "-F", "--field", "--input"}
CURL_DATA_FLAGS = {"-d", "--data", "--data-raw", "--data-binary", "--data-urlencode", "--data-ascii", "--json"}

ANSI_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "e": "\x1b", "f": "\f", "v": "\v"}


class Unparseable(ValueError):
    """The command's quoting or substitutions do not balance."""


class Lexer:
    """Splits one shell string into statements, each a list of words with quotes removed.

    Nested code the shell runs ($( ), backticks, <( ), expanded heredoc bodies)
    lands in the same `statements` list as statements of its own.
    """

    def __init__(self, src: str, depth: int = 0):
        self.s = src
        self.depth = depth
        self.statements: list[list[str]] = []

    def run(self) -> list[list[str]]:
        self.lex(0, None)
        return self.statements

    def nested(self, code: str) -> None:
        """Lex a separate string (backtick body, bash -c / eval argument). Unparseable: skipped."""
        if self.depth + 1 > MAX_DEPTH:
            log.debug("nested: depth %d exceeded, skipped", MAX_DEPTH)
            return
        try:
            self.statements.extend(Lexer(code, self.depth + 1).run())
        except Unparseable as exc:
            log.debug("nested: unparseable %r: %s", code, exc)

    def lex(self, i: int, closer: str | None) -> int:
        """Lex from i to the end, or to the `)` closing a substitution when closer is ')'.
        Returns the index just past where lexing stopped."""
        s, n = self.s, len(self.s)
        words: list[str] = []
        cur: list[str] = []
        in_word = False
        drop_next = False
        pending: list[tuple[str, bool, bool]] = []
        paren = 0

        def end_word() -> None:
            nonlocal cur, in_word, drop_next
            if in_word:
                if drop_next:
                    drop_next = False
                else:
                    words.append("".join(cur))
            cur = []
            in_word = False

        def end_statement() -> None:
            nonlocal drop_next
            end_word()
            drop_next = False
            if words:
                self.statements.append(list(words))
            words.clear()

        while i < n:
            c = s[i]
            nxt = s[i + 1] if i + 1 < n else ""
            if c == "\\":
                if nxt == "\n":
                    i += 2
                    continue
                if nxt:
                    cur.append(nxt)
                    in_word = True
                i += 2
                continue
            if c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise Unparseable("unterminated single quote")
                cur.append(s[i + 1:j])
                in_word = True
                i = j + 1
                continue
            if c == "$" and nxt == "'":
                i = self.ansi_quote(i + 2, cur)
                in_word = True
                continue
            if c == "$" and nxt == '"':
                i += 1
                continue
            if c == '"':
                i = self.double_quote(i + 1, cur)
                in_word = True
                continue
            if c == "$" and nxt == "(":
                i = self.substitution(i + 2)
                cur.append(SUBSTITUTED)
                in_word = True
                continue
            if c == "$" and nxt == "{":
                j = self.brace_end(i + 2)
                cur.append(s[i:j])
                in_word = True
                i = j
                continue
            if c == "`":
                i = self.backtick(i + 1)
                cur.append(SUBSTITUTED)
                in_word = True
                continue
            if c in "<>" and nxt == "(":
                i = self.substitution(i + 2)
                cur.append(SUBSTITUTED)
                in_word = True
                continue
            if c == "#" and not in_word:
                j = s.find("\n", i)
                i = n if j < 0 else j
                continue
            if c == "\n":
                end_statement()
                i += 1
                if pending:
                    i = self.bodies(i, pending)
                    pending = []
                continue
            if c in " \t\r":
                end_word()
                i += 1
                continue
            if c == "<" and s.startswith("<<", i) and not s.startswith("<<<", i):
                end_word()
                i = self.heredoc_head(i + 2, pending)
                continue
            if c in "<>" or (c == "&" and nxt == ">"):
                if in_word and "".join(cur).isdigit():
                    cur = []
                    in_word = False
                else:
                    end_word()
                i += 1
                while i < n and s[i] in "<>&|":
                    i += 1
                drop_next = True
                continue
            if c == ")" and closer == ")" and paren == 0:
                end_statement()
                return i + 1
            if c in ";&|()":
                if c == "(":
                    paren += 1
                elif c == ")":
                    paren = max(0, paren - 1)
                end_statement()
                i += 1
                continue
            cur.append(c)
            in_word = True
            i += 1
        if closer is not None:
            raise Unparseable("unterminated $( )")
        end_statement()
        return n

    def ansi_quote(self, i: int, cur: list[str]) -> int:
        s, n = self.s, len(self.s)
        while i < n:
            c = s[i]
            if c == "\\" and i + 1 < n:
                cur.append(ANSI_ESCAPES.get(s[i + 1], s[i + 1]))
                i += 2
                continue
            if c == "'":
                return i + 1
            cur.append(c)
            i += 1
        raise Unparseable("unterminated $' quote")

    def double_quote(self, i: int, cur: list[str]) -> int:
        s, n = self.s, len(self.s)
        while i < n:
            c = s[i]
            nxt = s[i + 1] if i + 1 < n else ""
            if c == "\\":
                if nxt in ('$', '`', '"', "\\"):
                    cur.append(nxt)
                elif nxt != "\n":
                    cur.append(c + nxt)
                i += 2
                continue
            if c == '"':
                return i + 1
            if c == "$" and nxt == "(":
                i = self.substitution(i + 2)
                cur.append(SUBSTITUTED)
                continue
            if c == "$" and nxt == "{":
                j = self.brace_end(i + 2)
                cur.append(s[i:j])
                i = j
                continue
            if c == "`":
                i = self.backtick(i + 1)
                cur.append(SUBSTITUTED)
                continue
            cur.append(c)
            i += 1
        raise Unparseable("unterminated double quote")

    def substitution(self, i: int) -> int:
        """Body of $( ) / <( ) / >( ) starting at i, lexed in place; returns the index past `)`."""
        if self.depth + 1 > MAX_DEPTH:
            raise Unparseable("substitutions nested too deep")
        self.depth += 1
        try:
            return self.lex(i, ")")
        finally:
            self.depth -= 1

    def backtick(self, i: int) -> int:
        s, n = self.s, len(self.s)
        j = i
        while j < n:
            if s[j] == "\\":
                j += 2
                continue
            if s[j] == "`":
                body = re.sub(r"\\([`$\\])", r"\1", s[i:j])
                self.nested(body)
                return j + 1
            j += 1
        raise Unparseable("unterminated backtick")

    def brace_end(self, i: int) -> int:
        """Index just past the `}` closing a ${ } expansion that starts at i."""
        s, n = self.s, len(self.s)
        depth = 1
        while i < n:
            c = s[i]
            if c == "\\":
                i += 2
                continue
            if c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise Unparseable("unterminated single quote in ${ }")
                i = j + 1
                continue
            if c == '"':
                i = self.double_quote(i + 1, [])
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise Unparseable("unterminated ${ }")

    def heredoc_head(self, i: int, pending: list[tuple[str, bool, bool]]) -> int:
        """Parse the delimiter after `<<` / `<<-`; queue the body for the next newline."""
        s, n = self.s, len(self.s)
        strip_tabs = i < n and s[i] == "-"
        if strip_tabs:
            i += 1
        while i < n and s[i] in " \t":
            i += 1
        delim: list[str] = []
        quoted = False
        while i < n and s[i] not in " \t\n;&|()<>":
            c = s[i]
            if c in "'\"":
                j = s.find(c, i + 1)
                if j < 0:
                    raise Unparseable("unterminated heredoc delimiter quote")
                delim.append(s[i + 1:j])
                quoted = True
                i = j + 1
                continue
            if c == "\\" and i + 1 < n:
                delim.append(s[i + 1])
                quoted = True
                i += 2
                continue
            delim.append(c)
            i += 1
        if not delim:
            raise Unparseable("heredoc with no delimiter")
        pending.append(("".join(delim), strip_tabs, quoted))
        return i

    def bodies(self, i: int, pending: list[tuple[str, bool, bool]]) -> int:
        """Skip the heredoc bodies starting at i; scan the unquoted ones for substitutions."""
        s, n = self.s, len(self.s)
        for delim, strip_tabs, quoted in pending:
            body: list[str] = []
            while i < n:
                end = s.find("\n", i)
                end = n if end < 0 else end
                line = s[i:end]
                i = end + 1
                if (line.lstrip("\t") if strip_tabs else line) == delim:
                    break
                body.append(line)
            if not quoted:
                self.expanded_body("\n".join(body))
        return min(i, n)

    def expanded_body(self, body: str) -> None:
        """An unquoted heredoc body is data, but bash runs its $( ) and backticks."""
        if self.depth + 1 > MAX_DEPTH:
            return
        sub = Lexer(body, self.depth + 1)
        i, n = 0, len(body)
        try:
            while i < n:
                c = body[i]
                if c == "\\":
                    i += 2
                elif c == "$" and body.startswith("$(", i):
                    i = sub.lex(i + 2, ")")
                elif c == "`":
                    i = sub.backtick(i + 1)
                else:
                    i += 1
        except Unparseable as exc:
            log.debug("expanded_body: unparseable substitution: %s", exc)
        self.statements.extend(sub.statements)


def head_index(words: list[str]) -> int | None:
    """Index of the word the shell runs, stepping over assignments, reserved words and wrappers."""
    k = 0
    while k < len(words):
        raw = words[k]
        if ASSIGNMENT.match(raw):
            k += 1
            continue
        verb = verb_word(raw)
        if verb in ("for", "select"):
            k += 2
            if k < len(words) and words[k] == "in":
                k += 1
            continue
        if verb in RESERVED:
            k += 1
            continue
        if verb in WRAPPERS:
            k += 1
            while k < len(words) and words[k].startswith("-") and words[k] != "-":
                option = words[k]
                k += 1
                if option in WRAPPER_VALUE_FLAGS and k < len(words):
                    k += 1
            if verb == "timeout" and k < len(words) and TIMEOUT_DURATION.match(words[k]):
                k += 1
            continue
        return k
    return None


def verb_word(raw: str) -> str:
    return raw.rsplit("/", 1)[-1]


def split_flag(arg: str, value_flags: set[str], args: list[str], k: int) -> tuple[str | None, str | None, int]:
    """(flag, value, next index) for args[k]: `--f=v`, `--f v`, `-Xv`, `-X v`, or a bare flag."""
    if arg.startswith("--") and "=" in arg:
        name, _, value = arg.partition("=")
        return name, value, k + 1
    if arg in value_flags:
        value = args[k + 1] if k + 1 < len(args) else None
        return arg, value, k + 2
    if not arg.startswith("--") and len(arg) > 2 and arg[:2] in value_flags:
        return arg[:2], arg[2:], k + 1
    return arg, None, k + 1


def gh_api_vector(args: list[str], cwd: str) -> str | None:
    endpoint = None
    method = None
    has_body = False
    fields: list[str] = []
    inputs: list[str] = []
    k = 0
    while k < len(args):
        arg = args[k]
        if not arg.startswith("-") or arg == "-":
            if endpoint is None:
                endpoint = arg
            k += 1
            continue
        name, value, k = split_flag(arg, GH_API_VALUE_FLAGS, args, k)
        if name in ("-X", "--method") and value is not None:
            method = value.upper()
        if name in GH_API_BODY_FLAGS:
            has_body = True
            if name in ("-F", "--field") and value is not None:
                fields.append(value)
            if name == "--input" and value is not None:
                inputs.append(value)
    log.debug("gh_api_vector: endpoint=%r method=%r has_body=%s", endpoint, method, has_body)
    if endpoint == "graphql":
        if any("createPullRequest" in a for a in args):
            return "gh api graphql createPullRequest"
        for field in fields:
            _, _, value = field.partition("=")
            if value.startswith("@") and value != "@-" and graphql_file_creates(value[1:], cwd):
                return "gh api graphql createPullRequest (query file)"
        for path in inputs:
            if path != "-" and graphql_file_creates(path, cwd):
                return "gh api graphql createPullRequest (--input file)"
        return None
    if endpoint is None or not PULLS_ENDPOINT.match(endpoint):
        return None
    if method == "POST" or (method is None and has_body):
        return "gh api POST pulls"
    return None


def graphql_file_creates(path: str, cwd: str) -> bool:
    full = path if os.path.isabs(path) else os.path.join(cwd, path)
    try:
        with open(full, encoding="utf-8", errors="replace") as fh:
            found = "createPullRequest" in fh.read()
    except OSError as exc:
        log.debug("graphql_file_creates: unreadable %s: %s", full, exc)
        return False
    log.debug("graphql_file_creates: %s -> %s", full, found)
    return found


def curl_vector(args: list[str]) -> str | None:
    method = None
    has_data = False
    get = False
    url = False
    k = 0
    while k < len(args):
        arg = args[k]
        if CURL_PULLS_URL.match(arg):
            url = True
        if arg in ("-G", "--get"):
            get = True
        if arg in ("-X", "--request") or arg.startswith("--request="):
            _, value, k = split_flag(arg, {"-X", "--request"}, args, k)
            method = value.upper() if value else method
            continue
        if arg.startswith("-X") and len(arg) > 2:
            method = arg[2:].upper()
        elif arg in CURL_DATA_FLAGS or arg.split("=", 1)[0] in CURL_DATA_FLAGS or arg.startswith("--data"):
            has_data = True
        elif arg.startswith("-d") and len(arg) > 2:
            has_data = True
        k += 1
    log.debug("curl_vector: url=%s method=%r has_data=%s get=%s", url, method, has_data, get)
    if not url:
        return None
    if method == "POST" or (method is None and has_data and not get):
        return "curl POST pulls"
    return None


def statement_vector(words: list[str], cwd: str, nested: list[str]) -> str | None:
    """The PR-creation vector one statement uses, or None. Code it hands to a
    child shell (`bash -c`, `eval`) is appended to `nested`."""
    k = head_index(words)
    if k is None:
        return None
    verb = verb_word(words[k])
    args = words[k + 1:]
    if verb in SHELLS:
        for j, arg in enumerate(args):
            if not arg.startswith("-"):
                break
            if DASH_C.match(arg) and j + 1 < len(args):
                nested.append(args[j + 1])
                break
        return None
    if verb == "eval":
        if args:
            nested.append(" ".join(args))
        return None
    if verb == "gh":
        if args[:2] in (["pr", "create"], ["pr", "new"]):
            return "gh pr " + args[1]
        if args[:2] == ["stack", "submit"]:
            return "gh stack submit"
        if args[:1] == ["api"]:
            return gh_api_vector(args[1:], cwd)
        return None
    if verb == "curl":
        return curl_vector(args)
    if verb == "hub" and "pull-request" in args:
        return "hub pull-request"
    return None


def command_vector(command: str, cwd: str) -> str | None:
    """The first PR-creation vector anywhere in a shell command, or None.
    Raises Unparseable when the top-level command does not balance."""
    queue = [(0, Lexer(command).run())]
    while queue:
        depth, statements = queue.pop(0)
        for words in statements:
            nested: list[str] = []
            vector = statement_vector(words, cwd, nested)
            log.debug("command_vector: %r -> %s", words, vector)
            if vector:
                return vector
            for code in nested:
                if depth + 1 > MAX_DEPTH:
                    log.debug("command_vector: depth %d exceeded, skipped %r", MAX_DEPTH, code)
                    continue
                try:
                    queue.append((depth + 1, Lexer(code, depth + 1).run()))
                except Unparseable as exc:
                    log.debug("command_vector: nested code unparseable, skipped: %s", exc)
    return None


def decide(payload: dict, environ: dict) -> dict | None:
    """The deny output for a PreToolUse payload, or None to allow."""
    tool = payload.get("tool_name") or ""
    log.debug("decide: tool=%s", tool)
    if environ.get(ENFORCEMENT_ENV, "").strip().lower() == "off":
        log.debug("decide: %s=off, standing down", ENFORCEMENT_ENV)
        return None
    vector = None
    if MCP_CREATE.match(tool):
        vector = "mcp " + tool
    elif tool in SHELL_TOOLS:
        command = (payload.get("tool_input") or {}).get("command")
        if not isinstance(command, str) or not command.strip():
            return None
        cwd = payload.get("cwd") or os.getcwd()
        try:
            vector = command_vector(command, cwd)
        except Unparseable as exc:
            log.debug("decide: unparseable command, allowed: %s", exc)
            return None
    log.debug("decide: vector=%s", vector)
    if vector is None:
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }
    }


def main() -> int:
    logging.basicConfig(level=logging.DEBUG if os.environ.get(DEBUG_ENV) == "1" else logging.WARNING,
                        format="%(name)s: %(message)s", stream=sys.stderr)
    payload = json.load(sys.stdin)
    decision = decide(payload, dict(os.environ))
    if decision is not None:
        json.dump(decision, sys.stdout)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
