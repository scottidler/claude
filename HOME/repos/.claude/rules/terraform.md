---
paths:
  - "**/*.tf"
  - "**/*.tf.json"
  - "**/*.tftest.hcl"
---

# Terraform Operating Rules

How to *operate* on Terraform, not how to write HCL. Mined from a real blunder:
pinning a consumer to a specific module patch as a workaround for a lagging
floating tag, and opening a public PR under the user's name to do it, when the
standard move was `terraform init -upgrade`. Do not repeat that.

## Plan is safe; apply is the mutation

- `terraform plan` is read-only (a brief state lock at most). `terraform apply` is
  the change. Never apply anything you have not first read the full plan of.
- Prefer a saved plan: `terraform plan -out=tfplan` then `terraform apply tfplan`,
  so the apply is EXACTLY the reviewed diff with no re-plan drift and no prompt.
- Read the plan's `Plan: X to add, Y to change, Z to destroy` AND every `# ...
  will be / must be replaced` line. Confirm each changed resource is one you
  intend. A "destroy"/"replace" of an IAM policy or similar is often a same-name
  recreate, not data loss — but verify, do not assume.

## Source ref changes are not live until applied

- Bumping/floating a module `source`/`?ref=`, merging a module PR, or a tag
  advancing changes the SOURCE only. The real resource (IAM role, table, ...)
  changes only when the *consuming composition* is re-applied. "The fix is merged"
  ≠ "the fix is live." Always name the apply that makes it real.

## Floating version tags lag — don't pin to route around it

- A floating major/minor alias (e.g. `?ref=v2`) trails the latest release for a
  while after a merge; a pipeline advances it later. A stale float is TRANSIENT.
- Do NOT pin a consumer to a specific patch as a workaround for a lagging float.
  The float catches up on its own, and pinning silently diverges that consumer
  from the fleet convention (the thing reviewers will call out).
- The standard move to pick up a moved floating tag is `terraform init -upgrade`,
  then apply. Reach for that first.
- Pin only for a deliberate, reviewed reason (reproducibility policy, quarantining
  a bad release) — never as an impatience hack. When unsure which the repo wants,
  ASK before changing the ref.

## Know the blast radius before applying

- Identify what the change actually touches vs. your immediate task. Account-wide
  CI/apply roles, shared state, org-wide tags/aliases affect far more than the one
  service you came for. Confirm from the plan that changes are scoped as intended.
- NEVER move/force-update a shared or org-wide tag/alias as a shortcut — that hits
  every consumer that pins it. Prefer the isolated, consumer-scoped change.
- Applies to SHARED infra should be run by the owner/operator, not freelanced.
  Set it up, show the plan, hand over the apply — do not auto-run it.

## Don't take public action to route around a transient condition

- Opening a PR, posting a comment, forcing a tag, or re-running a pipeline in a
  shared org repo happens under the USER's name and is visible to their team. A
  wrong one embarrasses them, not you.
- Before any such action to work around a state you dislike, confirm the state is
  NOT self-resolving (a lagging tag, a not-yet-run pipeline, an in-flight release
  usually is). Re-check current reality first — tags and pipelines move.
- When you don't know a repo's release/apply convention, read it or ask. Do not
  invent a novel workaround when a standard mechanism exists.

## Work in a clean, isolated tree

- Never build a change on top of an unrelated feature branch or a tree with stale
  uncommitted edits. Branch fresh off the default branch, or use a `git worktree`,
  so the change is isolated and the plan reflects only your diff.
- If the target tree is dirty or on the wrong branch, STOP and surface it — do not
  compound your change onto someone else's in-progress work.

## Terraform spans repos

- Module definitions, the version tags that release them, and the compositions
  that consume them frequently live in DIFFERENT repos. A single logical fix can
  require: a change + release in the module repo, AND a re-apply of each consuming
  composition. Trace the whole chain before declaring done.
