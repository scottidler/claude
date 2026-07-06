# Voice

Any prose that leaves this machine under Scott's name goes out in his voice.

**Before drafting, read `~/Claude/writing/VOICE.md` and match the genre's register.** A Slack one-liner, a design doc, and an eval each have their own register; VOICE.md encodes them. Do not substitute a memorized digest for reading the file.

Triggers (non-exhaustive):

- Slack messages and thread replies (any path: skill, MCP, slackify)
- Email drafts and replies
- Jira: summaries, descriptions, comments, acceptance criteria
- Confluence pages and comments
- Design docs, PRDs, one-pagers, tech specs, RFCs
- GitHub: PR titles, descriptions, comments, issues, READMEs, release notes
- Marquee publishes (posts, decks) and clyde reports
- Commit messages on shared (tatari-tv) repos

Non-triggers: code, code comments, terminal replies to Scott in-session, scratch notes.

Self-check before sending:

- No em-dashes. Use `--`, colons, parens, or split the sentence.
- Lead with the point. The ask or verdict goes at the top or as the closer, never buried.
- Flat verdicts owned in first person; no hedging ceremony ("it might be worth considering").
- One honest hedge max per claim ("probably", "TBD"). No hedge-stacking, no corporate softeners.
- Structure over prose: headers, bullets, owner-per-item. Pipes for alternatives (`Dev | Staging`), `->` for transitions.
- No exclamation-as-filler, no emoji confetti, no buzzwords, no time/effort estimates.
- Shorter and blunter beats longer and softer.

Read VOICE.md only, not the corpus tree (`~/Claude/writing/voice/`). Corpus samples are for explicit voice analysis or sample mining, smallest relevant file only.

<!--
Maintenance notes (for the next agent/human):
- ~/Claude/writing/VOICE.md is a REAL FILE, copy-deployed by a private repo's manifest. It must stay
  a real file: ~/Claude is a Syncthing folder and the Cowork workspace, and symlinks there dangle on
  other machines and break Cowork. Never replace it with a symlink; edit the private repo's canonical
  copy and redeploy. The profile and its corpus are deliberately NOT in this public repo. If the path
  is missing on a new machine, deploy from the private repo; if you don't know which repo, ask Scott.
- Per-skill reinforcement: slackify, slack, and create-design-doc SKILL.md files each carry a
  "## Voice" pointer for their genre. Shared/org tooling (marquee plugin, clyde) is deliberately
  NOT edited; this always-on rule covers those surfaces instead.
- Rules only load if symlinked into ~/repos/.claude/rules/. After adding or renaming a rule file,
  run: cd ~/repos/scottidler/claude && manifest -l '*' | bash
- Any change to always-on rules is startup config: throwaway-launch test before calling it done
  (headless `claude -p "reply OK"` from a scratch dir must return cleanly).
-->

