---

name: spec-review
description: Run parallel spec review with 5 team personas (SRE, Security, Data, Product, Leadership) until convergence. Use for tech spec cross-functional review.
user-invocable: true
allowed-tools: [Read, Glob, Grep, Task]
---

# Spec Review - Cross-Functional Persona Review

## Overview

Run 5 parallel persona sub-agents that review a tech spec from distinct organizational perspectives, synthesize findings, and repeat until convergence. Max 3 rounds.

**Announce at start:** "Using /spec-review to run cross-functional review of this tech spec."

## Personas

### 1. SRE

- **Core identity**: Site Reliability Engineer responsible for production stability, observability, and incident response
- **Sections to review**: Monitoring & Observability (Logging Plan, Health Metrics, Alerting Plan), Scale & Performance, Reliability & Resilience, AWS Cloud Cost Analysis, System Architecture
- **Review questions**:
  - Are SLIs/SLOs defined or derivable from the spec?
  - Is the alerting plan concrete (thresholds, channels, escalation)?
  - Are failure modes enumerated with recovery strategies?
  - Does the scale section quantify expected load (TPS, data volume, latency targets)?
  - Are there single points of failure in the architecture?
  - Is the cost model reasonable for the expected scale?
- **Blocker criteria (P1)**: Missing alerting plan, no failure mode analysis, undefined scale targets, single points of failure with no mitigation

### 2. Security

- **Core identity**: Security engineer responsible for threat modeling, access control, and compliance
- **Sections to review**: Security & Privacy (mandatory section), APIs and Interface Changes, Data Model / Schema Changes, New Technology
- **Review questions**:
  - Does the Security & Privacy section contain a reasoned assessment (not just a checklist reference)?
  - Are authentication and authorization mechanisms specified?
  - Is sensitive data identified with encryption at rest and in transit?
  - Are external dependencies assessed for supply chain risk?
  - Does the API design follow least-privilege and input validation?
  - Are OWASP Top 10 risks addressed where applicable?
  - Are compliance requirements (GDPR, CCPA, SOC 2) identified if relevant?
- **Blocker criteria (P1)**: Empty or boilerplate Security & Privacy section, unencrypted sensitive data, missing auth model for public-facing APIs, no "No Review Needed Justification" when claiming no security impact

### 3. Data

- **Core identity**: Data engineer/analyst responsible for data quality, pipeline integrity, and schema evolution
- **Sections to review**: Data Model / Schema Changes, Data Flow / Process Flow, Scale & Performance, APIs and Interface Changes
- **Review questions**:
  - Are schema changes backward-compatible or is a migration plan provided?
  - Is data validation defined at ingestion boundaries?
  - Are data retention and lifecycle policies addressed?
  - Is the data flow diagram complete (source -> transform -> sink)?
  - Are there race conditions or consistency gaps in the data pipeline?
  - Does the API contract match the data model?
- **Blocker criteria (P1)**: Breaking schema change with no migration plan, missing data validation at ingestion, undefined data flow for a data-heavy feature

### 4. Product

- **Core identity**: Product manager responsible for requirements alignment, user impact, and scope clarity
- **Sections to review**: Summary (Goals, Non-Goals, Assumptions, Dependencies), Proposed Solution, Execution Plan / Phases, Open Questions, Future Changes
- **Review questions**:
  - Do the goals directly address the problem stated in the PRD?
  - Are non-goals explicit enough to prevent scope creep?
  - Are assumptions testable or validated?
  - Does the phasing deliver incremental user value?
  - Are open questions blocking any phase?
  - Is the dependency list complete (upstream and downstream)?
- **Blocker criteria (P1)**: Goals that don't map to PRD requirements, open questions that block Phase 1, missing dependencies that could delay delivery

### 5. Leadership

- **Core identity**: Engineering manager / director responsible for cross-team coordination, timeline feasibility, and organizational risk
- **Sections to review**: Summary (Goals, Non-Goals, Assumptions, Dependencies), Execution Plan / Phases, New Technology, Design Alternatives, AWS Cloud Cost Analysis
- **Review questions**:
  - Is the phasing realistic given team capacity and competing priorities?
  - Are cross-team dependencies identified with owners?
  - Is new technology justified against existing solutions?
  - Were design alternatives fairly evaluated (not straw-manned)?
  - Is the cost-benefit ratio reasonable for the business impact?
  - Are there organizational risks (key-person dependency, knowledge silos)?
- **Blocker criteria (P1)**: Unrealistic phase timeline with no justification, new technology with no comparison to existing stack, missing design alternatives for a significant architecture decision

## Severity Levels

| Level | Meaning | Blocking? |
| ----- | ------- | --------- |
| P1 | Must fix before approval - spec is incomplete or has a critical gap | Yes - status becomes "Not Ready for Approval" |
| P2 | Should fix - improves spec quality, reduces risk | No - but recommended before finalizing |
| P3 | Nice to have - minor clarity or style improvements | No |

**Blocking rule**: Any P1 from any persona sets the overall status to "Not Ready for Approval". A spec is "Ready for Approval" only when zero P1 issues remain.

## Workflow

### Step 1: Read Spec and Build Section Inventory

1. **Determine spec source** based on the argument:
   - **Local file path** (e.g., `path/to/spec.md`): Read the file directly
   - **Confluence page ID** (numeric string): Fetch via Confluence (see Confluence Fetch Pattern below)
   - **Confluence URL** (contains `atlassian.net`): Extract page ID from URL, fetch via Confluence
   - **No argument**: Ask the user for a spec path, page ID, or URL

2. **Load the template heading tree** from `config/templates/tech-spec-template.md` using Read tool. Extract all markdown headings to build the expected section list.

3. **Parse the spec** against the template heading tree. For each expected heading, classify as:
   - **Filled**: Heading present with substantive content below it (not just HTML comments or placeholder text like `{...}`)
   - **Empty**: Heading present but only contains HTML comments, placeholder text, or whitespace
   - **Missing**: Heading not found in the spec

4. **Build section inventory** - a structured list:

   ```
   SECTION INVENTORY:
   - Summary: Filled
     - Goals: Filled
     - Non-Goals (Out of Scope): Empty
     - Assumptions: Missing
     - Dependencies: Filled
   - Proposed Solution: Filled
     - System Architecture: Filled
     - Data Model / Schema Changes: Empty
     ...
   ```

5. **Announce**: "Section inventory complete. [N] filled, [N] empty, [N] missing sections. Launching 5 persona reviews."

### Step 2: Launch Parallel Persona Sub-Agents

Launch all 5 personas as `Task(subagent_type='general-purpose', model='sonnet')` sub-agents **in a single message** (parallel execution). Each sub-agent receives:

1. The spec file path (for local files) or the spec content (for Confluence pages)
2. The section inventory from Step 1
3. Its persona definition (identity, sections to review, review questions, blocker criteria)
4. The structured output format

**Sub-agent prompt template** (adapt per persona):

```text
You are reviewing a tech spec as the **[PERSONA NAME]** reviewer.

**Your identity**: [Core identity from persona definition]

**Spec to review**: [path or inline content]

Read the spec completely. Focus on these sections:
[List of sections from persona definition]

Section inventory (from template comparison):
[Section inventory from Step 1]

Evaluate against these questions:
[Review questions from persona definition]

Flag as P1 (blocker) if any of these apply:
[Blocker criteria from persona definition]

Report using EXACTLY this format:

PERSONA: [Persona Name]
STATUS: CLEAN | ISSUES_FOUND
ISSUES:
- [P1|P2|P3] [Section Name] [description of finding]
- ...
MISSING_SECTIONS:
- [Section Name] [why this matters for your review area]
- ...
SUMMARY: [2-3 sentence summary of your review from this persona's perspective]

If no issues found, use STATUS: CLEAN, ISSUES: none, and MISSING_SECTIONS: none.
```

**Error handling:** If a sub-agent returns malformed output or fails, re-launch that single persona. After 2 failures for the same persona, skip it and note in the review log. A skipped persona is excluded from the selected set - convergence is evaluated against remaining active personas only.

### Step 3: Synthesize Findings

After all sub-agents complete:

1. **Collect** all ISSUES and MISSING_SECTIONS from every persona
2. **Deduplicate** - same section flagged by multiple personas counts once (note which personas flagged it)
3. **Detect conflicts** - if two personas disagree (e.g., Product says "Phase 1 scope is fine", Leadership says "Phase 1 is too ambitious"), flag as CONFLICT
4. **Sort** by severity: P1 -> P2 -> P3
5. **Apply blocking rule**: if any P1 exists, overall status is "Not Ready for Approval"

### Step 4: Present Findings

Present the synthesized findings to the user:

- **P1 issues**: Present each with recommended spec text that would resolve it. Quote the specific section and suggest concrete additions or changes.
- **P2 issues**: Present with recommendation and rationale
- **P3 issues**: Present briefly in a grouped list
- **Conflicts**: Present as "[Persona A] recommends X because [reason]. [Persona B] recommends Y because [reason]. Tradeoff: [summary]." Do NOT auto-resolve.
- **Missing sections**: List with which personas need them and why
- **New open questions**: Surface any questions the personas raised that aren't in the spec's Open Questions section

**Announce overall status**: "Spec Status: [Ready for Approval / Not Ready for Approval - N P1 issues remain]"

### Step 5: Re-Review (If User Applies Fixes)

If the user applies fixes and requests re-review:

1. Select personas to re-run:
   - **Default**: re-run ALL personas that returned ISSUES_FOUND in the previous round
   - **Narrow fixes** (single section changed): re-run only the personas that flagged that section
2. Launch only those personas as parallel sub-agents (same prompt template, updated spec content)
3. Synthesize again (back to Step 3)

### Step 6: Convergence Check

- **Converged**: a round where ALL active personas return CLEAN -> done
- **Not converged**: repeat from Step 5 with only personas that returned ISSUES_FOUND
- **Max 3 rounds**: after 3 rounds without convergence, stop and present remaining issues sorted by severity. User decides whether to accept, fix manually, or extend review.

Announce: "Round N complete. [Converged / N issues remain, starting round N+1 / Max rounds reached, reporting remaining issues]."

## Confluence Fetch Pattern

When the spec source is a Confluence page ID or URL:

1. **Get configuration** via config-management skill. Extract:
   - `tickets.config.jira.host` (used as Atlassian cloud ID)

2. **Try Confluence fetch**:
   - Call `mcp__atlassian__getConfluencePage` with:
     - `cloudId`: the Jira host value (e.g., `tatari.atlassian.net`)
     - `pageId`: the extracted page ID
     - `contentFormat`: `"markdown"`
   - If successful:
     - Strip all `<custom data-type="placeholder" ...>...</custom>` elements - these are Confluence UI guide hints, not content
     - Use the cleaned result as the spec content
     - Announce: "Fetched spec from Confluence (page {pageId})"
   - If the fetch fails (MCP tool unavailable, page not found, auth error, network issue):
     - Log warning: "Could not fetch Confluence page {pageId}. Please provide a local file path or paste the spec content."
     - Ask user for alternative input

3. **Extract page title** from the Confluence response for use as `{spec-name}` in the review log filename.

## When to Use

- After a tech spec draft is ready for cross-functional review
- Before circulating a spec to human reviewers (catch gaps early)
- When updating a spec and want to verify all sections remain addressed
- After a tech plan is produced that needs organizational validation

## Not For

- Code review or PR review
- Generic design quality review
- PRD review (this skill focuses on technical specifications)
- Simple bug fixes or small changes that don't warrant a spec
