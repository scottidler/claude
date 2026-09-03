---
name: thorough-review
description: Run a repo-wide code review whose completeness is proven, not asserted. Every tracked file is assigned to exactly one reviewer by explicit file list, every reviewer returns a per-file coverage table, a coverage check gates the result, and the mechanical classes (dead code, duplicate functions, unused deps, suppressions, broken doc links, stale paths, docs naming symbols that do not exist) come from a census script that is complete by construction. Findings are split by a stated severity floor into bugs (each with an observed repro) and a hygiene ledger. Use whenever the user asks for a thorough, complete, full, or repo-wide review, a code review remediation pass, "find everything wrong", "review the whole repo", or complains that a previous review missed things or keeps producing new lists. Not for reviewing one PR or diff; use code-review for that.
---

# Thorough review

Scott's word "thorough" means the complete list. A review that fans out reviewers by area and returns whatever they noticed is a sample, and samples refill: three passes on `otto` each produced a full-size list, and the third found a file dead since 2022 that eight reviewers in the first pass never mentioned. This skill replaces attention with enumeration wherever a class of finding can be enumerated, and demands proof of coverage wherever it cannot.

Two guarantees, and the review is not done until both hold:

1. **Census classes are complete.** Dead code candidates, duplicate functions, suppressions, unused dependencies, compiler and rustdoc warnings, broken doc links, stale paths, and doc tokens with no source hit come from `bin/census`, which walks every tracked file. Reviewers confirm rows; they never produce these lists by hand.
2. **Judgment classes have proven coverage.** Wrong logic, lying comments, two paths for one behavior, silent failure: no script finds these. So every tracked file is assigned to exactly one reviewer by explicit list (`bin/partition`), every reviewer returns a coverage row for every assigned file including zero-finding files, and `bin/coverage` fails the review while any file is unclaimed.

Scripts live in `~/.claude/skills/thorough-review/bin/`. The reviewer prompt is `prompt.md` beside this file.

## Inputs to settle before starting

- **Repo and commit.** Record `git rev-parse --short HEAD`; every location in the output is anchored to it.
- **Severity floor.** Default: "a user of the tool can observe the wrong behavior from the command line or in a file the tool writes." Anything else is hygiene. State the floor in the output; the user can move it.
- **Prior deferred list.** Open questions, deferred items, and "not this doc's" notes from the previous review or remediation doc in `docs/design/`. Hand them to every reviewer so they are not re-raised as new. If there is no prior review, say so.
- **Where outputs go.** Census and reports go to the scratchpad, never into the reviewed tree. The two deliverables (below) go to `docs/design/` only when the user wants them in the repo.
- **Cargo contention.** If another agent is building in the same tree, run census with `--no-cargo` and note that warnings.txt is empty because of it. Do not compete for the target-dir lock.

## Procedure

### 1. Census

```
~/.claude/skills/thorough-review/bin/census --repo <repo> --out <scratch>/census [--no-cargo]
```

Read `summary.md`. Every non-empty census file is part of the deliverable verbatim; candidates (marked in each file's header) need one confirmation each from the reviewer who owns the file. Keep the census directory: it is the proof.

### 2. Partition

```
~/.claude/skills/thorough-review/bin/partition <scratch>/census --max-lines 6000
```

Read `partition/index.md`. Adjust `--max-lines` so each reviewer's assignment is one a single agent can read in full; a 6000-line assignment is the ceiling, not a target. Files of kind `other` are excluded by default; look at what landed there in `manifest.tsv` and pull anything reviewable back in with `--kinds`.

### 3. Dispatch

One subagent per `partition/NN.tsv`, in parallel, using `prompt.md` with every placeholder filled:

- `{{FILES}}`: the `path` column of that partition file, one per line.
- `{{FLOOR}}`: the severity floor sentence.
- `{{PRIOR}}`: the prior deferred list, or "none".
- `{{CENSUS_DIR}}`, `{{REPO}}`, `{{COMMIT}}`.

Model: the strongest available for `src` and `test` partitions; a doc-only partition can go to a cheaper model. Save each returned report verbatim as `<scratch>/reports/NN.md`.

### 4. Coverage gate

```
~/.claude/skills/thorough-review/bin/coverage <scratch>/census <scratch>/reports/*.md
```

Exit 1 means uncovered files. Re-dispatch exactly those files (a new partition file, a new reviewer, same prompt) and re-run. Do not write findings while coverage is incomplete. Also read the `unknown` section: a path a reviewer claims that is not in the manifest is a typo or a file outside the tree, and its real file may be uncovered.

### 5. Systemic pass

One agent reads all reports and `summary.md`, not the code, looking only for altitude 2 and 3 patterns that span reviewers: the same rule enforced in one file and not another, two implementations of one behavior found by different reviewers, a boundary bug reported from both sides. It returns findings in the same shape, each citing the report numbers it merged. This pass cannot add findings without a location from some report.

### 6. Merge

Apply, in order:

- Drop nothing silently. A finding a reviewer made that you disagree with is kept with your one-line rebuttal under it.
- Mark any finding matching the prior deferred list as `previously deferred`, never as new.
- Collapse duplicates across reports into one finding naming every site.
- Split by the floor. Bugs need an `observed:` line; a bug without one is moved to Questions, not promoted on trust.

## Deliverables

Two documents, always both, so the hygiene tail never becomes a phase list again.

**Findings** (`docs/design/YYYY-MM-DD-<slug>-review.md` when the user wants it in the repo): the severity floor; every bug with its observed repro; the systemic findings; Questions; and a **Proof** section holding the census `summary.md` table, the coverage totals table from `bin/coverage`, the count of reviewers and the model each ran on, and a **Not reviewed** list that must be empty or explicit. This document is the input to `/create-design-doc` for a phased fix, and phases are built from bugs only.

**Hygiene ledger** (`docs/hygiene.md`, a standing file, appended under a dated heading, never a phased plan): every hygiene finding and every census row with its confirmation. It is worked opportunistically, one item at a time alongside other changes, and a row is removed when its fix lands. Its length is the tax a codebase of this size carries; it is not a measure of the last remediation's success.

## Hard rules for the orchestrator

- Never write "the review found N issues" without the coverage table beside it.
- Never let a reviewer pick its own files or describe its scope as an area.
- Never accept a report whose coverage table is missing rows; send it back, do not fill it in.
- Never re-run census by hand with ad hoc greps; fix the script and re-run it, so the next review inherits the fix.
- Report the tally in this order: files assigned, files covered, bugs above floor, hygiene rows, questions. The first two numbers are the claim of thoroughness; the rest are what it found.
