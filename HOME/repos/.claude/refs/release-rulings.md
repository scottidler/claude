# Release rulings

Scott's standing release rulings, one bullet each. Hall lines are in `~/HALL-OF-SHAME.md`, which stays the ledger; this file is the lookup.

## In force

- GitHub is always where the gating truth lives (Scott, 2026-10-08): `bump --gates` reads it, the hooks read it, no declaration layer. See `docs/design/2026-10-08-retro-fixes.md`.
- THE RULING, 2026-07-03, hall `:484-540`: exactly two flows, chosen by `bump --gates`. Gated: the bump rides the feature PR, the tag is cut after merge on updated main. Ungated: commit on main, push branch and tag together. No bump-only release branch, no tag off main.
- 2026-09-26, one release command: `bump release` / `bump finish` replace the hand recipe. Hook side: `HOME/.claude/hooks/git-release-guard.sh:106-111`.
- 2026-10-02 (a), hall `:1742`: protected -> release-driver, not protected -> shipit. Name the path by that word only.
- 2026-10-03 (c), hall `:1744`: on a tatari-tv ungated repo the commit-on-main hook fires anyway. Shape: commit on a temp branch, `git merge --ff-only` into main, delete the branch, `bump release` on main.
- 2026-10-03 lint-unused, hall `:1757`: ungated means never push by hand. `bump release` is the push.
- 2026-10-05 (d), hall `:1974`: ungated repo with work on a feature branch: fast-forward main to the branch locally, then `bump release` on main.
- 2026-10-07 (a), hall `:2023`: if Scott was told "on a branch", it ships as a PR; changing the path needs his OK first.
- 2026-10-07 (d), hall `:2026`: when the protected/unprotected check says unprotected on a repo Scott treats as protected, stop and ask. Do not ship.
- 2026-10-07 (e), hall `:2027`: answer "did you X?" with yes or no and the miss, no justification.

## Superseded

Not lifted. The 2026-10-08 ruling replaced each; do not re-derive them.

- 2026-10-07 (b), hall `:2024`, squash-merge heuristic ("a PR is the default whatever `bump --gates` says"): GitHub is the source, so the verdict is read, not guessed from `git log`.
- 2026-10-07 (c), hall `:2025`, "org policy beats tool output": the org policy is applied in GitHub as a ruleset, so the tool and the policy agree.
- 2026-09-29 (a), hall `:1660`, and 2026-09-30 (b), hall `:1687`: marquee's `bump --no-tag` door for a repo whose API said ungated. Marquee main gets a ruleset and the standard gated flow.
