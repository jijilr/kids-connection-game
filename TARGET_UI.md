# Target UI — the new experience (built on the old soul)

> **Status:** Design intent, 2026-06-21. **Stance:** *redo, rooted in the current
> app's soul.* The existing playful look is an asset, not debt — generic redesigns go
> dull. We carry the DNA forward and elevate it.
> Companion docs: `UI_SPEC.md` (the as-built baseline to keep) · `PRD.md` (what/why).

---

## 0. The one rule

**Never sterilise it.** A from-scratch UI tends toward flat, corporate, Material-default
greyness. That would kill this product. Every new screen must feel like it belongs in the
same warm, bouncy, candy-colored world the current app already lives in — just bigger and
more alive.

---

## 1. Design DNA — carry forward (do NOT discard)

From the current app (see `UI_SPEC.md` for exact tokens):
- **Candy palette & gradients** — pink/purple/teal/yellow, soft sunshine backgrounds.
- **Everything rounded**, soft drop shadows, no hard edges.
- **Spring motion** — `easeOutBack`, BounceIn; things overshoot and settle, they don't
  just fade. Playful physics.
- **Emoji & warmth** — 🎮🧩⭐🔥❄️ used as friendly punctuation.
- **Image-first, text-minimal** — the child may not read; pictures + audio lead.
- **Tactile feedback** — tap → scale + glow + checkmark + a spoken word.
- **Calm by design** — no countdown timers, no shame states, no dark patterns.

**Elevate (new):**
- A single **motion system** (consistent spring curves, staggered entrances, gentle idle
  "breathing" on key elements).
- A signature **connection motif** (§2) that becomes the product's visual identity.
- Richer **sound design** — every action has a soft, satisfying cue.

---

## 2. The signature motif — "threads of light"

The product's whole idea is *connection*. Make it visible.

- **Glowing threads** link things that share a part. Warm, soft, slightly animated
  (a faint travelling shimmer).
- **In the game:** when 4 items solve, threads of light briefly stitch them together
  before they collapse into the solved banner — you *see* the connection that made them
  a group.
- **In the mastery web:** the same threads, but **permanent** — the child's growing
  constellation of what they've connected.
- One visual language across game *and* reward. This is what makes it feel like one
  living thing, not a screen of buttons.

---

## 3. Screens

### 3.1 Home / "Worlds" picker
- Domains shown as floating, gently-bobbing **bubbles/islands** ("Animals 🦖", "Words 🔤",
  …), each with its own color theme drawn from the palette.
- Tapping a world zooms in with a spring transition. Locked/coming-soon worlds shimmer
  faintly (curiosity, never "buy to unlock" pressure).
- Big, wordless, image-led. A returning child sees their own mastery web preview pulsing
  on each world they've touched.

### 3.2 Puzzle round (refresh of the existing screen)
- Keep the proven grid of image cards, selection scale-0.95 + checkmark, solved banners.
- **Add the "lens" frame:** a small friendly emblem + spoken prompt for *how* to group
  this round — e.g. a 🍖 badge and "This time… find the ones that eat **meat**." Minimal
  text, big audio.
- **Solve moment:** threads of light connect the 4 → category spoken → banner bounces in.
- **The regroup twist (the magic):** when the *same* items return grouped a new way,
  celebrate it — "Same friends… a new way to see them!" — so the mind-bend feels like a
  reward, not a trick.

### 3.3 Post-round choice
Three big tactile cards (bouncy, color-coded), audio-labelled:
- ⬇️ **Go Deeper** — same branch, finer split.
- 🔀 **New Lens** — same creatures, regroup differently.
- 🎲 **Surprise Me** — a serendipity jump (~20% nudge).

### 3.4 The mastery web — the signature screen
- An organic, **zoomable, glowing constellation** of the concepts the child has mastered
  — their *own* version of the wordweb, grown by playing.
- **Node richness = mastery.** Heavily-met concepts are big, bright, many-threaded;
  lightly-seen ones are small sparks. **Nothing is greyed out — there is no empty space**
  (the schema is open; we never render "missing"). Growth only.
- **Living:** nodes breathe softly; threads shimmer. When a new connection is earned, it
  **animates in with a spark + sound** — the honest version of collection dopamine.
- **"Your web grew!"** moment after each session: the camera drifts to the freshly-lit
  node, a new thread draws itself in.
- **Printable / shareable:** one tap → a clean poster (PDF/image) for the fridge. This is
  the pride object — "look what I built," shown to a parent.
- **Time-travel:** returning later, old nodes may sprout *new* branches (the collective
  schema evolved). Surfaced as a gentle "your world has new things to discover."

### 3.5 First-run / onboarding (wordless)
- No text walls. A 20-second, show-don't-tell demo: a hand taps two things that share a
  part, a thread lights up, a cheer. The child learns the verb "connect" by watching.

---

## 4. Motion & sound system
- **Curves:** spring/`easeOutBack` for entrances; gentle ease for idle breathing.
- **Stagger:** lists/grids enter in sequence, not all at once.
- **Threads:** draw-on animation + faint travelling shimmer; fade, don't snap.
- **Sound:** soft tap, satisfying "connect" chime, warm category voice, sparkle on
  web-growth. Every action audible (audio-first child).

---

## 5. Accessibility & kid-safety (hard requirements)
- Large touch targets; full **audio narration** of anything textual.
- High contrast; colorblind-distinct group colors (don't rely on hue alone — also use the
  thread/shape).
- **No** timers that race, **no** leaderboards that shame, **no** ads/tracking.
- Calm default state; celebratory but never frantic.

---

## 6. Relationship to the other docs
- `UI_SPEC.md` = the **as-built baseline** (keep its tokens & proven components).
- This doc = the **target** the PRD's phases build toward.
- When a screen here conflicts with as-built, this doc wins — *except* on the DNA in §1,
  which both docs must honor.
