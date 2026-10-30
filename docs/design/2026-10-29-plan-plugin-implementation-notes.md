## Phase 0: Prove skills-dir loads skills and agents
### Design decisions
- (b) used a scratch settings file passed with `--settings` carrying a PreToolUse capture hook, never the committed `settings.json`; the scratch file and log were removed with `rkvr rmrf`.
- (e) judged by the `reason_type: "rule"` in the permission decision, because auto mode accepts the control call too and a denial cannot be produced under `defaultMode: auto`.
- (h) observed through pi's own `DefaultResourceLoader` against scratch agent dirs holding copies of `HOME/.pi/agent/settings.json` (pi has no list-skills command, and `pi -p` needs a model call).
- (i) driven in an interactive `claude` under tmux with pane capture, so it is verified, not UNVERIFIED.
- (j) `enable` removes the `enabledPlugins` key rather than writing `true`, so Phase 4's enumerator must treat an absent key as enabled.

### Deviations
- None.

### Tradeoffs
- Headless init events and a loader script prove load and registration. They do not prove `${CLAUDE_PLUGIN_ROOT}` expands inside a Bash command the model runs, only in skill and agent body text. Phase 1 can use it in bodies and should keep absolute paths at the head of Bash commands until Phase 5 proves it live.

### Open questions
- None.
