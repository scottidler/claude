---
description: Find and pull prior Claude Code sessions into this context
argument-hint: "<what to look for>"
---
Find the prior session with the `clyde` CLI. pi has no MCP, so drive the binary directly.

Looking for: ${@:-ask me what to search for}

    clyde session search "<query>"     # ranked full-text, snippet per hit
    clyde session read <id>            # role-labeled transcript
    clyde session ls --repo <repo>     # filter by repo, date, tag, model

Run `clyde session --help` before guessing a flag. Report what the prior session actually
decided, with the session id, rather than summarizing from the snippet alone.
