#!/usr/bin/env python3
"""
discover.py — walk a subcommand-style CLI's --help tree, collect every leaf
method token, and classify each as readonly / mutating / ambiguous.

Emits candidate `permissions.allow` rules for the readonly (and, if asked,
ambiguous) tokens so `allow-readonly` can merge them into settings.json.

The classification is verb-based: for CLIs shaped like
`<cli> <group> <resource> [sub] <method> [flags]` (gws, gcloud, kubectl-style,
most clap/cobra apps), whether a command mutates is decided by the FINAL token.
That lets one rule (`Bash(<cli> * <verb>:*)`) cover the verb across every
group/resource, instead of enumerating hundreds of full paths.

Usage:
    discover.py <cli> [--seed "grp1 grp2 ..."] [--depth N]
                      [--help-flag --help] [--include-ambiguous]
                      [--rules-only | --json]

--seed is needed only when `<cli> --help` does NOT print a parseable command
list (e.g. gws prints a "SERVICES:" blurb + JSON errors). Pass the top-level
groups explicitly, e.g.:
    discover.py gws --seed "drive sheets gmail calendar docs slides tasks \
        people chat classroom forms keep meet admin-reports"
"""
import argparse
import json
import re
import subprocess
import sys

# --- verb tables -------------------------------------------------------------
# A token is readonly if it starts with a READONLY root and does NOT start with
# a MUTATING root (mutating wins ties: "setDefault" -> set -> mutating).
# A leading "batch" is stripped and the remainder reclassified
# ("batchGet" -> get -> readonly; "batchUpdate" -> update -> mutating).

READONLY_ROOTS = [
    "get", "list", "search", "find", "download", "export", "query",
    "describe", "show", "view", "read", "fetch", "aggregat", "lookup",
    "preview", "inspect", "status", "info", "history", "count", "print",
    "cat", "dump", "tail", "logs", "log", "diff", "ls", "browse", "stat",
    "resolve-refs", "schema", "explain", "tree", "check", "probe", "ping",
    "whoami", "current", "exists", "summar",
]

MUTATING_ROOTS = [
    "create", "update", "delete", "patch", "put", "post", "set", "add",
    "remove", "insert", "modify", "copy", "move", "rename", "upload", "send",
    "empty", "generate", "clear", "append", "write", "edit", "enable",
    "disable", "start", "stop", "restart", "revoke", "grant", "trash",
    "untrash", "star", "unstar", "import", "sync", "run", "exec", "apply",
    "merge", "reset", "revert", "subscribe", "unsubscribe", "watch",
    "acknowledge", "accept", "decline", "approve", "reject", "cancel",
    "hide", "unhide", "obliterate", "transfer", "reactivate", "reclaim",
    "reassign", "renew", "verify", "comment", "turnin", "complete",
    "quickadd", "markas", "install", "uninstall", "deploy", "provision",
    "destroy", "kill", "purge", "rollback", "promote", "publish",
]

# Section headers under which CLIs list their subcommands (clap, cobra, click,
# argparse, docopt, and gws's "SERVICES:").
SECTION_RE = re.compile(
    r"^\s*(commands|available commands|subcommands|services|resources|"
    r"management commands|core commands|additional commands|options commands)"
    r"\s*:?\s*$",
    re.IGNORECASE,
)


def strip_batch(t):
    return t[5:] if t.startswith("batch") else t


def classify(token):
    t = token.lower()
    core = strip_batch(t)
    for r in MUTATING_ROOTS:
        if core.startswith(r):
            return "mutating"
    for r in READONLY_ROOTS:
        if core.startswith(r):
            return "readonly"
    return "ambiguous"


def run_help(argv):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=25)
        return (r.stdout or "") + "\n" + (r.stderr or "")
    except Exception:
        return ""


def parse_subcommands(text):
    """Pull subcommand names out of any recognized command-list section.

    Subcommand lines are indented `  name   description...`; the section ends
    at the next unindented line or blank gap after entries."""
    out = []
    lines = text.splitlines()
    in_section = False
    seen_entry = False
    for ln in lines:
        if SECTION_RE.match(ln):
            in_section = True
            seen_entry = False
            continue
        if not in_section:
            continue
        if ln.strip() == "":
            if seen_entry:
                break  # blank line after entries closes the section
            continue
        if re.match(r"^\S", ln):
            break  # dedent closes the section
        m = re.match(r"^\s{2,}([A-Za-z0-9][\w:+.-]*)\b", ln)
        if m:
            out.append(m.group(1))
            seen_entry = True
    # drop noise / non-methods
    return [
        s for s in out
        if s not in ("help", "completion", "version")
        and not s.startswith("+")
        and not s.startswith("-")
    ]


def walk(cli, help_flag, seed, max_depth):
    leaves = {}   # token -> [example full paths]
    visited = set()

    def rec(path, depth):
        key = tuple(path)
        if key in visited or depth > max_depth:
            return
        visited.add(key)
        subs = parse_subcommands(run_help([cli, *path, help_flag]))
        if not subs:
            if path:
                leaves.setdefault(path[-1], []).append(" ".join(path))
            return
        for s in subs:
            rec(path + [s], depth + 1)

    roots = seed if seed else parse_subcommands(run_help([cli, help_flag]))
    if not roots:
        sys.exit(
            f"error: could not parse any subcommands from `{cli} {help_flag}`.\n"
            f"Pass the top-level groups explicitly with --seed \"grp1 grp2 ...\"."
        )
    for r in roots:
        rec([r], 1)
    return leaves


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cli")
    ap.add_argument("--seed", default="")
    ap.add_argument("--depth", type=int, default=5)
    ap.add_argument("--help-flag", default="--help")
    ap.add_argument("--include-ambiguous", action="store_true")
    ap.add_argument("--rules-only", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    seed = args.seed.split() if args.seed else None
    leaves = walk(args.cli, args.help_flag, seed, args.depth)

    buckets = {"readonly": {}, "mutating": {}, "ambiguous": {}}
    for tok, paths in leaves.items():
        buckets[classify(tok)][tok] = paths

    ro = sorted(buckets["readonly"])
    amb = sorted(buckets["ambiguous"])
    rule_tokens = ro + (amb if args.include_ambiguous else [])
    rules = [f"Bash({args.cli} * {t}:*)" for t in rule_tokens]

    if args.json:
        print(json.dumps({
            "cli": args.cli,
            "readonly": {t: buckets["readonly"][t] for t in ro},
            "ambiguous": {t: buckets["ambiguous"][t] for t in amb},
            "mutating": sorted(buckets["mutating"]),
            "rules": rules,
        }, indent=2))
        return

    if args.rules_only:
        print("\n".join(rules))
        return

    def show(name):
        b = buckets[name]
        print(f"\n=== {name} ({len(b)}) ===")
        for t in sorted(b):
            print(f"  {t:32}  e.g. {args.cli} {b[t][0]}")

    show("readonly")
    show("ambiguous")
    show("mutating")
    print(f"\n=== candidate allow rules ({len(rules)}) ===")
    print("\n".join(rules))
    if amb and not args.include_ambiguous:
        print(f"\n# {len(amb)} ambiguous token(s) NOT included above — review with the user,")
        print(f"# then re-run with --include-ambiguous to fold in the approved ones.")


if __name__ == "__main__":
    main()
