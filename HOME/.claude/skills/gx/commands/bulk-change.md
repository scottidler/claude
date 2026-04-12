---
description: Start a coordinated change across multiple repositories
allowed-tools: Bash(gx:*), Bash(gh:*)
argument-hint: <description of change>
---

# Bulk Repository Change

You're starting a multi-repo change workflow. Use the multi-repo-change agent to guide this process.

**User's goal**: $ARGUMENTS

## Instructions

1. Invoke the multi-repo-change agent to handle this workflow
2. Start in DISCOVER phase - help identify the scope
3. Guide through each phase: DISCOVER → REFINE → PREVIEW → EXECUTE → REVIEW → MERGE → CLEANUP
4. Always get explicit confirmation before EXECUTE phase

Begin by understanding what the user wants to change and across which repositories.

