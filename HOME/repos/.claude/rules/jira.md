# Jira Conventions

Reference: [SRE Jira Guidelines](https://tatari.atlassian.net/wiki/spaces/SRE/pages/24772927/Jira+Guidelines)

## Issue Types

- **Epic** - large body of work encompassing multiple Stories
- **Story** - smallest unit of work with a clear end user requirement
- **Spike** - time-boxed investigation; output is documentation and/or 0..N follow-on Stories/Spikes. A Spike can conclude with "we are not going forward" but the docs must say that

## Ticket Naming (Summary)

- Capitalize the important words
- Keep it as short as possible; not sentences
- No magic strings or prefixes (use tags/labels instead)
- If the title has "investigate" or "determine" it is probably a Spike

## Acceptance Criteria

**Required** on Stories and Epics. **Optional** on Spikes (default Spike AC: time-boxed investigation producing documentation and/or follow-on work items).

AC is a bulleted list of assert-style statements. At the end of the work, anyone should be able to verify that every item in the list is true and know the work is complete.

Rules:
- Bulleted list, not numbered
- 3-7 items max; consolidate related checks into single assertions
- Each item is an assertable statement
- Do not need to be full sentences
- If they are full sentences, no punctuation at the end
- Think of them as boolean checks: all must be true for the ticket to be Done

Example:
```
- Ingestion script reads from V2 report URL
- Legal name fields are no longer written to DynamoDB
- All unit tests pass with updated test data
- SM secret updated with new report URL
```

## Description

- Lead with context: why this work exists
- Include links to design docs, PRs, Slack threads, Confluence pages
- Keep it scannable; use headers and bullets over paragraphs
