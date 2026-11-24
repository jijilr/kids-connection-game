# How the game decides

Written on 24 November 2026, at the owner's request: "document them... as my june md helped...
it will help in the future."

This file holds the rules the game follows today and the reasons for them, in the owner's own
words where he gave them. It is the place to look before changing how sets are chosen, how deep
the game goes, or what a set may contain.

How it sits beside the other files:

| File | What it is | State |
|---|---|---|
| `PRD.md`, `ARCHITECTURE.md`, `BUILD_PLAN.md`, `TARGET_UI.md`, `PHASE0_EXPERIMENT.md` | The owner's thinking of June 2026 | The principles stand. The mechanics have moved on; where they differ, this file is right. |
| `DESIGN.md` (this file) | The rules as they are now, and why | Kept current. Change it in the same commit as the rule. |
| `WORK_DONE.md` | What was built, in order | A record, not a guide. |

Each section says what is **built** and what is **not built yet**.

---

## 1. The idea

There is one game, and its data grows. The owner, 24 Nov 2026: "there is a one game... data is
dynamic."

A set is sixteen pictures. The player sorts them into four groups of four by one question. When
he does a group well, the game goes deeper into that group: the next set is made of things of
that kind, sorted by a new question. Sets that do not exist yet are made in the background while
he plays others: facts from fetched source pages, pictures from an image model. The game is
meant to go "as deep as wikipedia itself", in every direction the player shows he can follow.

Since the evening of 24 Nov 2026 the game is designed for **general use**, not for one child of
four: "don't worry about my son now... we are departing to the general use now." Limits that
exist only because of one player's age are settings of an audience (section 9), not rules of
the engine.

## 2. Words

| Word | Meaning |
|---|---|
| Thing | One item with a picture and a name: Mango tree, T. rex. |
| Question | One way of sorting: "What kind of animal is it?" In the data it is a *field*. |
| Kind | One answer to a question: Birds. In the data it is a *value*. |
| Group | Four things of one kind, on a set. |
| Set | Sixteen things in four groups, sorted by one question. In the code: *board*. |
| Place | A point in the game where a set can be made: Everything, Animals, Dinosaurs. In the code: *circle*; its id is the path to it, such as `animal/dinosaur`. The first place is `seed`. |
| Line | A place the game means to go to next, kept in the player's saved progress, best first. |
| Round | One set at a place that has more kinds than four (section 5). |
| End | A kind below which nothing lies (section 6). |
| In between | The group of things that have no single answer to a question (section 7). |
| Widening | Adding a kind to a place that already has a set (section 8). |

## 3. Rules that never bend

These are the owner's hard rules. A change to any of them needs his word.

1. **One clean solution.** A set has exactly one way to sort it into four groups of four. If
   another stored question also sorts the same sixteen four by four, the set is refused. "If
   there is a possibility of multiple solution (such as classification based on era, and
   classification based on eating habbits) must not be allowed."
2. **One named question for each set.** Never "the same sixteen, grouped another way".
3. **Never a shallow set.** No filler things, no surface questions. Never colour, never size.
4. **Grounded.** Facts come from fetched pages (Wikipedia, the Natural History Museum, the
   American Museum of Natural History, Kew), each with its sentence. The model chooses and
   reads; it does not invent.
5. **Nothing unsuitable for a young child** enters the game.
6. **Money.** A cap the owner names is a hard cap. Keys stay on his PC, never in the game.
7. **The live site** changes only on his word.
8. **Nothing is deleted.** What is taken out is marked and kept.

## 4. Which set comes next

Built. Owner's design of 23 and 24 Nov 2026.

1. On each set the game ranks the four groups by how well he did them: fewest wrong guesses
   that took in a thing of the group, then no clue asked, then "whichever the user attempted
   earliest".
2. A group done well (no such wrong guess, no clue) becomes a **line**: the game means to go
   into it. Lines are kept in his saved progress, the newest set's first.
3. When a set is finished, four times in five the game follows the first line whose set is
   ready. Once in five it goes to a set he has not proven, the one he has opened least, nearest
   first. He never waits: if no line is ready, he gets another set at once.
4. A helper on the owner's PC keeps his best three lines ready ("max 3 to 4 sets at any time...
   just like how chess braches are assessed by engines"). A set that does not exist is made
   then, under a cap of Rs 200 a day and Rs 90 a set. The game picks up new data without a
   rebuild.
5. The player does not choose where to go. "Dig deeper is not a choice for the user. This is a
   test feature." The switch at the top (Auto / Test) shows the old test features.

## 5. More kinds than four

Built in the game on 24 Nov 2026 (evening). Owner: "currently we have to have 4 sub items for a
node to have depth... we need to keep in mind that we can have more than 4. and we will have to
have combinations of them to cover testing each."

A place may hold any number of kinds. A set shows four of them. The kinds are covered in the
**fewest rounds**:

| Kinds at the place | Rounds | What each round shows |
|---|---|---|
| 4 | 1 | the four |
| 5 | 2 | four, then the one left and three used again |
| 6 | 2 | four, then the two left and two used again ("get it over with") |
| 7, 8 | 2 | four, then the rest and what is needed to make four |
| 9 | 3 | four, four, then the one left and three used again |

The rules:

- **Untested kinds first.** A kind is tested when he has found its group once.
- **The kinds used again are the ones he did worst.** A kind used again is shown with other
  things where it has them.
- **A place is not used up until every kind is tested.** It stays a line, at the very front, so
  its rounds follow one another. Only when all its kinds are tested is it known which he does
  best, and only then does the game go into one of them.
- **One clean solution outranks the fewest rounds.** If the chosen four cannot make a clean
  set, the game tries, in this order: the same four with other things; another used-again kind
  in place of one; and only then a four with fewer untested kinds, which costs one more round.
  The one-solution rule is never broken to save a round.
- A place whose last kind fits no clean set is not offered again in the same sitting, so he is
  never sent round in a ring.
- A kind with fewer than four things that can be shown is not counted. It waits until it has
  four.

What the game remembers for this, in saved progress, for each group: how often found, how often
cleanly, how many wrong guesses took in its things, and the four things it was last shown with.

**Not built yet:** the job fills only four kinds of a question when it makes a set. Filling the
others is part of widening (section 8).

Code: `BoardAssembler._fours`, `_fourOf`, `kindsReady`; `EngineProvider._coverage`,
`_unfinished`; `Progress.finished`. Tests: `test/more_than_four_test.dart`.

## 6. The end of a branch

Owner: "for some... you can't go deeper... consider we are on virus... then we reach covid
virus, then we reach say delta varient or omega varient. i think there is no more below that...
therefor that is the end of that brach."

A branch often ends one step before its last name. Going deeper means sorting the things of a
group into four kinds of four, which needs sixteen things. Five variants cannot be sorted
further. So the end is the group that holds them.

A line can stop for three different reasons, and they must not be confused:

| Reason | What it is | What the game does |
|---|---|---|
| **A true end** | The world holds too few such things to sort them further. | Marked as an end, for good. Never tried again. Shown on the web with a leaf. |
| **No question found** | There are enough things, but no question sorts them cleanly yet. | Held by the rules, with the reasons. A better question may come later. |
| **The audience's bar** | There are enough things, but too few that this audience knows. | A setting (section 9), not a fact about the world. |

How a true end is decided: by counting, not by opinion. The job asks for every such thing that
has a source page of its own and checks that each page exists. Fewer than sixteen: the group is
an end, and the count and the names are written down as the reason.

In the data an end is written on the question, in `dictionary.json`: `"ends": {"<kind>":
{"on": "...", "why": "..."}}`.

Built in the game: an end is never a line; the web shows a leaf on it.
**Not built yet:** see section 10 for the state of the job.

## 7. Things that resist classification

Owner, 24 Nov 2026: "Virus, Pluto, Schrödinger's cat, Centaur, Photon... things resist binary
classification." And: "i think we will have to force this in everything node... without this we
will lose real richness in the long run."

This is his third principle of June (`PRD.md`, Part I): "Categories are provisional. The deep
levels (virus: alive? Pluto: planet?) teach that classifications are human-made and fray at the
edges. The contested frontier is a feature, not a failure."

Why the first place needs it most: it is the only place with nothing above it. Lower down, a
thing that fits no kind still belongs where it is (an animal that fits no kind of animal is
still an animal). A thing that cannot answer the first question is outside the game for good.

His five examples do not resist for the same reason, and they need three different doors:

| Thing | Where it resists | What it needs |
|---|---|---|
| Virus | At the first question: alive or not? | "In between" at the first place |
| Pluto, Photon | Lower down. At the first question both are plainly "nature, not alive". | "In between" at the place where they resist |
| Centaur, Schrödinger's cat | Nowhere. Nobody disputes that they are imagined. | A missing kind, such as "things people imagined": widening (section 8) |

### The rule

**Any question may have the answer "in between".** A thing with no single answer to a question
is not left out and not forced into one answer. Once there are four such things at a place,
they are a group of their own on a set sorted by that question.

Four rules keep it honest:

1. **The sources must say so.** A thing is in between when its sources place it in two of the
   question's kinds, each with its sentence, or say in a sentence that the answer is disputed.
   "The world does not agree" is a fact and goes in. "We could not find out" is not: that
   thing stays held, as before.
2. **It is not a dump.** A thing that fits no kind at all calls for a new kind (section 8).
3. **It waits for both sides.** The group is shown only when he knows the kinds it lies
   between: he has found each, and where a side has a set of its own he has played it. A
   virus means nothing to one who does not know living from not living. This is the owner's
   own rule that new things are an "extension of what he has seen".
4. **It never makes up the number.** A place needs four real kinds to have a set. Three kinds
   and "in between" are no set.

In a set, "in between" is the single right answer for its four things, so the one-solution rule
holds.

### In the data

No new form was needed. The dictionary has carried both since October:

- A thing that fits two kinds lists them: Rain is `["sky", "water"]`.
- A thing that experts debate is marked `"depends"`, with a note saying why.

Until now such a thing "stays off boards sorted by that field". Now four of them form the group
"In between". Fewer than four stay off, as before. A question may give the group its own name
in the dictionary: `"in_between": {"label": "..."}`.

On the web the group is tied to its place and, by dotted threads, to the kinds it lies between.
These knots are the bridges between branches. They answer the owner's earlier worry that
"somewhere one branch might share elements with another branch".

Built in the game. Code: `Dimension.inBetween`, `Entity.valueFor`, `Entity.sidesOf`,
`EngineProvider._notYet`, `_knows`. Tests: `test/more_than_four_test.dart`.
**Not built yet:** see section 10 for the state of the job.

## 8. Widening a place

Until now the job could only make a whole new set under a group. It could not add a kind beside
the kinds a set already has, and the first set was made by hand.

Widening adds to a place that already has a set:

- **A kind the question has but cannot show yet**, because it has fewer than four things.
- **A new kind**, which the question lacks: mushrooms are neither plant nor animal, and nobody
  disputes it; they need a kind of their own.
- **The group "in between"** (section 7).

A new kind passes the same tests as a new question: four things with pictures, one answer for
each thing by two checks that agree, sets with one clean solution, and it must not be an
existing kind in other words.

When the game meets the wider place is settled by section 5: a place with an untested kind
becomes a line again.

**Not built yet:** see section 10.

## 9. The measures, and the audience

**Breadth and depth** (built). Counted on the player's own web, not on a list of subjects of
ours. An end of his web is a group with nothing found beyond it. Breadth is the number of ends.
Depth is the number of steps from the middle to an end: the average, and the deepest. The owner
saw the difficulty himself: "we assume we are the authorities to define that epistemological
decision." Counting on his own web avoids deciding what a subject is. The numbers show how his
web grows. They are not a measure of how much he knows.

**The audience.** These are settings, not rules of the engine:

| Setting | Where | Today |
|---|---|---|
| How well known a thing must be | `FAMILIAR_ENOUGH`, `WELL_KNOWN_ENOUGH` in `tools/prepare_next.py` | 0.7 for a first set; 0.4 for a set inside a group he did well |
| Share of sets that follow his best line | `next_board.deeper_share` in `settings.json` | 0.8 |
| Sets kept ready ahead of him | `BUFFER` in `tools/live/helper.py` | 3 |
| Money | `DAY_CAP_INR`, `SET_CAP_INR` in the helper | Rs 200 a day, Rs 90 a set |

The wording of the job's questions to the model still speaks of "a four-year-old in India".
With general use decided, that wording is the next thing to turn into a setting.

## 10. What is built, and what is not

| Rule | In the game | In the job that makes sets |
|---|---|---|
| Next set from his lines (4) | built | built (helper) |
| More kinds than four (5) | built | fills four kinds only |
| The end of a branch (6) | built: never a line, leaf on the web | not built: nothing marks an end yet |
| In between (7) | built | not built: nothing makes such things on purpose yet |
| Widening (8) | meets a wider place by rule 5 | not built |

## 11. Open questions

- **The audience's bar.** "Land grazers" cannot fill four groups of four well-known dinosaurs
  at 0.4. Lower the bar for general use, or accept that line stops there?
- **A second way a sharp player might see.** The clever-kid check found "number of legs" and
  "number of wheels" as second ways on some sample sets. They are stored nowhere, so the game
  cannot refuse them. Store them?
- **When "in between" opens.** Rule 3 of section 7 asks that he has played the set inside each
  side. That is the assistant's reading of "knows both sides". A lighter reading (he has found
  each side once) would show the group one set earlier.
- **The name of the group.** "In between" is the default. "People do not agree" or "Hard to
  place" may suit a question better; a question can set its own.
- **Automatic widening.** Whether the helper should widen places by itself, inside the day's
  money, or only on a command.

## 12. The owner's rulings, in order

| Date | Ruling |
|---|---|
| June 2026 | The principles: discover, don't instruct; categories are provisional; depth is a measurement; grounded, not invented (`PRD.md`). |
| 7 Oct 2026 | The system runs itself: rules decide, a digest reports. Questions come from a library of real ones. One way of making a set; one creator of new things; never a shallow set. |
| 23 Nov 2026 | Four in five deeper where he has shown mastery, one in five elsewhere. |
| 24 Nov 2026 | One game, dynamic data. Sets made while he plays. A buffer of three or four. Ties go to the group attempted earliest. Twelve pictures on a sheet. Rs 200 a day for now. |
| 24 Nov 2026 | No special cases: "I gave you prehistoric example just as an example." Build the general thing. |
| 24 Nov 2026 | Automate is the design; "Dig deeper" is a test feature. The web of what he has found; breadth and depth. |
| 24 Nov 2026, evening | More kinds than four, covered in the fewest rounds. A branch can end. Things resist classification, and the first place must take them in. General use. Write the decisions down. |
