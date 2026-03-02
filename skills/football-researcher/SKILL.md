---
name: football-researcher
description: Research football plays, schemes, and coaching concepts for youth and high school programs. Use when researching offensive/defensive schemes, practice drills, player development, or game strategy.
---

# Football Researcher

Research football coaching concepts by searching coaching sites, playbook resources, and football communities. Use this skill when the user wants to:
- Learn offensive or defensive schemes
- Find specific plays and formations
- Research practice drills and techniques
- Study opponent tendencies or game film concepts
- Discover age-appropriate coaching methods
- Find coaching clinics and resources

## Output Storage

**Always save research results to:**

```
~/repos/scottidler/obsidian/🏈 Football/Research/<date>/<topic>.md
```

- `<date>`: ISO date format `YYYY-MM-DD`
- `<topic>`: lowercase, hyphenated topic name (e.g., `wing-t-series`, `cover-3-beaters`, `youth-tackling-drills`)

Create the directory if it doesn't exist before writing.

## Research Process

### 1. Web Search for Football Resources

Search for coaching content:

```
"<topic>" football playbook
"<topic>" youth football drills
"<topic>" high school football scheme
"<topic>" football coaching clinic
"<formation>" plays concepts
"<scheme>" install progression
```

### 2. Key Sources to Prioritize

**Playbooks & Schemes:**
- FirstDown PlayBook
- Coach and Coordinator podcast
- Cody Alexander (Match Quarters)
- Chris Brown (Smart Football)
- Xs and Os Labs

**Youth-Specific:**
- USA Football
- Glazier Clinics
- Stack.com football drills
- AFCA (American Football Coaches Association)

**Video/Film:**
- YouTube coaching channels (JT O'Sullivan, Dan Gonzalez)
- Hudl technique videos
- Coach film breakdowns

**Communities:**
- r/footballstrategy
- CoachHuey forums
- Twitter/X coaching community

### 3. YouTube Search Priority

YouTube is critical for football research:

```
"<topic>" football coaching
"<play>" install teaching progression
"<drill>" youth football
"<formation>" playbook breakdown
film room "<scheme>"
```

**Top YouTube Channels:**
- JT O'Sullivan (QB School)
- Dan Gonzalez (DG Football)
- Joe Daniel Football
- Alex Kirby (spread offense)
- Zach Dunn (defensive schemes)

### 4. Apply Fabric Patterns

| Pattern | Use Case |
|---------|----------|
| `extract_wisdom` | Extract coaching insights from clinics/articles |
| `summarize_paper` | Summarize long playbook PDFs |
| `extract_recommendations` | Pull actionable coaching advice |
| `analyze_tech_impact` | Analyze scheme evolution |

## Output Format

```markdown
# <Topic> Research

> Researched: <date>

---

## Summary

<2-3 paragraph overview of scheme/concept>

---

## Formation/Alignment

<Diagram or description of base alignment>

---

## Key Plays/Concepts

| Play Name | Formation | Description | Best Against |
|-----------|-----------|-------------|--------------|
| ... | ... | ... | ... |

---

## Coaching Points

- Key teaching point 1
- Key teaching point 2
- Common mistakes to avoid

---

## Practice Drills

| Drill | Purpose | Time |
|-------|---------|------|
| ... | ... | ... |

---

## Install Progression

1. Day 1: ...
2. Day 2: ...
3. Day 3: ...

---

## Resources

- **Videos:** [title](url)
- **Playbooks:** [title](url)
- **Clinics:** [title](url)

---

## Age-Appropriate Modifications

<Adjustments for youth/JV level>
```

## Research Depth Levels

### Quick Research (default)
- Core concept explanation
- 3-5 key plays
- Basic coaching points
- 2-3 video resources

### Deep Research (when requested)
- Complete scheme philosophy
- Full play series with variations
- Install progression schedule
- Practice scripts
- Game film examples
- Counter plays and answers
- Blocking rules and assignments

## Scheme Categories

### Offense
- **Spread:** Air Raid, RPO-heavy, zone read
- **Pro Style:** West Coast, Erhardt-Perkins
- **Option:** Wing-T, Flexbone, Veer
- **Power:** Power-I, Inside Zone, Gap schemes

### Defense
- **Even Fronts:** 4-3, 4-2-5
- **Odd Fronts:** 3-4, 3-3-5
- **Coverages:** Cover 2, Cover 3, Cover 4, Man
- **Pressures:** Zone blitz, man blitz

### Special Teams
- Kickoff/return schemes
- Punt protection/block
- Field goal operation
- Onside kicks

## Youth Considerations

- USA Football Heads Up tackling certification
- Age-appropriate contact levels
- Simplified terminology
- Reduced playbook size
- Emphasis on fundamentals over scheme complexity
- Equal playing time philosophy
