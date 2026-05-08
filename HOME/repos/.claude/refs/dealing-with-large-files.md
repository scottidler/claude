# Decomposing Large Files

Files that exceed a language's size threshold (Rust: 1,500 lines, Python: 1,000 lines) need decomposition into a module directory. This is dangerous territory for LLM agents - the wrong approach can be catastrophic.

## The failure mode (2026-03-31 incident)

A 13,000-line `handlers.rs` needed decomposition. The agent used `sed`, `python3`, `head`, `tail` with precise line numbers to surgically delete function bodies. These commands are brittle on large files - they kept failing (exit 120, 134). Each failure logged the full 483KB file content to Claude Code's session transcript in `/tmp/claude-1000/`. The agent retried hundreds of times, each iteration carrying the half-megabyte file in context. The JSON transcript files ballooned exponentially until `/tmp` (a 16GB tmpfs RAM disk) hit 100% capacity, killing the session and all shell commands.

**Root cause:** Using line-number-based bash commands (sed, awk, python scripts) on large files inside an LLM agent loop. Failures compound because every retry dumps the full file into the transcript.

## The correct approach

1. **Insert comment markers** at section boundaries (e.g. `// SECTION_START`, `// SECTION_END` or `# SECTION_START`) using the Edit tool with small, unique string matches
2. **Use `head`/`tail` to split** at the markers - these are deterministic, single-pass, and don't fail:
   ```bash
   head -n 233 mod.rs > /tmp/top.rs
   /usr/bin/tail -n +5354 mod.rs > /tmp/bottom.rs
   cat /tmp/top.rs /tmp/bottom.rs > mod.rs
   ```
3. **Use the Edit tool** for small, targeted changes (adding mod declarations, fixing imports) - never for removing thousands of lines
4. **Work incrementally** - compile/lint check after each change, fix issues one at a time
5. **Never read a giant file and attempt a single massive deletion** - break it into phases

## What to NEVER do

- `sed` with line ranges on files over 1,000 lines (fragile, fails silently or noisily)
- Python scripts that read/rewrite large files (same failure mode)
- Any approach that retries on failure while carrying the full file in context
- Multiple parallel agents editing the same large file (git index lock contention)
