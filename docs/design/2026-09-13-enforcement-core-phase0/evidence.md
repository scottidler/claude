# Phase 0 evidence: enforcement-core

Run 2026-09-13 on desk.lan, Claude Code 2.1.270, from session `2b5b1727`.
Design doc: `docs/design/2026-09-13-enforcement-core.md`.

Scratch artifacts under `/tmp/claude-1000/p0/` (probe hooks, scratch `--settings` files, captured payloads).

## 0a: Stop hook fires and blocks -- PASS

Scratch Stop hook returning `{"decision":"block","reason":"probe: phase 0a stop hook block"}`
when `stop_hook_active` is false, registered via `--settings` on a nested `claude -p` run
with the prompt `Reply with exactly this and nothing else: Done. Want me to run it?`.

Two payloads captured:

1. `stop_hook_active: false`, `last_assistant_message: 'Done. Want me to run it?'` -> blocked.
2. `stop_hook_active: true`, a second assistant turn with the offer removed -> passed `{}`.

Stop payload keys (2.1.270): `background_tasks, cwd, hook_event_name, last_assistant_message,
permission_mode, prompt_id, session_crons, session_id, stop_hook_active, transcript_path`.

`last_assistant_message` is present and is a plain `str`. The transcript fallback the design
doc keeps for its absence is not needed on this version, but is retained as a guard.

There is **no prompt field** in the Stop payload. `prompt_id` is an opaque id, not the text.
The prompt must come from the transcript.

## 0a (SubagentStop): PASS

Captured from a nested session that dispatched one general-purpose subagent.

SubagentStop adds exactly the three fields the doc predicted: `agent_id`, `agent_transcript_path`,
`agent_type` (observed `general-purpose`). Same script handles both events.

## 0h: prompt extraction -- FAIL as specified, two defects

### Defect 1: `claude -p` writes no transcript

In both nested `-p` runs the payload's `transcript_path` pointed at a file that never existed,
during the hook and after the session ended:

```
transcript_path: /home/saidler/.claude/projects/-home-saidler-repos-scottidler-claude/8a5a1d24-....jsonl
exists: False
```

Same for `agent_transcript_path` on SubagentStop. So in headless/`-p` sessions the offer rule can
never fire: the prompt is unreachable. That is a fail-open, consistent with the design, but it
also means **0h cannot be proven through `claude -p`**. It was proven instead against this live
interactive session's transcript, which is written continuously (verified: file mtime tracked
wall-clock while the session ran).

### Defect 2: the doc's extraction predicate misses slash-command turns

Doc predicate (Data Model, Stop / main thread): last record with `type=="user"`, string
`message.content`, **not starting with `<`**, `isSidechain != true`.

Against this live session, whose typed prompt was
`/how-to-execute-a-plan docs/design/2026-09-13-enforcement-core.md`:

```
all user recs: 16
  [0] str  '<command-message>how-to-execute-a-plan</command-message>\n<command-name>/how-to-execute-a-plan</command-name>...'
  [1] list ['text']  (the expanded skill body)
  [2..15] list ['tool_result']
doc-predicate main-thread user recs: 0
```

The typed prompt is wrapped in `<command-message>`, so the `not starting with '<'` clause
discards it. **Every `/skill` turn extracts no prompt and the offer rule silently never fires.**

Against a prior normal session (`0aa23bbf`, 1466 records) the predicate works: 42 main-thread
user records, last one `'where is the note that we are working on the entire list of items in
design doc chunks?'`, which is the prompt actually typed.

### A better source exists: `last-prompt` records

The transcript carries a dedicated record type the doc does not use:

```json
{"type":"last-prompt","lastPrompt":"/how-to-execute-a-plan docs/design/2026-09-13-enforcement-core.md",
 "leafUuid":"31a31625-...","sessionId":"2b5b1727-..."}
```

It carries the verbatim typed prompt **including slash commands**. Caveats measured on the prior
session: it also records agent-injected messages (`Another Claude session sent a message: ...`),
and its newest entry lagged the newest typed prompt by one turn in that file. So it is a better
primary with the user-record scan as the cross-check, not a drop-in replacement.

## 0b: PreToolUse regex matchers -- PASS

Scratch settings with `"matcher": "Write|Edit|MultiEdit|NotebookEdit"` and a separate
`"matcher": "mcp__slack__chat_post_message"`. Nested session told to Write, then Edit, then Read
one file.

```
PRE tool_name= Write
PRE tool_name= Edit
```

Read is absent, as required. Payload carries `tool_name` and `tool_input`. The regex matcher form
is honored, so the single registration in the design's API Design section stands (no need for the
one-registration-per-tool fallback in the risk table).

The MCP matcher was not exercised (no Slack post issued from the scratch session); the regex form
itself is proven by the Write/Edit arm.

## 0e: TMPDIR -- PASS, and the fix is confirmed necessary

- Unsandboxed in this session today: `TMPDIR=[]` (empty). This is the `"$TMPDIR/ci.log"` -> `/ci.log`
  bug, reproduced.
- With `"env": {"TMPDIR": "/tmp/claude-1000"}` in the scratch settings, a command running
  **outside** the sandbox printed `TMPDIR=[/tmp/claude-1000]`.
- Sandboxed value is unchanged (`/tmp/claude-1000`) either way.

The `env.TMPDIR` entry in Phase 1 is correct and does what the doc says.

## 0f: sccache over a unix socket -- FAIL. Root cause found.

`SCCACHE_SERVER_UDS` is a supported env var in the installed sccache 0.10.0 (present in the
binary's string table). A host-side UDS server started and served `--show-stats` from outside
the sandbox.

From **inside** the sandbox, against that live socket:

```
[TRACE sccache::commands] connect_or_start_server(/home/saidler/.cache/sccache-uds/server.sock)
[TRACE sccache::client]   connect_to_server(/home/saidler/.cache/sccache-uds/server.sock)
sccache: error: Operation not permitted (os error 1)
```

Isolated to the syscall:

```python
socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
# PermissionError: [Errno 1] Operation not permitted
```

**The sandbox denies `socket(AF_UNIX, ...)` creation outright** -- it fails before any `connect()`,
so no filesystem allowlist entry can fix it. The same EPERM applies to `$SSH_AUTH_SOCK`.

Consequence: the Phase 0f unix-socket remedy is dead. The doc's recorded fallback applies --
`"RUSTC_WRAPPER": ""` in settings `env`, losing the cache for sandboxed cargo runs while the
excluded (unsandboxed) ones keep using the host server.

## 0f corollary: Phase 1's commit-signing fix as written cannot make AC1 pass

Because AF_UNIX is denied, ssh-agent is unreachable inside the sandbox, so `ssh-keygen -Y sign`
must fall back to reading the private key file. Measured with a throwaway key under `$TMPDIR`:

```
# private key readable, agent disabled:
$ SSH_AUTH_SOCK= ssh-keygen -Y sign -f ./k.pub -n git msg
Signing file msg          <- succeeds

# private half moved away, same command:
$ SSH_AUTH_SOCK= ssh-keygen -Y sign -f ./k.pub -n git msg
No private key found for public key "./k.pub"     <- fails
```

The design doc's Phase 1 entry adds **only** the `.pub` halves to `sandbox.filesystem.allowRead`
and states "private keys stay denied". With `~/.ssh` in the sandbox read-deny list and no agent,
that combination cannot produce a signature. AC1 fails as specified.

### Which key is which (the measurement that ruled out option A)

Verified 2026-09-13 by blob-hash match against `github.com/<user>.keys`,
`api.github.com/users/<user>/ssh_signing_keys`, `~/.ssh/config`, `~/.gitconfig-ssh` and desk.lan's
`authorized_keys`. No private key file was opened.

| key | GitHub auth key? | GitHub signing key? | other use |
|---|---|---|---|
| `~/.ssh/identities/work/signing` | no, absent from escote-tatari's auth keys | yes, escote-tatari | none; passphrase-less by design per `~/.gitconfig-work:5-8` |
| `~/.ssh/identities/home/id_ed25519` | **yes, scottidler's only one** | yes, scottidler | `IdentityFile` for `github.com`, `desk.ts`, `nas.lan`, `*.lan` (`ForwardAgent yes`), `nixos`; present in desk.lan `authorized_keys`; `HOME_KEY` in `~/.gitconfig-ssh` |

`home/id_ed25519` is 399 bytes, matching an unencrypted ed25519; the passphrase-locked work
`id_ed25519` is 464 bytes for the same key type. So no passphrase gates it (inferred from size,
not from reading the file).

The two personas are not symmetric: work received a signing/auth split on 2026-07-16, home never
did. Adding `home/id_ed25519` to `allowRead` would hand push-as-scottidler and LAN ssh to every
sandboxed subprocess, which is why option A was rejected.

Escalated to Scott, who ruled **option D** on 2026-09-13: mint a home signing-only key so that
both allowRead'd private keys are signing-only. See `Resolved Decisions` in the design doc.

## 0g: excludedCommands matching semantics -- ANY STAGE, whole compound exempted (the prefix reading was wrong)

Attempted in a nested session with three pattern forms
(`/tmp/.../m1.sh *`, `/tmp/.../m2.sh`, `m3.sh *`). All three ran **sandboxed**, and one run
reported `Sandbox is enabled but failed to initialize: EPERM ... listen '/tmp/claude-1000/srt-mux-9-1.sock'`.
Nested sandboxes do not initialize reliably, so the negative result is not evidence about the
pattern form.

Positive control in this (non-nested) session, where `cargo *` is a real `excludedCommands` entry:

```
$ cargo --version >/dev/null 2>&1; python3 -c "<AF_UNIX socket test>"
after-cargo-head: UNSANDBOXED
```

So `excludedCommands` works and carries the whole compound command out of the sandbox.

**CORRECTION, 2026-09-13, after Phase 1 landed.** This section originally concluded that matching
is on the command **string prefix**. That is WRONG. `excludedCommands` matches **any stage
anywhere** in a compound and exempts the ENTIRE compound. Measured in a live session with the
AF_UNIX marker, which is decisive because position does not matter:

```
$TMPDIR/marker.sh                          -> SANDBOXED
ssh -V 2>/dev/null; $TMPDIR/marker.sh      -> UNSANDBOXED   (excluded stage LEADING)
$TMPDIR/marker.sh; ssh -V 2>/dev/null      -> UNSANDBOXED   (excluded stage TRAILING)
$TMPDIR/marker.sh; cargo --version         -> UNSANDBOXED   (pre-existing entry, same)
```

The trailing case rules out prefix matching. The original conclusion was drawn from a single
`cargo`-headed compound, which is consistent with BOTH readings; the trailing test is the one that
separates them, and it was not run until after Phase 1 had already shipped the wider list.

Consequence: **every `excludedCommands` entry is a general sandbox-escape hatch.** Appending
`; ssh -V` to any command runs that command fully outside the sandbox with no approval prompt.
Phase 1 grew the list from 3 entries to 10, so it widened that surface from 3 hatches to 10 while
fixing the tool failures audit item 1 counted. Under review; see the design doc's Open Questions.

The absolute-path-head question is now moot for the reviewer scripts: since any stage matches,
a script path entry exempts any compound that mentions it.

Note: an earlier 0g attempt used `curl https://generativelanguage.googleapis.com/` as the
discriminator and returned HTTP 404 both inside and outside the sandbox -- that host is reachable
through the egress proxy regardless, so it is not a sandbox marker. The AF_UNIX socket test is.

## 0c: rails deny -- SUPERSEDED

The throwaway probe was never run: nested sessions are not a reliable harness (see 0g). It is now
moot. The rule under test is the real excluded-compound deny added to Phase 5 under OQ3, and its
live check (`$TMPDIR/marker.sh; ssh -V` denied, in main and in a subagent) is a Phase 6 criterion.

## 0d: sandbox edits apply live -- NOT RUN

Blocked on the same decision as the 0f corollary: it requires editing
`HOME/.claude/settings.json`, which the design doc's operator note (b) says must run with auto
mode off. Two auto-mode classifier denials were hit during Phase 0
(`[Credential Exploration]` on an `ls ~/.ssh/identities/...`, `[Create Unsafe Agents]` on
`--dangerously-skip-permissions`), confirming the note.

## Summary

| Spike | Result |
|---|---|
| 0a Stop fires and blocks | PASS |
| 0a SubagentStop payload | PASS (`agent_id`, `agent_transcript_path`, `agent_type`) |
| 0b PreToolUse regex matcher | PASS |
| 0c rails deny | not run |
| 0d sandbox live-apply | not run (needs auto mode off) |
| 0e TMPDIR | PASS, fix confirmed necessary |
| 0f sccache over UDS | FAIL -- sandbox denies `socket(AF_UNIX)`; fallback `RUSTC_WRAPPER=""` applies |
| 0f corollary | Phase 1 signing fix insufficient; needs private key readable or another route |
| 0g excludedCommands semantics | ANY-STAGE matching, whole compound exempted; path-head form moot; the mixed-compound deny is assigned to rails (Phase 5, absorbing spike 0c) |
| 0h prompt extraction | FAIL -- predicate misses slash-command turns; `last-prompt` records are the better source |
