---
name: fabric
description: Daniel Miessler's Fabric patterns - 234 battle-tested AI prompts. Use when analyzing content, extracting insights, improving prompts, creating summaries, or any structured text processing task.
---

# Fabric Patterns

Fabric is a collection of 234 battle-tested AI prompt patterns by Daniel Miessler. Each pattern solves a specific problem with a proven structure.

**Patterns location:** `~/repos/danielmiessler/Fabric/data/patterns/`

## Using Patterns

To use a Fabric pattern, read the `system.md` file from the pattern directory and follow its structure:

```bash
# Read a pattern
cat ~/repos/danielmiessler/Fabric/data/patterns/<pattern-name>/system.md
```

Then apply the pattern's structure to process the user's input.

## Pattern Structure

Each pattern follows this structure:

1. **IDENTITY and PURPOSE** - Role definition for the AI
2. **STEPS** - Sequential instructions to follow
3. **OUTPUT INSTRUCTIONS** - Formatting requirements
4. **INPUT** - Where user content goes

## Key Patterns by Category

### Analysis Patterns

| Pattern | Purpose |
|---------|---------|
| `analyze_paper` | Deep analysis of academic papers |
| `analyze_claims` | Evaluate truth/validity of claims |
| `analyze_debate` | Break down debate arguments |
| `analyze_prose` | Evaluate writing quality |
| `analyze_logs` | Parse and interpret log files |
| `analyze_malware` | Security analysis of malicious code |
| `analyze_threat_report` | Cybersecurity threat intelligence |
| `analyze_presentation` | Evaluate slide decks |
| `analyze_risk` | Risk assessment framework |

### Extraction Patterns

| Pattern | Purpose |
|---------|---------|
| `extract_wisdom` | Extract insights, ideas, quotes from content |
| `extract_ideas` | Pull out key ideas |
| `extract_recommendations` | Get actionable recommendations |
| `extract_questions` | Generate questions from content |
| `extract_references` | Pull out citations and sources |
| `extract_patterns` | Identify recurring patterns |
| `extract_skills` | List skills mentioned in content |
| `extract_book_ideas` | Key takeaways from books |

### Creation Patterns

| Pattern | Purpose |
|---------|---------|
| `create_pattern` | Create new Fabric patterns |
| `create_summary` | Generate structured summaries |
| `create_coding_project` | Scaffold code projects |
| `create_prd` | Product requirements document |
| `create_design_document` | Technical design docs |
| `create_mermaid_visualization` | Generate Mermaid diagrams |
| `create_keynote` | Presentation outlines |
| `create_quiz` | Generate quiz questions |
| `create_user_story` | Agile user stories |

### Improvement Patterns

| Pattern | Purpose |
|---------|---------|
| `improve_prompt` | Optimize AI prompts |
| `improve_writing` | Enhance prose quality |
| `improve_academic_writing` | Academic paper enhancement |
| `improve_report_finding` | Refine security findings |

### Summarization Patterns

| Pattern | Purpose |
|---------|---------|
| `summarize_paper` | Academic paper summaries |
| `summarize_meeting` | Meeting notes |
| `summarize_git_changes` | Git commit summaries |
| `summarize_lecture` | Lecture notes |
| `summarize_newsletter` | Newsletter digests |
| `summarize_rpg_session` | RPG session recaps |

### Writing Patterns

| Pattern | Purpose |
|---------|---------|
| `write_essay` | Essay composition |
| `write_micro_essay` | Short-form writing |
| `write_pull-request` | PR descriptions |
| `write_hackerone_report` | Security bug reports |
| `write_semgrep_rule` | Code analysis rules |

## Most Useful Patterns

### For Prompt Engineering

```
improve_prompt      - Make prompts more effective
create_pattern      - Create new Fabric-style patterns
```

### For Content Analysis

```
extract_wisdom      - Comprehensive insight extraction
analyze_paper       - Academic paper deep-dive
analyze_claims      - Fact-checking framework
```

### For Development

```
create_coding_project    - Project scaffolding
create_design_document   - Technical design
write_pull-request       - PR descriptions
summarize_git_changes    - Changelog generation
```

### For Security

```
analyze_malware          - Malware analysis
analyze_threat_report    - Threat intelligence
create_stride_threat_model - Threat modeling
write_hackerone_report   - Bug bounty reports
```

## Example: Using extract_wisdom

The `extract_wisdom` pattern extracts:
- **SUMMARY** - 25-word overview
- **IDEAS** - 20-50 key ideas (exactly 16 words each)
- **INSIGHTS** - 10-20 refined insights
- **QUOTES** - Notable quotes with attribution
- **HABITS** - Practical habits mentioned
- **FACTS** - Interesting facts
- **REFERENCES** - Sources and inspirations
- **ONE-SENTENCE TAKEAWAY** - 15-word essence
- **RECOMMENDATIONS** - Actionable advice

## Example: Using improve_prompt

To improve a prompt:
1. Read `~/repos/danielmiessler/Fabric/data/patterns/improve_prompt/system.md`
2. The pattern contains comprehensive prompt engineering knowledge
3. Apply its guidelines to rewrite the prompt

## Example: Using create_pattern

To create a new Fabric pattern:
1. Read `~/repos/danielmiessler/Fabric/data/patterns/create_pattern/system.md`
2. Provide the behavior you want
3. It generates a properly structured pattern with:
   - IDENTITY and PURPOSE
   - STEPS
   - OUTPUT INSTRUCTIONS
   - INPUT section

## Listing All Patterns

```bash
ls ~/repos/danielmiessler/Fabric/data/patterns | sort
```

## Pattern Count by Prefix

| Prefix | Count | Purpose |
|--------|-------|---------|
| `analyze_` | 35 | Analysis tasks |
| `create_` | 52 | Creation tasks |
| `extract_` | 32 | Extraction tasks |
| `summarize_` | 12 | Summarization |
| `write_` | 8 | Writing tasks |
| `improve_` | 4 | Enhancement |
| Other | 91 | Specialized tasks |

## Tips

1. **Read the pattern first** - Each pattern has specific requirements
2. **Follow output format exactly** - Patterns specify exact formatting
3. **Use for consistency** - Patterns ensure reproducible results
4. **Chain patterns** - Output from one can feed into another
5. **Customize locally** - Copy and modify for project-specific needs
