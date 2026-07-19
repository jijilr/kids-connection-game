# Epistemological Classification Engine — Architecture Document

> **Date**: June 19, 2026  
> **Project evolution from**: `Ishans_games_4` (Flutter Connections-style puzzle game)  
> **For**: Sharing with another AI / future reference

---

## 1. THE VISION

### From → To

| From | To |
|------|-----|
| A fixed Connections-style game (4 groups of 4, pre-programmed items) | A **taxonomic tree-traversal game** that grows with the child |
| 57 pre-built items, 8 categories | Potentially thousands of items across dozens of knowledge domains (biology, chemistry, physics...) |
| Flat category matching | Progressive depth: animate/inanimate → animals/plants → extinct/living → carnivore/herbivore → by era → by clade → ... |
| One child, static content | Multi-child, shared knowledge base, content grows organically |
| You (human) design everything | **AI agents discover structure from play data** |

### Core Philosophy

This is not a game with AI-generated content. It is an **epistemological engine** — a system that learns how to teach taxonomy by watching children learn taxonomy.

The child discovers through **visual pattern recognition** — they notice "short hands and big heads = carnivores" — not explicit instruction. The game provides the images; the child provides the insight.

---

## 2. GAME MECHANIC

### What stays the same
- Grid-based grouping (4 groups of 4 items, like NYT Connections)
- Image-driven — every item has a cute, child-friendly illustration
- Flutter cross-platform (iPad, Android tablet, Windows, iPhone, Android phone)
- Scoring, lifelines, audio feedback

### What changes
- **Tree traversal, not one-off puzzles**: Child solves a classification → zooms into one branch → classifies deeper → continues
- **Multi-dimensional exploration**: The same set of 16 items could be validly grouped by diet, by extinction status, by era, by size... The system decides which dimension is the "intended" one for each round
- **Seen-pool reclassification**: After accumulating ~100+ seen items, the system constructs puzzles from the SEEN pool using dimensions the child has NOT yet explored. This forces productive mental-model rebuilding ("T-Rex and Brachiosaurus are BOTH extinct? But I thought T-Rex was with carnivores...")

### The Loop

```
Child enters Level N (e.g., "Carnivorous Dinosaurs")
  → Sees 16 images in a grid
  → Groups them (4 groups of 4) by the intended dimension
  → Solves successfully
  → Presented options:
      🔽 Continue: "Carnivores → By Era?" (depth progression)
      🔀 Explore: "Same creatures — by Extinct vs Living?" (lateral dimension)
      🎲 Random: "Jump to Ocean Predators" (serendipity)
  → Child chooses → next puzzle loads
```

---

## 3. DATA ARCHITECTURE

### The Critical Design Decision: Tags as Data, Not Schema

**The problem**: A fixed tag schema (e.g., `{diet, era, extinction, habitat...}`) cannot scale to unknown future domains. Bacteria need different dimensions than dinosaurs. Chemistry needs different dimensions than biology. You cannot pre-design everything.

**The solution**: Tags are flat strings stored on items. Dimensions are **discovered later** by an AI agent. Structure emerges from data, not from pre-design.

### Item Model (minimum viable)

```json
{
  "id": "trex_01",
  "name": "T-Rex",
  "category": "dinosaur",
  "imageUrl": "https://storage.../trex.png",
  "imagePrompt": "cute cartoon T-Rex, large head, tiny arms, flat vector style",
  "tags": [
    "carnivore", "extinct", "cretaceous", "land", 
    "large", "bipedal", "theropod", "tyrannosaurid"
  ]
}
```

Tags are **flat strings**. No hierarchy. No predefined values. Just descriptive labels. Any tag can be added to any item at any time.

### Dimension Model (discovered, not pre-designed)

```json
{
  "dimensionId": "dim_diet",
  "displayName": "Diet Type",
  "question": "What do they eat?",
  "domain": "biology",
  "values": {
    "carnivore": "Meat-Eaters",
    "herbivore": "Plant-Eaters",
    "omnivore": "Eats Both"
  },
  "discoveredFrom": ["carnivore", "herbivore", "omnivore"],
  "confidence": 0.94,
  "discoveredAt": "2026-07-15T..."
}
```

Dimensions are **computed from tag co-occurrence patterns**, not authored by humans.

### User Progress Model

```json
{
  "userId": "...",
  "seenItems": ["trex_01", "brachio_02", ...],       // all items ever encountered
  "solvedDimensions": ["diet", "habitat", "era"],     // dimensions already explored
  "completedRounds": 12,
  "depth": 4,
  "currentDomain": "dinosaur"
}
```

### Firestore Collections

```
items/{itemId}           — all items across all domains
tags/{tagId}             — (optional) tag metadata
dimensions/{dimensionId} — discovered grouping dimensions
user_progress/{userId}   — per-child state
puzzles/{puzzleId}       — cached puzzles for reuse
```

---

## 4. MULTI-AGENT AI ARCHITECTURE

The system uses **three specialized AI agents**, not one monolithic generator:

### Agent 1: Content Generator
**Trigger**: On-demand, when child reaches unexplored depth  
**Latency budget**: 3-8 minutes (fires when child ENTERS parent level, must complete before they finish)

```
Input:  Domain + depth + parent taxonomy path
Output: 16 items with flat tags + image prompts + fun facts
        + 3-4 proposed classification dimensions for these items
        + One "primary puzzle" (intended dimension + group assignments)

Example output:
{
  "items": [
    {"name": "E. coli", "tags": ["bacillus", "gram_negative", "facultative", ...], "imagePrompt": "..."},
    ...
  ],
  "primaryPuzzle": {
    "dimension": "gram_stain",
    "groups": [
      { "value": "positive", "items": [...] },
      { "value": "negative", "items": [...] }
    ]
  },
  "discoveredDimensions": [
    { "key": "shape", "displayName": "Cell Shape", "values": ["coccus", "bacillus", "spirillum", "vibrio"] },
    { "key": "oxygen_requirement", "displayName": "Oxygen Need", "values": ["aerobic", "anaerobic", "facultative"] }
  ]
}
```

### Agent 2: Dimension Discoverer (the "back-propagation" agent)
**Trigger**: Periodic (cron job, or when N new items accumulate)  
**Latency budget**: Async — runs in background, not blocking gameplay

```
Algorithm:
1. GATHER all items, grouped by category/domain
2. EXTRACT all unique flat tags
3. CORRELATE: which tags NEVER co-occur on the same item?
   → "carnivore" and "herbivore" NEVER co-occur → same dimension
   → "cretaceous" and "jurassic" NEVER co-occur → same dimension
   → "carnivore" and "cretaceous" DO co-occur (T-Rex) → different dimensions
4. CLUSTER mutually-exclusive tags into candidate dimensions
5. VALIDATE via LLM: does this set make taxonomic sense?
6. STORE discovered dimension
7. ENRICH items: add dimension grouping to items that have the relevant tags
8. GAP-FILL: find items MISSING tags for known dimensions
   → "Brachiosaurus has [herbivore, jurassic, land...] but no 'extinct'.
      Is Brachiosaurus extinct? Yes → add tag 'extinct'."
```

This is **genuinely tensor-like**: Items × Tags = sparse matrix. Agent 2 performs matrix factorization to discover latent dimensions, and matrix completion to fill missing tags.

### Agent 3: Puzzle Constructor
**Trigger**: Synchronously, between rounds  
**Latency budget**: < 1 second (computation, no LLM call)

```
Input:  Child's seenItems + solvedDimensions + depth
Output: 16 items + 1 intended dimension = a valid puzzle

Algorithm:
1. FILTER seenItems for items with ≥5 tags (thin items can't support reuse)
2. COMPUTE: for each UNEXPLORED dimension:
   - Can seen items form balanced groups? (ideal: 4 groups × 4 items)
   - Score by group balance + visual distinctiveness
3. RANK dimensions, pick best unexplored one
4. ENFORCE UNIQUENESS:
   - Check if any OTHER dimension also forms valid groups
   - If so, swap 1-2 items with "poison" items that break the alternative
   - Repeat until ONLY the intended dimension works
5. If seen pool is insufficient: pull new items from seed data
6. RETURN 16 item IDs + dimension + group labels
```

### Agent Interaction Flow

```
                     ┌──────────────┐
                     │   Children   │
                     │    Play      │
                     └──────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        ┌──────────┐ ┌──────────┐ ┌──────────────┐
        │ Agent 3  │ │ Agent 1  │ │   Play Data  │
        │ Puzzle   │ │ Content  │ │ Accumulates  │
        │ Construc.│ │ Generator│ │ (Firestore)  │
        └──────────┘ └──────────┘ └──────┬───────┘
              │             │            │
              │             │     ┌──────▼───────┐
              │             │     │  Agent 2     │
              │             │     │  Dimension   │
              │             │     │  Discoverer  │
              │             │     │  (periodic)  │
              │             │     └──────┬───────┘
              │             │            │
              │             │     ┌──────▼───────┐
              │             │     │  Items are   │
              │             │     │  enriched    │
              │             │     │  retroactively│
              │             │     └──────────────┘
              ▼             ▼
        ┌─────────────────────────┐
        │  Puzzles served         │
        │  to children            │
        └─────────────────────────┘
```

---

## 5. THE MULTI-DIMENSIONAL GROUPING PROBLEM

### The Challenge

Given 16 items with rich tag vectors, multiple dimensions may form valid, non-overlapping groups simultaneously:

```
T-Rex:          {diet: carnivore, extinction: extinct, era: cretaceous}
Brachiosaurus:  {diet: herbivore, extinction: extinct, era: jurassic}
Tiger:          {diet: carnivore, extinction: alive, era: modern}
Sheep:          {diet: herbivore, extinction: alive, era: modern}

All valid groupings:
  By diet:       Carnivore (T-Rex, Tiger) vs Herbivore (Brachio, Sheep)
  By extinction: Extinct (T-Rex, Brachio) vs Living (Tiger, Sheep)
  By era:        Mesozoic (T-Rex, Brachio) vs Modern (Tiger, Sheep)
```

### The Resolution

**Each round has ONE intended dimension.** The Puzzle Constructor (Agent 3) ensures uniqueness by:
1. Selecting the intended dimension
2. Checking all other dimensions for validity
3. If another dimension also forms clean groups, swapping items with "poison" items that break the alternative
4. The other valid dimensions become **explore options** (🔀) — available but not the primary path

### The Pedagogical Value

When the system serves a puzzle where a child's old grouping assumption breaks ("Wait, T-Rex and Brachiosaurus are BOTH extinct? But I grouped T-Rex as carnivore before..."), the child's mental model is **productively broken**. They must rebuild their taxonomy from a new angle. This is the deepest learning moment.

---

## 6. SERENDIPITY INJECTION (Netflix 20% Model)

To prevent children from tunneling down one narrow path (e.g., dinosaurs → carnivores → Cretaceous → tyrannosaurids forever), the system injects:

1. **80% of rounds**: Natural depth progression (continue down the current branch)
2. **20% of rounds**: Lateral jumps or forced dimension shifts
   - "You've been classifying dinosaurs for 5 rounds. Explore ocean life?"
   - "Same creatures, but can you group them a DIFFERENT way?"
   - Adjacent domain suggestions from a pre-defined adjacency map

### Adjacency Map (human-authored, lightweight)

```
dinosaurs ↔ prehistoric-reptiles ↔ ocean-predators
mammals ↔ marsupials ↔ egg-layers
plants ↔ fungi ↔ bacteria
chemistry ↔ physics ↔ earth-science
```

Small, curated, expandable. Just enough to enable meaningful serendipity.

---

## 7. BACK-PROPAGATION / RETROACTIVE ENRICHMENT

### The Problem

You cannot pre-design tag schemas for unknown future domains. When Agent 1 generates bacteria items, it might create tags like `gram_positive`, `gram_negative`, `coccus`, `bacillus`. The system doesn't yet know these form dimensions. Old items may be missing tags that are now known to be relevant.

### The Solution: Schema-as-Data + Retroactive Enrichment

1. **All tags are flat strings** — no predefined schema
2. **Dimensions are discovered** by Agent 2 from tag co-occurrence patterns
3. **Retroactive enrichment**: When Agent 2 discovers a new dimension, it:
   - Finds ALL items in the relevant domain
   - Checks which items are MISSING tags for this dimension
   - Uses LLM to fill gaps: "Is Brachiosaurus extinct? Yes → add tag `extinct`"
   - Does NOT regenerate items — just enriches existing ones

### The Flywheel

```
Children play → Data accumulates → Agent 2 discovers dimensions →
Items enriched → Future puzzles become richer → Children explore deeper →
Agent 1 generates new domains → More data → Agent 2 discovers MORE...
```

---

## 8. IMAGE STRATEGY

### The Challenge
Images are THE learning mechanism for pre-teens. But AI-generated images across different domains (dinosaurs, bacteria, chemistry elements) must feel visually cohesive.

### Tiered Approach

| Depth | Source | Rationale |
|-------|--------|-----------|
| Depth 0-2 (animate/inanimate, animal/plant) | **Pre-built** (existing 60+ PNGs + expanded set) | High traffic, must be perfect |
| Depth 3-4 (dinosaur diet, mammal habitat) | **Pre-built + AI-augmented** | Common paths can be pre-built |
| Depth 5+ (era-specific, bacteria, chemistry) | **AI-generated on demand, cached forever** | Long-tail, write-once-read-forever |

### AI Image Generation

- **Tool**: FLUX (via FAL.ai / Replicate) or DALL-E
- **Style prompt prefix**: `"Cute, child-friendly illustration in flat vector art style, bright colors, clean lines, white background, suitable for ages 8-12."`
- **Storage**: Firebase Storage (URL in Firestore item document)
- **Cost**: ~$0.02-0.05/image, amortized across all children who ever see that item

---

## 9. LAUNCH PHILOSOPHY

### The Old Way (rejected)
Pre-design all dimensions, pre-generate all content, pre-build the entire knowledge base. Launch when "complete."

### The New Way (adopted)
Launch with the **bare minimum**, let the AI agents do the rest in production:

| Launch with | Don't launch with |
|-------------|-------------------|
| ~60 pre-built items with flat string tags | Complete tag vectors for every item |
| Puzzle Constructor (Agent 3) working | Dimension definitions (Agent 2 hasn't run yet) |
| Content Generator (Agent 1) wired up | Content beyond depth 3 |
| The grid-grouping game mechanic (existing Flutter code) | Any content outside biology/dinosaurs |
| Firestore schema for items + user progress | Play history (it accumulates after launch) |

Agent 2 (Dimension Discoverer) activates AFTER enough play data accumulates. Agent 1 fires when children reach unexplored depth. The system **gets smarter in production**.

---

## 10. IMPLEMENTATION PHASES

### Phase 1: The Lean Core (2-3 weeks)
- Refactor existing Flutter code to use flat string tags
- Build Firestore schema (items, user progress)
- Implement Puzzle Constructor (Agent 3) — simple version
- Keep 60 pre-built items as seed data
- No AI generation yet — hard stops when content runs out

### Phase 2: Agent 1 — Content Generator (2-3 weeks)
- Cloud Function: LLM-powered item + tag generation
- Image generation pipeline (FLUX/Replicate)
- Prefetch trigger (fires when child enters parent level)
- Generation status handling (loading states, fallbacks)

### Phase 3: Agent 2 — Dimension Discoverer (2-3 weeks)
- Cron-triggered Cloud Function
- Tag correlation analysis
- Dimension proposal + LLM validation
- Retroactive item enrichment (gap-filling)

### Phase 4: Serendipity & Polish (1-2 weeks)
- Adjacency map + lateral jumps
- Tree-map visualization (child's taxonomic journey)
- Multi-domain launch (chemistry, bacteria seeding)
- Parent dashboard

### Phase 5: Scale (ongoing)
- Pre-generation of popular branches
- Quality review queue for AI-generated content
- Multi-language support

---

## 11. KEY ARCHITECTURAL DECISIONS SUMMARY

| Decision | Rationale |
|----------|-----------|
| Flat string tags, not fixed schema | Cannot predict dimensions of future domains |
| Dimensions discovered by AI, not authored | System must scale beyond human ontology design |
| One intended dimension per puzzle | Avoids player confusion from multiple valid answers |
| Unexplored dimensions become explore options | Epistemological honesty — child learns taxonomy is multi-dimensional |
| Prefetch generation (fire at parent entry) | 3-8 minute latency window makes "live" generation unnecessary |
| Write-once-read-forever for generated content | One child's generated items serve all future children |
| Launch lean, enrich in production | Old way (pre-build everything) is impossible at this scale |
| Multi-agent architecture (3 agents) | Separation of concerns: generate, discover, construct |
| Serendipity injection (80/20 split) | Prevents tunneling; expands unknown-unknowns |

---

## 12. OPEN QUESTIONS / FUTURE CONSIDERATIONS

1. **Image consistency**: Can FLUX/DALL-E produce visually cohesive images across wildly different domains (dinosaur × bacteria × chemical element)?

2. **Dimension validation quality**: How to ensure Agent 2 doesn't propose dimensions that are statistically valid but taxonomically nonsensical?

3. **Cross-domain coherence**: When a child jumps from dinosaurs to chemistry, how does the system make the transition feel natural rather than jarring?

4. **Content moderation**: AI-generated content for children requires some form of review/approval before serving.

5. **Cost scaling**: Image generation cost per item × number of items generated. At launch this is negligible; at scale (10,000+ items) it needs monitoring.

6. **The "cold start" for new domains**: When the first child reaches bacteria, Agent 1 generates 16 items. But 16 items may not be enough for Agent 2 to discover rich dimensions. How many items are needed before a domain "wakes up"?

---

*This document captures discussions from June 19, 2026 between Jijil and the Hermes AI agent. It represents the architectural vision for evolving the Ishans_games_4 Flutter project into an epistemological classification engine.*
