---
name: building-researcher
description: Research construction, DIY projects, and building techniques from YouTube and other sources. Use when researching building methods, tool selection, materials, code requirements, or project planning.
---

# Building Researcher

Research construction and DIY projects by searching YouTube, building forums, and contractor resources. Use this skill when the user wants to:
- Learn building techniques and methods
- Research tool selection and usage
- Find material specifications and options
- Understand building codes and permits
- Plan project sequences and timelines
- Troubleshoot construction problems

## Output Storage

**Always save research results to:**

```
~/repos/scottidler/obsidian/notes/<topic>.md
```

- `<topic>`: lowercase-hyphenated slug with `-research` suffix (e.g., `shed-foundation-research`, `electrical-rough-in-research`, `deck-framing-research`)
- All research notes go to the flat `notes/` folder - no subdirectories

## Research Process

### 1. YouTube Search (Primary Source)

YouTube is the primary source for building research:

```
"<topic>" DIY tutorial
"<topic>" how to build
"<topic>" step by step
"<topic>" pro tips
"<topic>" common mistakes
"<topic>" building code
```

**Top YouTube Channels:**

**General Construction:**
- Essential Craftsman (Scott Wadsworth) - fundamentals, wisdom
- Matt Risinger - building science, best practices
- This Old House - techniques, problem-solving
- Home RenoVision DIY - practical tutorials

**Framing/Carpentry:**
- The Honest Carpenter
- Perkins Builder Brothers
- Larry Haun (classic framing)

**Electrical:**
- Electrician U
- How To Home
- Sparky Channel

**Plumbing:**
- Roger Wakefield
- Got2Learn

**Finish Work:**
- Finish Carpentry TV
- The Craftsman Blog

### 2. Web Search for Specifications

```
"<topic>" building code requirements
"<topic>" material specifications
"<topic>" best practices <current-year>
"<material>" installation guide
"<tool>" how to use properly
```

### 3. Key Sources to Prioritize

**Codes & Standards:**
- ICC (International Code Council)
- Local building department websites
- NEC (electrical code)
- UPC/IPC (plumbing codes)

**Building Science:**
- Building Science Corporation (buildingscience.com)
- Fine Homebuilding
- Journal of Light Construction

**DIY Communities:**
- r/HomeImprovement
- r/DIY
- Contractor Talk forums
- GardenWeb/Houzz forums

**Manufacturer Resources:**
- Simpson Strong-Tie (connectors)
- Tyvek/Dupont (housewrap)
- LP/Advantech (sheathing)
- Individual product install guides

### 4. Apply Fabric Patterns

| Pattern | Use Case |
|---------|----------|
| `extract_wisdom` | Extract tips from contractor videos |
| `extract_recommendations` | Pull tool and material recommendations |
| `summarize_paper` | Summarize technical building documents |
| `compare_and_contrast` | Compare material/tool options |

## Output Format

Every research note must have proper YAML frontmatter per the vault schema, followed by the research content.

```markdown
---
title: "<Human Readable Topic> Research"
date: <YYYY-MM-DD>
type: research
domain: knowledge
origin: assisted
tags:
  - building
  - <relevant-tags>
---

## Summary

<2-3 paragraph overview of technique/project>

## Tools Required

| Tool | Purpose | Notes |
|------|---------|-------|
| ... | ... | Buy vs rent? |

## Materials

| Material | Quantity Calc | Alternatives |
|----------|---------------|--------------|
| ... | ... | ... |

## Step-by-Step Process

1. **Prep:** ...
2. **Step 1:** ...
3. **Step 2:** ...

## Code Considerations

- Permit required: Yes/No
- Inspection points: ...
- Key code requirements: ...

## Pro Tips

- Tip from experienced builders
- Common mistakes to avoid
- Time/money savers

## Video Resources

| Video | Channel | Why Watch |
|-------|---------|-----------|
| [title](url) | ... | ... |

## Safety Considerations

- PPE required
- Hazards to watch for
- When to call a pro
```

## Research Depth Levels

### Quick Research (default)
- Basic technique overview
- Key tools and materials
- 2-3 video tutorials
- Main code considerations

### Deep Research (when requested)
- Complete project breakdown
- Tool buying guide
- Material cost estimates
- Full code research
- Multiple technique variations
- Troubleshooting common problems
- Professional vs DIY comparison

## Project Categories

### Structural
- Foundation types (concrete, pier, slab)
- Framing (walls, roof, floor)
- Load-bearing considerations
- Connections and fasteners

### Exterior
- Siding and trim
- Roofing
- Windows and doors
- Waterproofing

### Systems
- Electrical (circuits, panels, outlets)
- Plumbing (supply, drain, venting)
- HVAC basics
- Insulation

### Interior
- Drywall
- Flooring
- Trim and finish
- Painting

### Outbuildings
- Sheds
- Workshops
- Garages
- Decks and patios

## Safety First

Always include:
- Required PPE for task
- Tool safety basics
- When permits/inspections needed
- When to hire a licensed professional (gas, main electrical panel, structural changes)
- Lead/asbestos considerations in older homes
