# UI Specification — Current App (as built)

> **Status:** Reverse-engineered from the existing Flutter code, 2026-06-21.
> **Purpose:** Concrete, implementation-ready description of the CURRENT UI so a
> developer or AI agent can rebuild or extend it without reading the source.
> Companion to `PRD.md` (which covers *what/why*; this covers *exactly what the screen is*).
> Source files: `lib/main.dart`, `lib/screens/game_screen.dart`,
> `lib/widgets/item_card.dart`, `lib/widgets/solved_group_card.dart`.

---

## 1. Tech & libraries

- **Flutter**, Material 3, `useMaterial3: true`. State via **Provider** (`ChangeNotifier`).
- **Fonts (google_fonts):** `Quicksand` = titles & group names; `Inter` = scores,
  labels, buttons, banners. App theme default text = Quicksand.
- **Animations (`animate_do`):** `FadeIn`, `FadeInDown`, `FadeInUp`, `BounceInDown`, `Pulse`.
- **Color scheme:** seeded from primaryPurple, light brightness.

---

## 2. Design tokens

### Palette (hex)
| Token | Hex | Use |
|---|---|---|
| primaryPink | `#FF6B9D` | accents / fun gradient |
| primaryPurple | `#9B6DFF` | theme primary |
| primaryBlue | `#4ECDC4` | accents |
| primaryYellow | `#FFE66D` | accents / revealed cards |
| primaryOrange | `#FF8C42` | accents |
| cardSelected | `#6C5CE7` | selected card / checkmark |
| textPrimary | `#2D3436` | body text |
| backgroundStart | `#E8F5FF` | scaffold bg |
| backgroundEnd | `#FFF0F5` | bg |

### Gradients
- **sunshineGradient** (page bg): `#FFF9E6 → #FFE8F0`, top→bottom.
- **funGradient**: pink→purple→blue, topLeft→bottomRight.
- **App-bar / wide-screen backdrop**: `#667eea → #764ba2` (+ `#f093fb` on wide bg).
- **Selected card**: `#6C5CE7 → #A29BFE`, TL→BR.
- **Normal card**: `#FFFFFF → #F8F9FA`, TL→BR.
- **Revealed card**: `#FFE66D → #FFD93D`, TL→BR.
- **Streak chip**: `#FF6B6B → #FFE66D`.

### Group colors (solved groups, in order)
`#E74C3C` (red) · `#3498DB` (blue) · `#F1C40F` (yellow) · `#9B59B6` (purple).

### Radii / spacing / shadow conventions
- Card radius 16 (inner image clip 14); solved-group & big buttons radius 20–25;
  lifeline buttons radius 12; chips radius 20.
- Grid spacing `clamp(6,10)` px; outer padding `clamp(8,16)` px (scale with width).
- Shadows: selected/revealed cards glow (blur 12, spread 2) in their accent color;
  normal cards subtle black @8% (blur 6).

---

## 3. App shell & responsive behavior (`ResponsiveWrapper`)

- **mobileMaxWidth = 600**, **contentMaxWidth = 480**.
- **Width ≤ 600 (phone):** full-bleed; background = sunshineGradient.
- **Width > 600 (desktop/tablet):** centered "phone frame":
  - Backdrop gradient `#667eea → #764ba2 → #f093fb` (TL→BR).
  - Inner container: width = contentMaxWidth; if width > 900, width =
    `(screenWidth * 0.4).clamp(480, 550)`. Rounded 30, sunshineGradient fill,
    drop shadow (black @20%, blur 30, spread 5), maxHeight 95% of screen,
    vertical margin 20, clipped (antiAlias).

---

## 4. Screen: Game (main play screen)

`Scaffold` (transparent bg). Vertical layout, top → bottom:

### 4.1 App bar
- Transparent bar with gradient `flexibleSpace` (`#667eea → #764ba2`), elevation 0.
- **Title (centered):** `🎮` (24) · "CONNECTIONS" (Quicksand, w800, 22, letterSpacing 2,
  white) · `🧩` (24).
- **Action (right):** refresh icon (white) inside a white@20% rounded-12 box →
  stops audio + starts a new game.

### 4.2 Score bar (`padding h16 v8`, Row spaceBetween)
- **Left:** "SCORE" (Inter, 10, w600, grey, letterSpacing 1) over value
  (Inter, 24, w900, black).
- **Center (only if streak > 0):** chip — streak gradient, radius 20,
  `local_fire_department` icon (white, 18) + "{n}x" (Inter, 14, w800, white). FadeIn.
- **Right:** "HIGH SCORE" (same label style) over value (Inter, 18, w700, amber 700).
- Followed by a 1px `Divider`.

### 4.3 Conditional banners (stacked, full width)
- **Hint banner** (when a hint is active): amber.100 bg, `lightbulb` (amber) + hint
  text (Inter, w600, amber.900) + close button. FadeIn.
- **Freeze indicator** (when freeze active): blue.100 bg, centered `ac_unit` (blue) +
  "FREEZE ACTIVE - Next mistake won't count!" (Inter, w600, 12, blue.900). FadeIn.

### 4.4 Play area (scrollable, `Expanded`)
1. **Solved group cards** (see §5.2), newest stacking down.
2. **Item grid** — `GridView`, square cards (`childAspectRatio 1.0`),
   `crossAxisCount = 4` (→ **3** if width < 280), spacing `clamp(6,10)`,
   non-scrolling (parent scrolls).

### 4.5 Lifeline bar (`bg grey.50`, top border grey.200, `padding h16 v8`, spaceEvenly)
Four buttons (AnimatedContainer 200ms, padding h12 v8, radius 12):

| Label | Icon | Color | Default count | Behavior |
|---|---|---|---|---|
| Reveal | `lightbulb_outline` | amber | 1 | glows one correct item per unsolved group; snackbar |
| Hint | `help_outline` | purple | 2 | shows a random unsolved group's name as hint banner |
| Freeze | `ac_unit` | blue | 1 | next wrong answer doesn't count; snackbar |
| Solve All | `auto_fix_high` | green | 1 | animated auto-solve of all remaining groups |

Each: icon (24) with a small **count badge** (top-right, filled circle, white number).
States — **disabled:** greyed (icon/label/badge grey, grey border); **active:** color@20%
bg + 2px color border (used by Freeze when active, Solve All while running; label → "...").

### 4.6 Controls (`padding 16`)
- **Mistakes row:** "Mistakes remaining:" (Inter, w500) + 4 dots (`CircleAvatar`
  radius 6): filled `black87` for remaining, `grey.300` for used.
- **Button row (centered):**
  - **Deselect all** — OutlinedButton, rounded 20, black fg; disabled when nothing selected.
  - **Shuffle** — OutlinedButton, rounded 20, black fg; reshuffles unsolved items.
  - **Submit** — ElevatedButton, black bg / white fg, rounded 20; **enabled only when
    exactly 4 selected**.

---

## 5. Components

### 5.1 Item card (`ItemCard`) — square, AnimatedContainer 250ms `easeOutBack`
- **Content:** `Image.asset(item.imagePath)` (`BoxFit.contain`, padding 8). Error →
  `image_not_supported_rounded` (grey).
- **Normal:** white→#F8F9FA gradient, 1px grey@10% border, subtle shadow.
- **Selected:** purple gradient, **scale 0.95**, white@50% 3px border, purple glow;
  **checkmark badge** bottom-right (white circle, `check_rounded` #6C5CE7, 16).
- **Revealed (lifeline):** yellow gradient, orange (`#FF9F43`) 3px border, yellow glow;
  **sparkle badge** top-right (`#FF6B6B` box, `auto_awesome` white, 14).

### 5.2 Solved group card (`SolvedGroupCard`) — full width, radius 20, BounceInDown 600ms
- Gradient: lighter→full group color; colored shadow (color@40%, blur 12); white@30% 2px border.
- **Row 1:** ⭐ + group name (UPPERCASE, Quicksand, w800, size `clamp(14,18)`, white,
  soft shadow) + ⭐.
- **Row 2:** item names joined by " • " (Quicksand, w600, `clamp(10,13)`, white@90%,
  1 line ellipsis).
- **Row 3:** `Wrap` of item images in white rounded-12 bubbles, size `clamp(35,50)`, padding 4.

---

## 6. Screen: Victory (all 4 groups solved)
Centered column, animate_do staggered (delays 200/400/600/800ms):
- **Rating** (FadeInDown): one of `⭐⭐⭐ PERFECT!` / `⭐⭐ GREAT!` / `⭐ GOOD!` /
  `COMPLETED!` (Inter, 32, w900, amber.700) — based on mistakes (0/1/≤2/else).
- **"YOU WON!"** (Inter, 40, w900).
- **Score card** (grey.100, radius 16): "FINAL SCORE" (Inter, 14, w600, grey,
  letterSpacing 2) + value (Inter, 56, w900) + optional **"🏆 NEW HIGH SCORE!"** amber
  badge (Pulse, infinite).
- **Stat cards** row: "Games Won" and "Mistakes" (grey.100, radius 12).
- **Play Again** — ElevatedButton (black/white, rounded 25, `replay` icon).

---

## 7. Screen: Game Over (4 mistakes used)
Centered column, staggered:
- `😢` (64) · **"GAME OVER"** (Inter, 36, w900).
- **Score card** (grey.100, radius 16): "YOUR SCORE" + value (Inter, 48, w900) +
  "Groups Found: {n}/4".
- "High Score: {n}" (Inter, 16, amber.700).
- **Try Again** — ElevatedButton (black/white, rounded 25, `replay` icon).

---

## 8. Transient feedback (SnackBars, floating)
- **Correct group:** plays correct + category audio (no snackbar).
- **One away** (3/4 correct): "One away..." (black87, width 200, 1s) + audio.
- **Wrong:** "Not quite!" (black87, width 200, 1s) + wrong/encourage audio.
- **Lifelines:** "Look for the glowing items! ⭐" (amber, 2s); "Freeze activated! ❄️"
  (blue, 2s).

---

## 9. Key interaction flows
1. **Tap card** → play item-name audio → toggle selection (max 4). Selected animates
   to scale 0.95 + checkmark.
2. **Submit** (needs 4) → correct: items lock into a solved group card (BounceInDown),
   score += 100 + streak bonus. Wrong: mistake dot fills (unless Freeze), score −25.
3. **Auto-solve ("Solve All")** → narrated, human-paced: selects each item one by one
   (with name audio, waits for each), confirms, solves the group, announces category,
   repeats for all remaining groups, then victory. Cards are non-interactive during this.

---

## 10. What does NOT exist yet (gaps for the new build)
These are referenced in `PRD.md` but have **no current UI** and must be designed:
- **Topic/domain selection** (the app currently hardcodes one dataset).
- **The mastery-web view/print** (PRD §7.2) — the signature feature.
- **Multi-dimensional round framing** — showing *which dimension* this round groups by,
  and the post-round "go deeper / new lens / jump" choice (PRD §5.3).
- **Onboarding / first-run** for a non-reading child.
- **Parent/teacher surfaces** (later phases).

> When building from scratch, treat §1–§9 as the proven, keep-able baseline and §10
> as the new surface area the PRD's phases introduce.
