# Implementation notes: session recall

Append-only. Design doc: `docs/design/2026-09-17-session-recall.md`.

## Phase 0: prove the injection survives

### Design decisions
- **One throwaway hook serves all four probes** (`2026-09-17-session-recall-phase0/spike-hook.sh`):
  it logs the raw payload unconditionally as its first act, then runs the predicate. Probe 3
  needs the payload and no fire; probes 1 and 2 need the fire; probe 4 needs the keys. Logging
  before the bails means one registration covers all of them, and a bailed prompt still leaves
  a payload record.
- **The spike hook implements the doc's bails and both trigger arms**, not just a constant
  emitter. A constant emitter would have tested the injection but not the quoting, and the
  quoting is what makes the id arm corroborated. Cost: a `grep -oP` for the lookaround regex,
  which is the same engine Phase 2 will need in bash.
- **Probes ran as `claude -p` with `--output-format stream-json --verbose`**, not plain `-p`.
  Plain `-p` returns only the final text; the tool-call trace is what makes the retrieval
  attributable to the injected line rather than to the prompt. The first `-p` run is still
  recorded because it is what proved project-local hooks fire headlessly.
- **`--allowedTools` granted only the five read-only clyde retrieval tools plus `ToolSearch`.**
  An attempt blocked on permissions would have been indistinguishable from a refusal at the
  signal the phase reads.
- **The interactive-TUI half of probe 3 is answered from the live `inline-skill-tokens.py` log,
  not from the spike.** A headless `-p` run cannot settle what the TUI submits, and
  `~/.cache/claude/inline-skill-tokens.log` already records the live payload's `prompt` for 31
  slash-command prompts typed in the TUI, including the one that launched this phase. Reading
  an existing measurement beats inventing an unfalsifiable one.
- **The scratch project lives under `$TMPDIR`, and its two files are copied into the phase0
  directory as the record.** Precedent: `2026-09-17-dm-resolution-and-pipeline-glue-phase0/`
  commits its driver scripts. The copies are mode 644 and registered nowhere.

### Deviations
- **Probe 2's verbatim response contains one em-dash (U+2014) and it is preserved.** The
  brief said no em-dashes anywhere; an evidence file's deliverable is verbatim fidelity, and
  editing a quoted model response is the one edit it may not make. Not a CI failure:
  `.otto.yml`'s em-dash `FILES` list is enumerated and does not name this file, and `otto ci`
  exits 0 with it present. Flagged at the top of `evidence.md` and again under Open questions,
  because Phase 2 adding this file to that list would turn it into one.
- **Probe 2's prompt is self-evidently a recall ask**, so it does not isolate the injected
  line as the cause of the retrieval. The doc fixes the signal as refusal versus no-refusal,
  which the probe does measure, and the `select:`-list fingerprint in the first tool call
  gives partial attribution. Stated in `evidence.md` under "The confound" rather than glossed.
- **Probe 3 ran three slash commands, not one** (`/doctor`, a nonexistent command, and
  `/doctor` with arguments). The doc asked for one. The argument-carrying form is the shape of
  the `<command-args>` record the round-3 carve-out branch hinged on, so measuring it without
  arguments would have left the branch half-tested.
- **The child `claude -p` processes could not write their own transcripts**: the Bash sandbox
  denies writes under `~/.claude/projects`, so the `transcript_path` in each payload does not
  exist on disk. Irrelevant to the verdicts (the stream-json stdout is the record) and noted
  so a reader does not go looking for those files.

### Tradeoffs
- **A throwaway bash hook rather than a first draft of `session-recall-guard.sh`.** Writing
  the production hook here would have been faster for Phase 2 and would have broken the
  phase's own rule that no production file is written, and would have made "is the spike the
  thing under test" ambiguous. Phase 2 starts clean from the doc.
- **No regression matrix for the spike predicate**, only the four smoke payloads recorded in
  `evidence.md`. The ten-fixture matrix is Phase 2's deliverable against the production hook;
  building it twice against a throwaway would be work thrown away with it.
- **Granted live clyde tool access instead of stubbing retrieval.** A stub would have made the
  runs cheaper and would have removed the only evidence that the injected tool names resolve
  to callable tools at all.

### Open questions
- **Does this evidence file belong in `.otto.yml`'s em-dash `FILES` list, given the preserved
  em-dash in probe 2's quote?** Phase 2 owns that registration. Three options, none picked
  here: leave the file out of the list (current state, CI green); add the file and replace the
  character in the quote with a marker (breaks verbatim); add the file and narrow the lint to
  skip fenced blocks (touches the gate for one character). Scott's call.
- **Bail 2's class was not observed in the live hook log.** 0 of 246 entries over 16 hours
  begin `Another Claude session sent a message:`. The doc's 2,351 corpus records stand, and
  the live-payload form of that prefix is unmeasured. Phase 2's replay reads the corpus, so
  this does not block it; it does mean bail 2 is the one bail with no live-payload confirmation.

## Phase 1: the `session-recall` skill

### Design decisions
- **`HOME/.claude/skills/session-recall/SKILL.md`, structure copied line-for-line from
  `vault-recall/SKILL.md`**: frontmatter `name` + `description`, H1, one-paragraph why,
  `## Steps` as numbered imperatives, `## Rules` as bullets. No new section shape invented.
- **The five required tools (`sessions_search`, `sessions_ls`, `session_open`, `session_grep`,
  `session_read`) and their required params were cross-checked against clyde source**, not
  taken from the design doc's table on faith: `tatari-tv/clyde/sessions/src/mcp/tools.rs`
  (`SessionsSearchRequest`, `SessionsLsRequest`, `SessionRef`, `SessionGrepRequest`,
  `SessionReadRequest`) and the dispatch match arms + tool-name literals in
  `tatari-tv/clyde/sessions/src/mcp.rs:68-89`. Every tool name, required field, and optional
  field in the doc's table matches the source exactly; no disagreement to resolve.
- **`session_efficiency` is omitted from Steps** per the doc's floor ("at least the five
  retrieval tools... `session_efficiency` is not required"). It is not mentioned anywhere in
  the skill, matching the doc's framing that it is a behavior-signal tool, not a retrieval one.
- **The CLI fallback step names only the three tools that have one** (`clyde session search`,
  `clyde session ls`, `clyde session resume`), confirmed live via `clyde session --help` and
  `clyde efficiency --help` on PATH. `session_grep` and `session_read` have no CLI equivalent
  per the doc's table (blank CLI column); the skill states that explicitly rather than
  silently omitting a fallback for them.
- **No new symlink or `manifest -l` needed.** `HOME/.claude/skills` is linked wholesale:
  `~/.claude/skills -> .../HOME/.claude/skills` (a single directory symlink, confirmed with
  `readlink ~/.claude/skills`), unlike `~/.claude/hooks`, which is 36 per-file symlinks (Phase
  2's problem, not this one). The new `session-recall/` directory appeared live at
  `~/.claude/skills/session-recall/SKILL.md` on write, no extra step run.

### Deviations
- None. The skill matches the doc's Phase 1 bullet and the six-tool table verbatim; the
  schema cross-check against clyde source agreed with the doc's table in every field.

### Tradeoffs
- **Trigger phrases in the description are copied from the doc's enumerated phrase-arm list**
  (`the session where`, `that doc/design/spec we wrote/made/did`, `previous/last/prior session`)
  rather than paraphrased, so the skill's own trigger surface stays traceable to the same
  enumeration Phase 2's hook will implement, even though Phase 0 found both arms survive and
  nothing here depends on that verdict.
- **Rules section keeps the naming-trap list as prose bullets, not a table**, matching
  `vault-recall`'s bullet-only `## Rules` shape rather than importing the doc's markdown table.
  The table's content survives; the format follows the sibling skill, not the doc.

### Open questions
None.
