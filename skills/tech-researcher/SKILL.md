---
name: tech-researcher
description: Research technical topics by searching GitHub repos, blog posts, documentation, and other sources. Uses Fabric patterns for structured analysis. Use when the user wants to learn about a technology, find libraries, or gather information on a topic.
---

# Tech Researcher

Research technical topics comprehensively by searching multiple sources and applying Fabric patterns for structured analysis. Use this skill when the user wants to:
- Find GitHub repositories for a technology or problem
- Discover blog posts and articles about a topic
- Locate official documentation
- Compare tools, libraries, or frameworks
- Learn about best practices or patterns

## Research Process

When researching a topic, follow this structured approach:

### 1. GitHub Repository Search

Search for relevant repositories using the `gh` CLI (run via Bash, not a skill):

```bash
# Search by topic
gh search repos "<topic>" --limit 10 --sort stars

# Search with language filter
gh search repos "<topic> language:rust" --limit 10 --sort stars

# Search by description
gh search repos "<topic>" --limit 10 --sort updated
```

For each promising repo, gather details:

```bash
# Get repo info
gh repo view <owner>/<repo>

# Check recent activity
gh repo view <owner>/<repo> --json updatedAt,stargazerCount,description
```

### 2. Web Search for Articles and Docs

Use WebSearch to find:
- Official documentation
- Blog posts and tutorials
- Comparisons and benchmarks
- Best practices guides

Search queries to try:
- `"<topic>" documentation official`
- `"<topic>" tutorial guide`
- `"<topic>" vs "<alternative>" comparison`
- `"<topic>" best practices <current-year>`
- `"<topic>" examples github`

### 3. Fetch and Summarize Content

Use WebFetch to read promising pages and extract key information:
- Features and capabilities
- Installation/setup instructions
- Pros and cons
- Code examples
- Community activity

### 4. Apply Fabric Patterns for Analysis

Use Fabric patterns from `~/repos/danielmiessler/Fabric/data/patterns/` to structure your analysis:

#### For Content Analysis

**extract_wisdom** - Extract comprehensive insights from articles/docs:
- SUMMARY (25 words)
- IDEAS (20-50 key ideas)
- INSIGHTS (10-20 refined insights)
- QUOTES (notable quotes)
- RECOMMENDATIONS (actionable advice)
- ONE-SENTENCE TAKEAWAY

**analyze_paper** - Deep analysis of academic papers or technical docs:
- Main arguments and findings
- Methodology evaluation
- Strengths and weaknesses
- Implications

#### For Comparisons

**compare_and_contrast** - Structured comparison of tools/libraries:
- Feature comparison matrix
- Pros/cons for each option
- Use case recommendations

#### For Summarization

**summarize_paper** - Concise paper/article summaries
**create_5_sentence_summary** - Ultra-brief summaries
**extract_recommendations** - Pull out actionable items

#### Pattern Usage

To apply a pattern:
1. Read the pattern: `cat ~/repos/danielmiessler/Fabric/data/patterns/<pattern>/system.md`
2. Follow its IDENTITY, STEPS, and OUTPUT INSTRUCTIONS
3. Process the fetched content through the pattern structure

## Output Storage

**Always save research results to:**

```
~/repos/scottidler/obsidian/🤖 Tech/Research/<date>/<topic>.md
```

- `<date>`: ISO date format `YYYY-MM-DD`
- `<topic>`: lowercase, hyphenated topic name (e.g., `slack-mcp`, `rust-http-clients`)

Create the directory if it doesn't exist before writing.

## Output Format

Present research findings in a structured format:

```markdown
## Topic: <topic>

### Top GitHub Repositories

| Repository | Stars | Description |
|------------|-------|-------------|
| owner/repo | 1.2k  | Brief desc  |

### Key Resources

- **Official Docs:** [link]
- **Best Tutorial:** [link]
- **Comparison:** [link]

### Summary

<2-3 paragraph summary of findings>

### Recommendations

<actionable recommendations based on research>
```

## Research Depth Levels

Adjust depth based on user needs:

### Quick Research (default)
- Top 5 GitHub repos by stars
- 2-3 key documentation/article links
- Brief summary

### Deep Research (when requested)
- Top 10+ repos with detailed analysis
- Multiple articles and comparisons
- Code examples and patterns
- Community sentiment analysis
- Pros/cons breakdown

## Source Priority

Prioritize sources in this order:

1. **Official documentation** — Most authoritative
2. **GitHub repos** — Real implementations and examples
3. **Reputable tech blogs** — (e.g., official company blogs, known authors)
4. **Stack Overflow** — Community solutions
5. **Tutorial sites** — Learning resources

## Avoiding Noise

Filter out:
- Outdated content (check dates, prefer recent)
- Low-quality SEO articles
- Abandoned repos (no commits in 2+ years, unless stable/complete)
- Paywalled content

## Example Research Queries

| User Request | Research Approach |
|--------------|-------------------|
| "Find a good Rust HTTP client" | Search GitHub for `http client language:rust`, compare reqwest vs ureq vs hyper |
| "How does X technology work?" | Find official docs, architecture posts, GitHub readme |
| "Best practices for Y" | Search for style guides, official recommendations, popular repos' patterns |
| "Compare A vs B" | Find comparison articles, check GitHub stars/activity, read discussions |

## Fabric Pattern Reference

Key patterns for research tasks (in `~/repos/danielmiessler/Fabric/data/patterns/`):

| Pattern | Use Case |
|---------|----------|
| `extract_wisdom` | Comprehensive insight extraction |
| `analyze_paper` | Academic/technical paper analysis |
| `analyze_tech_impact` | Technology impact assessment |
| `compare_and_contrast` | Tool/library comparisons |
| `summarize_paper` | Paper summarization |
| `extract_recommendations` | Actionable recommendations |
| `extract_references` | Source and citation extraction |
| `create_5_sentence_summary` | Ultra-brief summaries |

## Future Capabilities

*Not yet implemented:*
- YouTube video search and summarization (use `extract_wisdom` on transcripts)
- Conference talk discovery
