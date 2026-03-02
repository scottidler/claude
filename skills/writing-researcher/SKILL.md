---
name: writing-researcher
description: Research writing craft, publishing, and storytelling for sci-fi and children's books. Use when researching plot structures, character development, worldbuilding, publishing options, or genre conventions.
---

# Writing Researcher

Research writing craft and publishing by searching writing communities, author blogs, and literary resources. Use this skill when the user wants to:
- Learn about story structure and plot techniques
- Research worldbuilding for sci-fi
- Find children's book conventions and age-appropriate content
- Discover publishing paths (traditional vs self-publishing)
- Study character development and dialogue
- Find writing communities and critique groups

## Output Storage

**Always save research results to:**

```
~/repos/scottidler/obsidian/✍️ Writing/research/<date>/<topic>.md
```

- `<date>`: ISO date format `YYYY-MM-DD`
- `<topic>`: lowercase, hyphenated topic name (e.g., `three-act-structure`, `middle-grade-conventions`)

Create the directory if it doesn't exist before writing.

## Research Process

### 1. Web Search for Writing Resources

Search for authoritative writing content:

```
"<topic>" writing craft
"<topic>" fiction techniques
"<topic>" sci-fi worldbuilding
"<topic>" children's books age range
"<topic>" story structure
"<topic>" publishing guide <current-year>
```

### 2. Key Sources to Prioritize

**Craft & Technique:**
- Writing Excuses podcast transcripts
- Brandon Sanderson lectures (BYU)
- Jane Friedman's blog (publishing)
- SCBWI (Society of Children's Book Writers and Illustrators)
- The Creative Penn

**Sci-Fi Specific:**
- SFWA (Science Fiction Writers Association)
- Tor.com articles
- Worldbuilding Stack Exchange
- r/scifiwriting, r/worldbuilding

**Children's Books:**
- SCBWI resources
- Children's Book Insider
- Picture Book Summit
- Publishers Weekly children's reviews

**Craft Books (reference):**
- Save the Cat! Writes a Novel
- Story Genius (Lisa Cron)
- Writing the Breakout Novel (Maass)
- The Emotion Thesaurus

### 3. GitHub for Writing Tools

Search for writing-related tools:

```bash
gh search repos "writing" --limit 5 --sort stars
gh search repos "novel writing" --limit 5 --sort stars
gh search repos "worldbuilding" --limit 5 --sort stars
```

### 4. Apply Fabric Patterns

| Pattern | Use Case |
|---------|----------|
| `extract_wisdom` | Extract craft insights from articles/interviews |
| `analyze_paper` | Deep dive on writing theory |
| `summarize_paper` | Summarize long craft articles |
| `extract_recommendations` | Pull actionable writing advice |

## Output Format

```markdown
# <Topic> Research

> Researched: <date>

---

## Summary

<2-3 paragraph overview>

---

## Key Concepts

- Concept 1: explanation
- Concept 2: explanation

---

## Techniques

| Technique | Description | Example |
|-----------|-------------|---------|
| ... | ... | ... |

---

## Resources

- **Articles:** [title](url)
- **Books:** Title by Author
- **Communities:** [name](url)

---

## Recommendations

<Actionable advice for applying this research>
```

## Research Depth Levels

### Quick Research (default)
- 3-5 authoritative sources
- Key concepts explained
- 2-3 actionable recommendations

### Deep Research (when requested)
- 10+ sources across categories
- Historical context and evolution
- Multiple perspectives/schools of thought
- Detailed examples and exercises
- Tool and community recommendations

## Genre-Specific Considerations

### Sci-Fi Writing
- Hard vs soft sci-fi conventions
- Worldbuilding depth (iceberg theory)
- Technology extrapolation
- Social science fiction themes
- Avoiding info-dumps

### Children's Books
- Age ranges: board (0-3), picture (3-8), early reader (5-7), chapter (7-10), middle grade (8-12), YA (12+)
- Word count conventions by category
- Illustration considerations
- Themes appropriate by age
- Rhyme and rhythm for picture books
