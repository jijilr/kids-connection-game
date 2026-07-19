# BUILD PLAN — actionable implementation plan
### Companion to PRD.md (the "what/why"). This is the "how / in what order, concretely."

> **Date:** 2026-06-22 · **Two locked constraints for this phase:**
> 1. **No image API yet** — text-only tiles. (OpenAI image generation deferred; PRD Part VI stands for later.)
> 2. **DeepSeek is the LLM**, used first as a **dev-time content generator** (a script that
>    writes verified JSON, baked into the app) — *not* a runtime service. Runtime/demand-paged
>    generation is a later phase.
>
> Everything here honors the settled design: 4×4 fixed, filter-stack traversal (descend / regroup
> / back), announced-lens default, read-ranking descent, grounded-not-invented + provenance,
> cache-the-graph, accuracy-gated depth scoring.

---

## 1. Stack & where DeepSeek sits

- **Client:** Flutter (existing repo), Provider state. Reuse the prototype's proven loop + the
  app's card / selection / solved-group UI + audio.
- **Data:** plain JSON, **bundled** with the app (offline). Two files per domain: `entities.json`,
  `dimensions.json`. No database, no server this phase.
- **DeepSeek = dev-time tool.** A small **Python** script (`tools/generate/`) calls the DeepSeek
  API (OpenAI-compatible endpoint: `base_url=https://api.deepseek.com`, model `deepseek-chat`, via
  the `openai` SDK) to generate + verify entities/dimensions, writing validated JSON. Key lives in
  a local `.env` (git-ignored) — **never** in the app or committed.
- **No image pipeline, no backend, no Wikidata ingestion yet** — all deferred (§6).

```
Flutter app  ──reads──▶  assets/data/animals/entities.json + dimensions.json
                                     ▲
                                     │ baked in (checked into repo)
tools/generate/*.py  ──DeepSeek──▶  generates + verifies the JSON   (run by a developer, offline)
```

---

## 2. Data contracts (build these first — everything depends on them)

**`dimensions.json`** — the canonical registry (so lazily-added tags always compose):
```json
{
  "category":  { "type": "intrinsic", "arity": "n", "question": "What kind of thing is it?",
                 "values": { "mammal":"Mammals", "bird":"Birds", "fish":"Fish", "insect":"Insects" } },
  "diet":      { "type": "intrinsic", "arity": 3, "question": "What does it eat?",
                 "values": { "carnivore":"Meat-eaters", "herbivore":"Plant-eaters", "omnivore":"Eats both" } },
  "habitat":   { "type": "contextual", "arity": 2, "values": { "land":"Land", "water":"Water" } }
}
```

**`entities.json`** — the graph (per PRD II, minus images this phase):
```json
{ "id":"trex", "name":"T-Rex", "domain":"animals",
  "tags": ["dinosaur","reptile","carnivore","cretaceous","land","large","biped","extinct"],
  "facts": ["Its bite was the strongest of any land animal ever."],
  "recognizability": 0.95,                          // DeepSeek-scored stand-in for Wikidata fame (§3)
  "provenance": { "entity":"deepseek:generated+verified",
                  "tags": { "carnivore":"deepseek:verified", "scary":"deepseek:game-tag" } } }
```
- **`recognizability`** (0–1) is the fame-ordering signal (PRD IV.3) until Wikidata grounding lands —
  DeepSeek scores "how recognizable to an 8-year-old." Drives first-board / mundane-first ordering.
- **Dart side:** one `Entity` model + a `DimensionRegistry`; migrate the existing
  `items_classification.json` (54 animals) into this format as the initial hand-seed.

---

## 3. The DeepSeek generation pipeline (`tools/generate/`)

**Job (bounded per PRD VII.0):** DeepSeek *curates and phrases*, it does not invent structure it
can't defend. For this phase (no Wikidata yet), it generates candidate content **and self-verifies**;
provenance is stamped `deepseek:generated+verified`. Wikidata grounding is the hardening step (§6).

**Two scripts:**
1. `gen_entities.py --domain animals --seed-tags "..."` → asks DeepSeek for N entities with flat
   tags + 1–2 kid facts + `recognizability` + proposed dimensions. Output validated against the
   JSON schema (pydantic). Anything failing schema/verify is dropped, not shipped.
2. `verify.py` → a **second, independent DeepSeek pass** (the cheap QA gate): "here is an entity and
   its tags — flag any tag that is factually wrong for a child (spider≠insect)." Rejects/queues
   failures. This two-pass generate→verify is the discipline that keeps the corpus trustworthy.

**Contract (input → output):**
```
IN:  { domain, optional filter (tag constraints), target dimension | "propose" }
OUT: { entities:[{name,tags,facts,recognizability}], dimensions:[{key,values}] }   // validated JSON
```
- Board *construction* stays **local, deterministic, no LLM** (combinatorics over the JSON) — DeepSeek
  only makes the *content*. (The clever-kid adversarial pass, PRD IV.2, is added at Phase 4 for silent
  mode — also DeepSeek, dev-time or on-demand.)
- Cost is trivial (text only, run occasionally in dev) — no budget concern this phase.

---

## 4. Phases (each ends with a concrete "done when")

**P1 — Flutter text core (the vertical slice; no DeepSeek yet).**
Port the prototype loop into the app on the **hand-migrated 54 animals**: 4×4 text tiles (reuse card
UI), select/submit/solve, solved-group banners, **read-ranking**, **descend** (pick a solved group →
filter → new 4-valued dimension over survivors), **back**, **announced-lens** label. Board assembled
fresh from the entity+dimension JSON (cache-the-graph).
✔ *Done when: a child plays root → descend → back on a phone, text-only, offline, from bundled JSON.*

**P2 — DeepSeek content pump (`tools/generate/`).**
Build the two scripts (§3); generate + verify an expanded animals set (aim ~150 entities, richer tags,
5–8 dimensions incl. a couple of compound-ready ones). Bake the output in, replacing the hand-seed.
**Pre-warm the *popular core* (Animals, Mammals, Big cats…) so no common board is ever 4-choose-4** —
the first player still gets varied boards; let demand-paging's cold-start thinness fall only in the
rare long tail (§6 / PRD VI.0). Pool size turns a fixed board (4C4 = 1) into a varied one (4C16 = 1820).
✔ *Done when: the app runs on DeepSeek-generated, verified data; regenerating is one command; no tag
fails a spot-check.*

**P3 — Score, persistence, mastery tracking.**
PRD V.1 scoring with **accuracy-gated depth multiplier** (no rote-farming); device-local stats
(`shared_preferences`) + per-child `encounters` recording (which entities/dimensions met).
✔ *Done when: score matches the V.1 table; app killed & reopened, stats + encounters survive.*

**P4 — Regroup, compound dimensions, silent mode + adversarial.**
Regroup move (same 16, new dimension — constructor prefers an un-applied dimension via `encounters`);
**compound dimensions** for "advanced" boards (era × diet); announced→silent graduation per branch;
uniqueness constructor (active-dimension set + poison swaps) + **DeepSeek clever-kid adversarial pass**.
✔ *Done when: same 16 solvable under 2 dimensions; a compound board builds; no silent board ships with
a second valid solution in its active set.*

**P5 — Mastery web (text).**
Living, printable web from the `encounters` graph (nodes = entities met, threads = affirmed
dimensions); "your web grew" moment. Text/emoji tiles for now (real images later).
✔ *Done when: a child can view + print their web.*

---

## 5. Start here — the first vertical slice (do this before anything else)

1. Define the Dart `Entity` + `DimensionRegistry` models (§2).
2. Write `assets/data/animals/dimensions.json` (hand, ~5 dimensions) and migrate the 54 animals into
   `entities.json` (hand).
3. Board assembler: given (filter, dimension) → pick 4 values × 4 recognizable entities → 16 tiles.
4. Wire into the existing game screen: render text tiles, keep select/submit/solve, add the descend
   move (tap a solved group → new board from filter+next dimension) and an announced-lens label.
5. Play it on a device.

This is P1 and it needs **zero DeepSeek and zero new infrastructure** — pure Flutter over bundled
JSON. It's the fastest path to something a kid can touch, and it de-risks the loop before we point
DeepSeek at content growth.

---

## 6. Explicitly deferred (and why)

| Deferred | Until | Why |
|---|---|---|
| OpenAI image generation | after text loop proven | your call; text tests the learning bet more cleanly |
| Runtime / demand-paged generation + backend | after content model proven (post-P4) | dev-time generation is far simpler and enough to build with |
| Wikidata / GBIF grounding | hardening pass | DeepSeek generate+verify is enough to move; grounding is the credibility upgrade, layer it in without changing the schema (provenance fields already there) |
| Serendipity jumps, worlds picker, onboarding, 2nd domain | post-P5 | not on the critical path to "is it fun?" |

---

## 7. Repo layout (additions)

```
lib/
  models/ entity.dart, dimension.dart          # new data model
  services/ board_assembler.dart               # local, deterministic 4×4 construction
  ...                                          # existing game_screen/providers reused
assets/data/animals/ entities.json, dimensions.json
tools/generate/ gen_entities.py, verify.py, schema.py, .env(gitignored), requirements.txt
```

---

*Next action: P1, step 1 — the Dart data models + JSON migration. Nothing needs DeepSeek or a network
call to begin.*
