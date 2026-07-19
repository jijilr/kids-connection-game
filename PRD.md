# PRD v1.0 — The Discover-by-Connecting Learning Engine
### The build document, in parts

> **Status:** v1.0 (build-oriented rewrite) · **Date:** 2026-06-22 · **Owner:** Jijil
> Supersedes PRD v0.1 and `ARCHITECTURE.md`. Companions: `UI_SPEC.md` (as-built Flutter UI),
> `TARGET_UI.md` (design soul), `PHASE0_EXPERIMENT.md` (paper test),
> `prototype_connections.html` (working gameplay prototype — Milestone 0, done).

---

## Part 0 — Orientation (read first, especially if you are a fresh AI instance)

**The product in one paragraph.** A learning engine (not one game) where a child sorts a
4×4 grid of items into 4 hidden groups — NYT-Connections style — but solving a board is
only a *move*: the child then **descends** into the branch they read most cleanly
(sub-groups of that group), **regroups** the same items by a different dimension, or
**jumps** somewhere unexpected. Knowledge is stored as a graph; the child carves a
personal path through it; their growing, printable web of mastered ideas is both the
reward and the assessment. Mission: Khan-not-Byju's — calm, honest, anti-rote,
non-exploitative, near-zero marginal cost.

**Decisions already made — do not re-litigate:**
1. Client = **Flutter** (existing app in this repo is the seed; web + Android/iOS).
   The HTML prototype is a design bench, not the product.
2. Gameplay proven first in **text**; images enter later via the Part VI policy
   (grid-of-4 generation, intrinsic-vs-contextual backgrounds).
3. The dormant tag engine in `lib/` is **foundation, not dead code**.
4. Generator API keys (DeepSeek/Claude/OpenAI) live **server-side only** — never in
   client code.
5. Mastery = **depth and richness, never percentage-complete**. No greyed-out "missing"
   anything, no leaderboards, no time-on-app rewards, no countdown anxiety.
6. Never sterilise the UI: candy palette, springy motion, audio-first (see §7 DNA in
   `UI_SPEC.md` / `TARGET_UI.md`).
7. No destructive repo changes without the owner's explicit go-ahead.
8. **Grounding-first (anti-hallucination):** ontology + taxonomy are *retrieved* from
   authoritative sources (Wikidata + per-domain scientific authorities), never invented;
   the LLM only expands *within* that skeleton; every content atom carries provenance.
   See Part VII.0 — this is foundational, decided early on purpose.

**Core insight that shapes everything:** the knowledge is a **graph** (every entity has
many threads: clade, diet, era, size…). A *tree* is just the child's one-parent-at-a-time
**path** through it. "Descend" and "regroup" are two directions of travel on the same
graph. Overlap between groups is not a bug to eliminate — it is where the learning
lives; it only needs *controlling* (Part IV).

### Part 0.1 — External artifacts & design DNA (inlined so this file stands alone)

This PRD is meant to travel by itself. The rest of the project lives in another repo; here
is what you're missing and its essence:
- **Flutter seed app** (`Ishans_games_4` repo): a working NYT-Connections-style *picture*
  game (4×4), Provider state, deployed to GitHub Pages. Its generator currently groups only
  by `category`; a richer multi-dimensional tag engine (`GroupingDefinition`, conflict
  rules) exists but is **dormant — that is the constructor skeleton, not dead code**. ~54
  tagged animals in `items_classification.json`. Reuse its card / selection / solved-group
  UI and audio system; migrate its data into the Part II entity format.
- **`prototype_connections.html`** (Milestone 0, done): a playable *text* Connections that
  proved the loop — read-ranking, descend, and a step-through dev explorer with a live
  breadth/depth tree map. A design bench, not the shipping client.
- **`UI_SPEC.md` / `TARGET_UI.md`**: the full UI specs; their essence is inlined next.

**Design DNA — never sterilise this.** Warm, playful, candy-colored, rounded, springy,
image/audio-first, calm. A flat Material-default redesign would kill the product.
- Palette: pink `#FF6B9D`, purple `#9B6DFF`/`#6C5CE7`, teal `#4ECDC4`, yellow `#FFE66D`,
  orange `#FF8C42`; page bg sunshine gradient `#FFF9E6 → #FFE8F0`; solved-group colors
  `#E74C3C #3498DB #F1C40F #9B59B6`. Fonts: Quicksand (titles), Inter (body).
- Motion: spring / `easeOutBack`, bounce-in, gentle idle "breathing." Signature motif:
  **"threads of light"** connecting things that share a part — in play *and* in the mastery
  web. Audio for everything (kids may not read). No timers, no shame states, no dark patterns.

---

## Part I — Vision & Principles (compressed)

1. **Discover, don't instruct.** The child finds the pattern; the system supplies
   examples and structure. Minimal text, maximal pattern.
2. **The transferable skill is "find the dimension."** Sorting animals by diet, stars by
   temperature, molecules by bond type = the same cognitive move. That move — not the
   facts — is the product.
3. **Categories are provisional.** The deep levels (virus: alive? Pluto: planet?) teach
   that classifications are human-made and fray at the edges. The contested frontier is
   a feature, not a failure.
4. **Self-leveling depth.** A child descends until they start erring — the game parks
   itself at their frontier automatically. Depth reached is a *measurement*, not a score
   we assign.
5. **Knowledge graph is open and emergent.** Flat tags accrue; there is no "complete"
   list of an entity's attributes, so the map can only grow — it can never shame.
6. **Write once, read forever.** Every generated item/image/board is cached and serves
   every future child. Marginal cost per child ≈ 0. This is what lets us stay
   non-exploitative *and* sustainable.
7. **Correctness is sacred.** A wrong tag or wrong image teaches a falsehood. Human/AI
   QA gates are not optional (Part VI, VII).
8. **Grounded, not invented.** Structure and attributes are retrieved from authoritative
   sources; the LLM expands only within that skeleton; provenance is attached to every
   atom. Honest "how do we know" is both our credibility and our deepest lesson (Part VII.0).

---

## Part II — The Knowledge Model

**Entity** (the atom):
```json
{
  "id": "trex",
  "name": "T-Rex",
  "domain": "animals",
  "tags": ["dinosaur","reptile","carnivore","cretaceous","land","large","biped","extinct"],
  "facts": ["Its bite was the strongest of any land animal ever."],
  "images": { "portrait": "...", "scenes": { "era_cretaceous": "..." } },
  "provenance": {
    "entity": "wikidata:Q14332",
    "tags": { "cretaceous": "wikidata:P2348", "carnivore": "gbif:2489042", "scary": "llm:game-tag" },
    "facts": ["wikipedia:Tyrannosaurus#Feeding (llm-phrased, cited)"]
  }
}
```
- Tags are **flat strings**, open-ended, added at any time (by author, generator, or
  enrichment). No fixed schema.
- **Every atom carries provenance** (`wikidata:` / `gbif:` / domain authority /
  `llm:game-tag` / `llm:phrased+cited` / `human:verified`). Retrieved-truth and
  LLM-generated content are never blurred — this is what answers "says who?" (Part VII.0).

**Dimension** (a way of grouping):
```json
{
  "id": "diet",
  "question": "What do they eat?",
  "type": "intrinsic",            // intrinsic | contextual  ← drives image policy
  "values": { "carnivore": "Meat-eaters", "herbivore": "Plant-eaters", "omnivore": "Eats both" },
  "domains": ["animals"]
}
```
- **Intrinsic** = readable off the entity itself (kind, size, legs, color, diet-ish).
- **Contextual** = lives in the environment/time (era, habitat, ecosystem). This flag
  decides image style (Part VI) and lens mode suitability (Part III).
- Dimensions are **hand-authored now**; AI-discovered later (Part VII, deferred).

**Node** (a place in the traversal — a "board-able" set):
```json
{
  "id": "dinosaurs_by_era",
  "title": "Dinosaurs — by era",
  "parent": "animals_by_class",
  "dimension": "era",
  "groups": [ { "value": "cretaceous", "entities": ["trex","triceratops","..."] }, ... ],
  "childNodes": ["cretaceous_by_diet", "..."],
  "status": "authored | generated | pending"
}
```

**Per-child knowledge graph** (the mastery record):
```json
{
  "childId": "...",
  "encounters": { "trex": { "seen": 9, "affirmedTags": { "carnivore": 4, "cretaceous": 2 } } },
  "nodesSolved": { "dinosaurs_by_era": { "times": 2, "bestReadRank": 1 } },
  "maxDepthByBranch": { "animals": 4 },
  "dimensionsExplored": ["class","diet","era"]
}
```
This single object powers the mastery web (Part V), difficulty selection, and the
traversal suggestions.

**II.5 — Progressive enrichment (lazy hydration).** An entity is cached as a *thin slice*
at first (only the tags a shallow board needed) and **hydrated on demand**: to place entity
E on a board sorting by dimension D, E must carry a D-value; if missing, pull it from the
grounded source (Part VII.0) — or, for a non-grounded *game-tag*, generate + verify. Because
the authority already holds E's full record, this is *materializing known data, not inventing
it* ("back-propagation" is the wrong mental model — it's lazy hydration; trigger = dimension
demand, with prefetch as an optimization).
- *Additive* enrichment (E gains `era: cretaceous`) is monotonic and safe — ~95% of cases.
- *Corrective* revision (a prior tag was wrong) is non-monotonic and the genuinely hard case:
  version the entity, keep old values in history, reconcile anything built on the old value
  (see IV.4).
- **Two levels grow, never conflate them:** the entity's **canonical record** (shared,
  grounded, hydrated from the authority) vs the **child's personal model** (per-child
  `encounters` — what the mastery web draws).

---

## Part III — Gameplay

**III.1 The board (unchanged, proven):** 16 tiles, 4 hidden groups of 4. Select 4 →
Submit. Correct → group locks in with color + audio. Wrong → mistake; "one away" hint
when 3/4. Four mistakes = board ends gently (reveal + encourage — never a shame screen).

**III.2 Lens modes — the difficulty graduation (key design):**
- **Announced mode (early game, default):** the board *names* the dimension — "This
  round: sort by *what they eat*." Overlap becomes harmless (any correct partition along
  the named axis is right), the uniqueness engine can idle, and young kids aren't
  bewildered by shifting rules.
- **Silent mode (advanced):** classic Connections — discovering *which* dimension is in
  play IS the puzzle. Requires the uniqueness engine + adversarial pass (Part IV).
- Progression: a branch starts announced; after N clean solves it graduates to silent.

**III.3 Moves after solving a board:**
- ⬇️ **Descend** — into the branch the child read most cleanly (see III.4), one level
  deeper (e.g. Big cats → The cat family).
- 🔀 **Regroup** — same 16 entities, new dimension ("same creatures — now by era").
  This is the signature learning moment (mental-model rebuild).
- ↩️ **Back** — return to a parent node to take a parallel branch (breadth).
- 🎲 **Surprise** — serendipity jump to an adjacent domain (~20% nudge; adjacency map
  is hand-authored, small). *Policy for choosing jumps: open question (Part X).*

**III.4 Read-ranking (from the prototype — keep):** per solved group record
`(near-misses, solve order, time)`. Rank groups by fewest near-misses → solved earliest
→ fastest. The top-ranked group is the child's "cleanest read" and becomes the default
descend suggestion. (Navigation driver — deliberately separate from points.)

**III.5 Lifelines (inherit from current app):** Reveal-one, Category-hint (free in
announced mode — it IS the announcement), Freeze, Auto-solve (kept as a *teaching*
mode: solves one group at a time, tile-by-tile, narrated — already built in Flutter).

**III.6 Dev harness (keep, never ships to kids):** step-through auto-explorer with the
live tree map (breadth/depth/visited) — `prototype_connections.html`.

**III.7 Traversal & board shape — how you reach a specific/deep thing (fork now CLOSED:
board is fixed 4 groups × 4 tiles).** A *node* = an accumulated filter-stack + a 4-valued
active dimension; *descend* = pick one solved group → it becomes a filter → apply a new
4-valued dimension over the survivors (everyday things → [kind] → Vehicles → [medium] → Air,
where a hot-air balloon sits as a tile beside airplane/helicopter/rocket).
- **The tree is WIDE and SHALLOW.** Pure narrowing bottoms out fast at the recognition ceiling
  (IV.3) — you rarely find 16 recognizable things that split 4×4 more than ~2–3 filters deep.
  So a *specific* entity (air balloon) is reached as a **tile** on the deepest board that still
  has 16 recognizable members, *not* as a destination node you tunnel into (there aren't 16
  balloon-types).
- **Depth = compound dimensions, not obscurity.** "Advanced" boards stay 4×4 by *combining*
  axes over the familiar cast: dinosaurs by era × diet → {Jurassic-carnivore, Jurassic-herbivore,
  Cretaceous-carnivore, Cretaceous-herbivore}; flight by origin × power → {man-made powered;
  man-made unpowered (balloon, glider, parachute, kite); natural powered (bird, bat, bee);
  natural unpowered (dandelion seed, flying squirrel, spider-ballooning)}. Difficulty rises with
  the number of axes to track, not with entity obscurity — and this is where the deep,
  non-obvious cross-category insights live (a balloon shares *unpowered flight* with a dandelion
  seed).
- **Mastery of a specific entity is not a destination — it's the accumulation of every board it
  appeared on** (→ the mastery web). You reach specificity by re-cutting the recognizable world
  from every angle, not by tunnelling.

---

## Part IV — Board Construction & the Overlap Problem

**The rule:** overlap between candidate groups is *fine* — required, even (it's where
learning lives) — **as long as exactly one solution exists for the mode being played.**

**IV.1 Validity (both modes):** 16 entities, 4 groups × 4, each entity belongs to
exactly one *intended* group; every group has a display label and (announced mode) a
dimension value.

**IV.2 Uniqueness (silent mode only):**
1. Uniqueness is checked **only against the board's declared active-dimension set**
   (e.g. {class, diet, era}) — not against every conceivable shared property, which
   would make every board "ambiguous." Declaring active dimensions = declaring what this
   round teaches.
2. Constructor: pick intended dimension → pick 4 value-groups → fill disjointly
   (most-constrained first) → check the other active dimensions for accidental clean
   partitions → if found, **swap in poison items** that break the alternative → retry
   N times → if still ambiguous, *fall back to announced mode* (graceful, always
   available).
3. **Adversarial "clever-kid" pass (AI):** an LLM sees the 16 items (later: the images
   too) and lists every grouping a sharp child might attempt — including untagged
   visual/cultural ones (stripes, "all scary," "all in cartoons"). Each finding is
   either closed (swap a tile) or promoted to an accepted alternative answer. This is a
   *real* AI job: it models the knowledge a child brings that our tags don't.
4. Contextual-dimension caution: when the answer is visible in the background (era
   scenes), a child can sort by scenery without learning the *connection*. Prefer
   announced mode or a different mechanic (timeline placement) for those dimensions.

**IV.3 Ordering & the two depth ceilings** (found by stress-test: "Jurassic dinosaurs by diet").
- **Order every node by fame first.** Rank a node's members by recognizability (Wikidata
  sitelinks / pageviews = retrievable proxy) so the **first board is always its most mundane,
  canonical members** (Allosaurus & Stegosaurus, not Yangchuanosaurus). Mundane-first is
  *correct*: recognition is the prerequisite for the lesson (the new *dimension*). Famous
  creatures reappearing from the descent aren't redundancy — they're the regroup payload
  (familiar faces, new question) — *provided the constructor picks a dimension the child hasn't
  applied to that cast yet* (mastery graph enables this).
- **Combinatorial ceiling:** deeper = more-similar entities = fewer clean 4×4 cuts. Narrow deep
  nodes force **compound dimensions** (diet × size → big/small × meat/plant = 4 groups) — a real
  sophistication escalation and the answer to "how do you make 4 groups that deep." (Note: there
  aren't even 16 *famous* Jurassic dinosaurs, and they skew herbivore — the mundane pool is
  genuinely thin at depth.)
- **Recognition ceiling (lower, sharper):** past the famous cast, entities become unrecognizable
  and classification-by-recognition breaks — at the extreme, sorting obscure genera by *memorized
  fact* IS the rote-learning we oppose. So **depth is dimensional, not entity-novelty:** re-cut a
  roughly-stable *recognizable* cast through more/compound dimensions; obscurity is an opt-in
  enthusiast thread, never the main loop. The recognition ceiling *is* the self-leveling frontier
  (the child halts where creatures stop being recognizable = their knowledge edge) — healthy,
  **unless scoring rewards depth-for-its-own-sake and pushes them past it (see V.1).**
- When no valid board exists at all, surface the frontier as "🌱 the edge of what's known here"
  (later, the generator's cue to grow content).

**IV.4 Enrichment ↔ uniqueness (subtle — don't miss it):** adding a tag to an entity can
retroactively give an *already-cached* board a second valid solution (T-Rex gaining `era`
makes an old board also solvable by era). So every board stores the **tag-snapshot it was
validated against**; announced-mode boards are immune (the lens is named); silent-mode
boards re-verify — or simply regenerate — when a relevant tag changed. Progressive
enrichment (II.5) is not free; it couples to the constructor. **Cleaner resolution (VI.0):
don't cache boards at all — cache the grounded graph and assemble boards fresh, so staleness
can't accrue.** Snapshotting is only a fallback if board-construction cost ever bites.

---

## Part V — Scoring, Progression & the Mastery Web

Two layers, deliberately separate. **Points are for the session. Mastery is forever.**
Points may never gate content; mastery may never decay.

**V.1 Session score (per board — inherits & adjusts current Flutter values):**
| Event | Points |
|---|---|
| Group solved | +100 |
| Streak bonus (consecutive correct submits within the board) | +50 × (streak−1) |
| Mistake | −25 (floor 0) |
| Perfect board (0 mistakes) | +500 |
| Lifeline used | −50 (Freeze free; hint free in announced mode) |
| **Depth multiplier** | ×(1 + 0.25·depth) applied to the *quality* of the solve (clean / low-mistake), **NOT** to mere presence at depth. You cannot farm points by reaching or guessing through deep boards of creatures you don't recognize — depth rewards *understanding shown*, never depth itself. This keeps the recognition ceiling (IV.3) a healthy self-leveling stop instead of a rote-farming incentive. |
| Regroup bonus (solving the *same* entities under a 2nd+ dimension) | +150 |

The regroup bonus is the values statement in number form: we pay most for *re-seeing
the same things a new way* — the exact anti-rote behavior we exist to teach.

**V.2 What persists (device-local first):** high score, boards solved, per-branch max
depth, dimensions explored, the per-child knowledge graph (Part II). **Explicitly
banned:** daily-login streaks, global leaderboards, time-based bonuses, paywalled
score boosts.

**V.3 Read-quality (navigation, not points):** the III.4 ranking. Shown after each
board as "your cleanest read ★" — informative pride, no point value, so kids aren't
punished for exploring sloppily.

**V.4 The mastery web (the real reward):** the child's knowledge graph rendered as a
living, zoomable, **printable** web (poster/PDF) — entities as nodes sized by
encounter-richness, threads for affirmed connections, branches lighting up as depth
grows. No empty slots ever shown; returning children may find old nodes grew new
branches (schema evolved). Session end: "your web grew — +3 connections" moment,
camera drifting to the new nodes.

**V.5 Ratings (keep, gentle):** per-board stars by mistakes (0 → ⭐⭐⭐, 1 → ⭐⭐, ≤2 → ⭐,
else "Completed!").

---

## Part VI — Content & Image Pipeline

**VI.0 — Demand-paged growth (start lean, grow with play). The core capital-efficiency
mechanism and the real moat.** The knowledge graph is *demand-paged*, like virtual memory:
seed one domain tiny, then **page in** (retrieve / hydrate / generate) only the entities,
tags, and dimensions a child's path actually touches — cached write-once for every future
child. You never pay to build the untraveled graph; the union of all paths grows the corpus
weighted by what kids actually want.
- **Cache the GRAPH, not the boards.** A board is a cheap deterministic function of the
  cached graph (entities × dimension × seed → combinatorics), so *assemble boards fresh on
  demand* rather than storing puzzles. This supersedes IV.4's snapshotting: enrichment flows
  into new boards automatically and boards can't go stale. Cache the expensive grounded atoms
  (entities, tags, images, adversarial verdicts keyed by board-signature); recompute the cheap
  layout.
- **Fast path / slow path.** The first child to reach an unbuilt deep node gets an *instant*
  grounded **text, announced-mode** board (retrieval + combinatorics — no LLM, no image).
  Images, silent-mode uniqueness, phrasing, and the adversarial pass enrich the node **in the
  background** for the next visitor. The node improves per visit — "no rich data early on" made
  literal.
- **Prefetch generously (the read-ranking is your predictor).** While a child plays board N,
  pre-warm the 2–3 most-likely next branches, ranked by their cleanest-read group (= probable
  descent). A *mispredicted* content-prefetch is never *globally* wasted — a branch this child
  skips is cached for the next child who takes it (locally mistimed, globally always useful) —
  so prefetch wide. A separate **low-priority background sweep** pre-warms a *grounded* dimension
  across the pool once first used (cheap batch retrieval only — never the costly generated
  layer). Single-canonical-record (cache-the-graph) means there are **no duplicate instances to
  sync** — enrich the one record and every future board is current.
- **The seed is retrieved, not authored.** One Wikidata query seeds a domain with hundreds of
  grounded entities+tags. Invest in the *pipeline (the pump)*, not a content warehouse (the
  water): retrieve → verify → cache → construct → serve → enrich.
- **The moat is the disciplined pipeline, not the algorithm.** Verified-only cache (nothing
  served unverified, so errors can't propagate) + canonical dimension registry (so lazily-
  hydrated tags compose, not fragment) + grounded-not-generated structure + provenance. A
  casual clone generates boards live and ships hallucinations; the durable asset is the
  *trustworthy, usage-shaped, compounding* corpus this produces.
- **Two flywheels:** coverage (popular paths built once, then free — cost/child falls as the
  hot subgraph saturates) and quality (play data flags confusing / too-easy / too-hard boards
  → auto-curation). The corpus gets bigger *and* better with use.

**VI.1 Content flow:** seed a domain by *retrieval* (Wikidata/authority query) + light
hand-curation (the existing 54 animals migrate in) → validate (schema + fact QA) → boards
assembled fresh per VI.0 → at an unbuilt frontier the **generator** (Part VII) pages in the
next node's entities/tags → verify gate → cached forever.

**VI.2 Image policy — keyed to (entity × dimension-type),** the settled design:

| Tier | What | Generation | Background | Reuse |
|---|---|---|---|---|
| **Portraits** (intrinsic dims — the workhorse) | 1 neutral portrait per entity (+1 spare for common entities, anti-memorization) | **Grid-of-4 different entities per call**, cut into 4 (cost-efficient; safe because backgrounds are uniformly blank/neutral — no style leakage) | Strictly identical flat/neutral | Serves *every* intrinsic dimension, every board, forever |
| **Scenes** (contextual dims: era, habitat) | Per-board scene images | **Grid-of-4 same-scene** (4 creatures sharing one Cretaceous world in one call — cheaper *and* more correct, shared scene is the point) | The scene IS the content | Low (that dimension only) — generate lazily, only when such a board is built |
| **Heroes** (frequently-met entities) | Full-res single + variants | Singles | Neutral | High; powers a "look closer" zoom view |

- **Style contract (rigid):** identical prompt prefix; isolated subject; flat neutral
  ground for portraits; child-friendly illustration style; ~512px per delivered tile
  (grid generated at full model res, cut with Pillow).
- **QA gate (non-negotiable):** reject wrong anatomy/color/subject-blend (a 6-legged
  spider teaches a falsehood), misaligned grid cuts, style drift. Budget a reject/retry
  tax. Human spot-check for anything child-facing.
- **Prefetch:** the tree-map's "to-do" nodes double as the image/generation work queue —
  generate a node's assets while the child plays its parent, so Descend feels instant.
- Pipeline is **offline/server tooling** (Python + OpenAI SDK + Pillow). Never in-app.

**VI.3 Audio (inherit):** existing Flutter sound system + assets (names, categories,
feedback, encouragement) carries over; new entities get name/fact audio in the same
folder scheme.

---

## Part VII — AI Services (server-side, each with one honest job)

**VII.0 — Grounding & provenance (the anti-hallucination foundation; read first).**
The engine does not *invent* knowledge — it *retrieves a skeleton and expands within it*.
- **Retrieve the skeleton** per domain from authorities: **Wikidata** as the universal
  backbone (structured is-a / has-property graph, cited, CC0), plus domain gold-standards —
  **GBIF / Catalogue of Life** (life), **IUPAC + periodic table** (chemistry),
  **Morgan–Keenan / IAU** (stars). This yields entities, subclass/instance edges, and typed
  attributes as *grounded* tags.
- **Bound the LLM's freedom.** It MAY: curate boards from grounded entities; phrase
  kid-friendly facts *cited back to a source*; propose *subjective game-tags* that were
  never truth-claims ("looks scary", "kids love these"); write image prompts. It MAY NOT:
  mint an is-a edge, or assert an attribute the game treats as fact, from nothing. (This is
  RAG over a knowledge graph — the model is a curator/translator, not a witness.)
- **Provenance on every atom** (Part II): any claim answers "says who?" — both the defense
  to a skeptical parent/school and, surfaced to the child at the frontier ("scientists
  don't fully agree here"), the deepest lesson. *Retrieve the ontology, retrieve the
  taxonomy, make the epistemology visible.*
- **Hold two layers on purpose:** grounded scientific truth (correctness/defense) *and* a
  folk/intuitive layer the game plays in (whale as "sea animal"); the **gap between them is
  a lesson**, not a bug. Don't let the scientific tree straitjacket the fun.
- **Frame-ambiguity is a feature; factual error is not.** An entity may hold conflicting tags
  across *named frames* (tomato = `fruit[botanical]` + `vegetable[culinary / Nix v. Hedden]`) —
  under announced mode *both* sorts are correct, and the delayed collision teaches "categories
  are convenience, not law." Designed, not a bug. But a plain error (spider ≠ insect) still
  teaches a falsehood: fix it (optionally as "scientists updated their thinking"), never shrug.
  **Rigor on facts earns the license to be playful with frames** — sloppiness and provisionality
  look identical from outside; only earned trust distinguishes them.
- **Provenance conflicts auto-surface the best lessons.** Where two grounded sources disagree
  about an entity, don't reconcile it away — flag it as a "why do people classify this
  differently?" node. The disagreements *are* content; mine them.
- **Licensing:** prefer Wikidata (CC0) + the LLM's own phrasing cited to source over
  copying Wikipedia prose (CC-BY-SA share-alike). **Freshness:** snapshot the skeleton,
  refresh periodically (content is cached forever anyway). Risk is low at shallow/common
  depth and rises with depth/obscurity — ground hardest deep, but build the provenance
  plumbing from day one.

| Service | Job | When | Model |
|---|---|---|---|
| **Node generator** | Given a parent node + dimension, produce 16 entities w/ tags, labels, facts, image prompts | Child nears frontier (prefetch) | DeepSeek/Claude — key server-side |
| **Clever-kid adversary** | List every grouping a sharp child might see in a candidate board | Silent-mode board construction | Same |
| **Fact/tag QA** | Verify generated tags/facts before caching | Post-generation | Same + human spot-check |
| **Dimension discovery** | Cluster co-occurring tags into new dimensions | **Deferred** — hand-author until data volume demands it | — |

Thin backend (Cloud Function / tiny VPS): `/node/generate`, `/board/construct`,
`/images/enqueue`. Client stays offline-capable on cached content.

---

## Part VIII — Architecture

- **Client:** Flutter (this repo). Provider state mgmt as-is. Screens: Board,
  Post-solve (moves), Mastery Web, Worlds picker. Dev harness stays HTML.
- **Content store:** bundled JSON seed + local cache of fetched nodes/images
  (offline-first); cloud sync later.
- **Backend:** the three endpoints above + static image hosting (CDN). Keys server-side.
- **Repo hygiene:** keep `GroupingDefinition`/conflict logic as the constructor's
  skeleton; `items_classification.json` migrates into the Part II entity format.

---

## Part IX — Build Plan (milestones with acceptance criteria)

**M0 — Gameplay prototype ✅ done.** `prototype_connections.html`: playable text
Connections, read-ranking, descend, step-through explorer, breadth/depth map.

**M1 — Flutter text core (1–2 wks).** Port the loop into the Flutter app: text tiles
(reuse card/selection/solved-group UI), announced-lens label, read-ranking, descend +
back moves, 2-level hand-authored animal tree (~40 nodes-worth of entities).
✔ *Done when: a child can play root→branch→back on a phone, text-only, offline.*

**M2 — Score & persistence (days).** Part V.1 table incl. depth multiplier + regroup
bonus; stars; device-local stats + knowledge-graph recording (encounters, depth).
✔ *Done when: score behaves per table; kill the app, stats survive.*

**M3 — Regroup & silent mode v1 (1 wk).** Regroup move on solved boards; graduation
announced→silent per branch; constructor with active-dimension uniqueness + poison
swaps (no LLM yet); graceful fallback to announced.
✔ *Done when: same 16 entities solvable under 2 dimensions; no silent board ships with
a second valid partition within its active set.*

**M4 — Backend generator (1–2 wks).** Node-generation + QA endpoints (DeepSeek key
server-side); frontier detection + prefetch; generated nodes cached and replayable by
every user.
✔ *Done when: a child exhausts authored content and descends into a generated node
without noticing the seam.*

**M5 — Images (1–2 wks).** Pillow grid-cutter + style contract; portrait tier for all
entities (grid-of-4-different); hero zoom for top ~20; scene tier for one contextual
dimension (era) behind announced mode; QA queue.
✔ *Done when: boards render image tiles from cache; no board mixes portrait/scene
tiers; zero uncut/misaligned tiles shipped.*

**M6 — Mastery web (1 wk).** Living web view from the knowledge graph; "your web grew"
session-end moment; print/PDF poster export.
✔ *Done when: a kid can print their web and pin it on a fridge.*

**M7 — Clever-kid pass + polish (1 wk).** Adversarial check wired into silent-mode
construction; audio for new entities; onboarding (wordless demo).

**M8 — Second domain (proof of engine-ness).** Author a words/etymology or space seed
tree reusing *unchanged* engine code. ✔ *Done when: zero engine code changes needed.*

*Sequencing rationale: kid-visible value first (M1–M3 playable & fun), infrastructure
only after fun is proven (M4+), images after gameplay (M5), exactly per the settled
decisions.*

---

## Part X — Metrics, Risks, Open Questions

**Success metrics (learning, not engagement):** transfer (child solves an unseen
board's dimension unaided), regroup success rate, voluntary return, depth frontier
advancing over weeks, mastery-web growth. **Never optimized:** session length.

**Top risks:** content correctness at scale (mitigation: QA gates, human spot-check) ·
silent-mode unfairness from untagged kid-knowledge (mitigation: clever-kid pass,
announced fallback) · reward layer curdling into engagement farming (mitigation: Part V
bans, review every mechanic against "does this reward understanding?") · image style
drift creating false signals (mitigation: style contract + reject tax).

**Open questions:** serendipity-jump selection policy · when a branch graduates
announced→silent (fixed N or per-child?) · scene-dimension mechanics beyond sorting
(timeline?) · product name.

---

*Living document. Next action: M1.*
