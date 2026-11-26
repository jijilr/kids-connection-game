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

How a true end is decided: by counting, not by opinion. Three keys, and the last is a script's.

1. The model lists every such thing that has an article of its own. Kinds, sorts, breeds,
   varieties and named examples all count, because a deeper set may be made of any of them.
2. A second, strict call keeps only true members. The first call pads a short list with near
   things: seas among the oceans, continents of the past among the continents.
3. A script asks for each article and counts each article once. Two names filed under one
   article are one thing.

With what the game already holds, fewer than sixteen: the group is an end, and the count and
the names are written down as the reason. The count leans toward "not an end": a wrong end
would close a branch, while a missed end only costs a search for a question.

In the data an end is written on the place, in `dictionary.json`, under the place's own name:
`"ends": {"animal/mammal/pet": {"on": "...", "why": "...", "run": "..."}}`. It is a place and not
an answer to a question (section 8a). An end can be taken back; the mark is kept.

Tried for real on 24 Nov 2026 (Rs 0.3 in all), on groups the game does not have yet:

| Group | Count | Verdict |
|---|---|---|
| Planets that go round the Sun | 8 | an end |
| Continents | 7 | an end |
| Land grazers (dinosaurs) | 59 | not an end |
| Things in the sky | 34 | not an end |
| Variants of the virus that causes COVID-19 | 21 | not an end |

The owner's own example, the variants, is not an end by the count: enough named variants and
lineages have articles of their own. One variant is a thing, and things are always leaves.

Built. In the game: an end is never a line; the web shows a leaf on it. In the job: the count
runs before a question is looked for, the engine's tree gives the place the status "end", and
the helper never tries to make it. No place in the game has been found to end yet.

Code: `tools/job/ends.py`; `count_the_world`, `mark_end` in `tools/prepare_next.py`;
`ends_in`, `judge` in `tools/content/expand.py`; `ends_now` in `tools/live/helper.py`.
Commands: `python tools/job/ends.py` lists the ends; `python tools/job/ends.py reopen CIRCLE
--why "..."` takes one back.

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

### How a thing is proved to be in between

Two keys, and both must turn. They are written and tested in `tools/job/widen.py`.

1. **Its own pages say so.** From the thing's whole pages the model copies one sentence for each
   answer the pages give it, and one sentence saying the answer is disputed, if there is one. A
   script checks every sentence against the saved text, word for word. A second call, shown
   only the sentence of dispute, says whether it speaks of today.
2. **Two checks give it no one place.** The same two sortings that settle every other thing are
   asked. If both put it in one and the same kind, it has a place after all.

### What a real trial showed (24 Nov 2026, Rs 2.2)

At the first place the model was asked twice for things with no single answer. It offered
fifteen. The keys refused fourteen:

| Offered | Why it was refused |
|---|---|
| Venus flytrap, sea anemone, moss | They only surprise. Their pages give them one kind. |
| Coral | Its dispute is of the past: "presently, corals are classified as species of animals". |
| Mushroom, bacteria | They belong to kinds the question lacks. That is widening (section 8). |
| Beaver dam, bird nest, spider web, fossil | Their pages give them one kind. |

**The virus passed both keys.** Its sentence: "Scientific opinions differ on whether viruses are
a form of life or organic structures that interact with living organisms."

One more thing passed on a sentence about what "early taxonomists" found hard. That is why the
second call about today was added.

What this means: honest in-between things are rare, which is as it should be. At the first
place there is one sure thing, the virus, and a group needs four. The group cannot be made of
four unrelated oddities.

### Not built yet, and why: a kind that is in between

What can fill the group is four different viruses. Each is in between because it is a virus,
not because its own page argues the point. That needs one more rule, which the owner has not
ruled on:

> A thing is also in between when it is a member of a kind that is. Two sentences prove it:
> one from its own page saying it is of that kind, and one from the kind's page saying the
> kind is disputed.

With that rule, "In between" at the first place is in effect the door to the viruses, and the
place below it can be sorted further like any other: kinds of virus, then coronaviruses, then
their variants. This is one answer to the owner's question of how "Everything" reaches the
virus. He was about to give his own; this section waits for it.

Until then nothing makes in-between things on purpose, and the catalogue's copy of the rule
(which writes the clues for the group) is not written either. The game is ready for them.

## 8. Widening a place

Until now the job could only make a whole new set under a group. It could not add a kind beside
the kinds a set already has, and the first set was made by hand.

Widening adds to a place that already has a set:

- **A kind the question has but cannot show yet**, because it has fewer than four things.
- **A new kind**, which the question lacks: mushrooms are neither plant nor animal, and nobody
  disputes it; they need a kind of their own.
- **The group "in between"** (section 7).

A new kind must pass three tests, by two separate sortings that share no wording:

1. **Four of its things are put in it** by both sortings.
2. **It takes nothing that is already there.** If either sorting would put a thing the place
   holds into the new kind, it is not a kind of its own.
3. **It stands beside the kinds there, not inside one.** Sorted over the old kinds alone, its
   things must have no place.

Its things then go through every stage like any other: pages, facts with their sentences, the
one-solution rule, pictures, checks.

When the game meets the wider place is settled by section 5: a place with an untested kind
becomes a line again.

Tried for real on 24 Nov 2026 (Rs 0.8), before anything was built on it:

| Place | Kind proposed | Verdict |
|---|---|---|
| Animals | Arachnids; Crustaceans | both pass |
| Plants | Herbs and spices; Ferns and mosses | both pass |
| Vehicles | On snow and ice | passes |
| Vehicles | In space | refused: Rocket, already "In the air", would belong to it |
| Everything | Furniture | refused: Chair, already there, would belong to it |
| Everything | Clothing | passed at first, wrongly. Clothes are things people make. Test 3 was added for this. |

Built: `python tools/prepare_next.py --widen CIRCLE --cap N`. It fills the kinds a question has
but cannot show, and adds at most one new kind in a run. A kind the owner holds back in
`settings.json` is left alone. Code: `tools/job/widen.py`; `plan_widen`, `add_kind` and
`widen_place` in `tools/prepare_next.py`.

The first real run (24 Nov 2026, job run 2026-11-24-23, Rs 27.8): Animals gained the kind
"Arachnids". Scorpion, Tick and Tarantula went into the game with their pictures. Spider and
Mite did not: the picture check took the spider for the tarantula and the mite for the tick,
so a player could not tell them apart either. With three things the kind is not shown yet; one
more run fills it. Nothing was padded to make four.

**Not built yet:** the helper does not widen by itself. Today widening is a command.

## 8a. Circles that cross

Owner, 24 Nov 2026, late evening: "inspite of being accomodating, we still assume concentric
circles paradigm. but knowledge is never that... while tomato could be part of the vegitable
circle, it could be also part of the hard to define category... how do we accomadate other
possible circles along with the main center and concentric circle". And then: "yes, build the
small proof."

**The data was never concentric.** A thing is a list of answers to questions. Tomato plant
carries two: it is a vegetable plant, and the part we eat is the fruit. Both are true, and
neither is "in between". It already stood in two circles.

**The game was concentric**, by three choices in the engine. Each is now undone:

| The old choice | What it is now |
|---|---|
| A question lived inside one circle. "Pet, farm or wild?" was asked of mammals and stored again, as a second field, for birds. | A question belongs to every thing it is true of. It is one field. |
| A place asked one question. | A place may ask more than one. Each set still asks one, and the same sixteen are never grouped a second way. |
| A place was named by the road to it. | A place is named by the circles it lies in, in the dictionary's order. Two roads to the same things reach one place, with one name and one knot on the web. |

The centre and the rings stay, as the spine: every place on the old single road keeps its name,
so nothing saved is lost.

### A question has a reach

The first real run taught this. "Is it mostly a pet, a farm animal or a wild animal?" was put
to the sixty animals that had never been asked. Two checks, sharing no wording, placed the fish
and the insects, and both refused every dinosaur and the two extinct snakes. A dinosaur is not
a pet, a farm animal or a wild animal. It is gone.

So the rule is: **a question belongs to every thing it is true of, and only to those.** A thing
it does not fit carries no answer, and a set sorted by the question simply does not show it.
Nothing is forced.

A question is asked at a place when it can fill a set there and either

- every thing of the place answers it, or
- the place is the question's **home**: the smallest place that holds every thing that answers.

"Pet, farm or wild?" has its home at Animals. It is not a question about Everything, because
every thing that answers it is an animal.

### What the player meets

1. Animals comes twice for its six kinds, as before (section 5).
2. Animals then stays a line for its second question. It does not come at once: it follows the
   groups he has just done well.
3. When it comes, the set asks "pet, farm or wild?" of animals of every kind. "Pets at home"
   holds a dog and a parrot.
4. A group done well there is a line like any other. "Wild animals on land" is a place of its
   own, with a set sorted by kind of animal: mammals, birds, insects, reptiles.
5. The wild land animals among the mammals are one place, whether he came through Mammals or
   through Wild animals on land. On the web it is one knot, tied by a dotted thread to the
   other circle it lies in.

Depth is the number of circles a place lies inside, whatever the road.

### What it changed elsewhere

- **An end is a place, not an answer.** "Pets at home" among the mammals and among the birds
  are two places, and one may end where the other does not. The mark moved from the question
  to the place (section 6).
- **Words can become untrue.** A group that grows past what its clues were written for must
  not keep them. The wild animals in water were whales and seals, and "comes up to breathe
  air" was true; then the fish joined. When the keep-fit check finds a clue or an explanation
  no longer true of every thing, and nothing better passes, the words are set aside (kept on
  record, not shown). No clue is better than a false one.
- **A question its things already answer is not offered to them again**, so no second copy of
  a question can be made.

### The real numbers (24 Nov 2026, Rs 1.7 in all)

| | |
|---|---|
| Animals that already carried the answer | 33 mammals |
| Answers taken over from the second copy | 17 birds |
| Placed by both checks | 28: 21 wild on land, 7 wild in water |
| Listed two groups | 1: Goldfish, a pet and a wild animal in water |
| The question does not fit | 31: every dinosaur, and two extinct snakes |
| Groups after the change | Pets 9, Farm 9, Wild on land 43, Wild in water 16 |

Code: `tools/job/cross.py` (the data); `BoardAssembler.canon`, `questionsAt`, `circlesBelow`;
`EngineProvider._questionFor`, `_resolve`, `_widerThan`, the `web` getter. Tests:
`test/crossing_circles_test.dart` (12), and three in `tools/job/selftest.py`.

### What the proof does not cover

- **The job and the helper still know only the old single road.** They cannot make a set for
  a place that exists only by crossing. Such a place plays from things the game already has,
  and the game no longer drops its line because the helper has never heard of it.
- **Two widened groups have no clues now**, and one has no explanation: "Wild animals on land"
  and "Wild animals in water". Their old words were written for mammals. New ones were refused
  three times each. A group this broad may be too broad to hint at.
- **A wider circle is a looser idea.** "Wild animals on land" now holds a lion, a crow, a
  housefly and a house lizard. Two checks agree that each belongs. Whether such a group still
  teaches something is a question for the owner.
- **Two questions have been widened.** "Which part of the plant do we eat?" is now asked of
  every plant it fits: the mango tree and the banana plant join the tomato under "the fruit",
  rice, wheat and the sunflower join the seeds, the coconut tree lists two parts, and the
  question does not fit the rose, the lotus, the marigold, grass, the neem tree, sugarcane or
  bamboo. One pass over a long list proved too careless to say a question does not fit a
  thing: a thing only one check placed is now asked again by itself.

## 8b. The map of places: the nerve system

Owner, 24 Nov 2026, night: "don't we have some kind of json with meta data of each node?...
if it is not integrated... that is the nerve system of the whole thing."

### Why it is needed

Three programs must agree on what the places are: the game, the job that makes content, and
the helper that decides what to make. Each worked the places out for itself, by its own copy
of the rules, and they had drifted apart:

- The game opened "Wild animals on land" across all animals. The helper had never heard of it
  and told the game to drop it. The game was patched to ignore the helper there.
- "A question has its home at a place" was written in the game's code only. The job could not
  use it.
- What was decided about a place lay in three files: ends in the dictionary, holds in the
  engine's tree, words in the catalogue.

The larger reason is depth. A phone cannot load every thing and work the places out from them.
It needs the map first, and the things of a place only when it goes there. An engine does not
hold every position; it holds the tree, with a judgement on each node.

### What it is

One file, `Assets/data/places.json`, with one record for each place. One program builds it,
`tools/catalogue/places.py`, from the master records: the things in the game, the dictionary,
the settings, the decisions on record, the words of each group. It is built again whenever the
catalogue is saved or the engine's tree is rebuilt. Nobody edits it.

| Part of a record | Example, for the wild land animals among the mammals |
|---|---|
| `name` | Wild animals on land |
| `circles` | animal, mammal, wild on land, in the dictionary's order |
| `lies_in` | the places one circle wider, with the answer this place adds: Mammals; Wild animals on land |
| `reached_from` | of those, the places where a set leads here |
| `things`, `with_pictures` | 18, 18 |
| `asks` | each question asked there, why it is asked there, whether it makes a set, and each kind with its count, whether it can be shown, where it leads, and whether it has clues and an explanation |
| `state`, `why` | ready / can be made / held / end / a group only, and the reason |
| `known_to_the_job` | whether the job's tree has this place (a place that exists only by crossing does not) |
| `history` | every decision about it, with date and reason |

What stays out: the player's progress, which is one layer per device over the same place
names; and the facts about things, which stay in the catalogue.

On the night it was first built the map held 82 places: 16 ready, 52 held, 5 that can be made,
9 that are a group only.

### The steps

| Step | What | State |
|---|---|---|
| 1 | The builder and the map, with a test that the map and the game agree on every place | **built** |
| 2 | The game reads the map and drops its own copy of the rules | **built** |
| 3 | The helper and the job read the map and write their results to the master records | **built**, with one part left (below) |
| 4 | A page for the owner: the whole map, every place by its state | **built** |
| 5 | Things stored by place, so a phone loads only the places near his lines | **built** |

**Since step 2 the rules of what a place is are written once, in the builder.** The game reads
the map (`lib/models/places_map.dart`) and works out nothing about places for itself: which
places there are, what each is called, what is asked there, which kinds can be shown, where
each kind leads, what lies in what, and which places are ends. What the game still does by
itself is what must happen while he plays: choosing sixteen things, and seeing that they have
one clean solution (`lib/services/board_assembler.dart`, which now makes sets and nothing else).

How the two ends are held together:

- Before the game's copy of the rules was removed, a test compared it with the map on the real
  data, place by place. They agreed on all 82 places. That test did its work and is gone with
  the rules it checked.
- `test/places_map_test.dart` now checks the other way round: wherever the map says a question
  makes a set, the game makes one, in pictures, with one clean solution, of kinds the map calls
  ready; and every place holds the things the map counts.
- The game's own tests on made-up games ask the builder for their maps
  (`test/support/places_for.dart` runs `places.py for FILE`), so no test carries a private idea
  of what a place is. This means the game's tests need Python on the machine.
- A check in `tools/catalogue/selftest.py` fails if the file on disk is not what the builder
  makes now.
- The map and the things are written a moment apart. The map says how many things it was built
  for, and the game does not take up a map and a list of things that do not match.
- Without a map the game can still play its first set, and nothing beyond it.

### Step 3: the helper and the job

- **The helper reads the map** and nothing else to know about places: what can open, what is
  never to be tried and why (an end, a place the rules hold, a group no question can sort),
  and which of his lines to make next. It no longer reads the job's printed words to guess why
  a set could not be made. It tells the game, for each of his lines, the state and the reason.
- **A place that cannot make a set says what it would take.** The map's `could_ask` names the
  question it could be sorted by and the kinds that are short. "Wild animals in water" needs
  two more reptiles to be sorted by kind of animal.
- **The job makes such a place** from what the map says: each short kind is an ordinary need,
  and its things must lie in every circle of the place (`plan_place` in
  `tools/prepare_next.py`). So `--only animal/wild_water` now works; before, the job did not
  know the place existed.
- **What was decided about such a place is kept in the catalogue**, under `places`
  (`record_place`), and the map carries it as the place's history and state: tried and not
  filled means held, until its things change.

What is left of step 3: for the places on the old single road, the job's planning still goes
through its own tree (`tools/content/expand.py`) and the catalogue's `worked_out`. They agree
with the map, and the map carries their decisions, but the rule "the first question that
sorts a place" is still written there as well. Only a dry run and the self-tests have exercised
the making of a crossing place; no money has been spent on a real one.

### Step 4: the owner's page

`http://localhost:8200/map`, served by the helper (`tools/live/map.html`). It reads the same
map the game reads, each time it is opened, so it is never behind. It shows:

- how many places there are in each state, as buttons that show or hide that state;
- the lines the game means to follow, best first, each with its state;
- every place, set under the place it lies in: its name, its state, the questions asked there
  with each kind and its count, and where a place cannot be played, why;
- on a touch, a place's circles, every place it lies in, the roads to it, what it would take
  to make it, and every decision ever made about it.

It works on a phone on the same Wi-Fi, at the PC's address with `/map`.

### Step 5: things stored by place

A phone cannot load every thing there is. So each place that can make a set has a small file
of its own, `Assets/data/places/<place>.json`, written by the builder with the map.

- **What a place's file holds:** of each kind that can be shown by a question asked there, the
  twelve best-known things, taken in turn from the kinds below it so that no one of them fills
  the list; and the things that are "in between" there. Twelve is three sets of four without
  a repeat.
- **The rest of a kind's things are met deeper in**, at the kind's own place. However large the
  game grows, a place's file stays small.
- **The game starts with the first place's file only** and takes up another place's file when
  it goes there. The place the button will lead to is fetched while he looks at the set he has
  just finished, so he does not wait.
- **One stamp.** The map and every file carry the mark of the moment they were built. A file
  with another mark is not used; he stays where he is, and the next try reads it again.
- The picture that stands for a place on his web, and what a group "in between" lies between,
  are written on the map, because the things themselves may not be on the device.

On the night it was built: the first set needs 48 things in 13 KB, where the game used to load
all 276 in 95 KB. Sixteen files, the largest 21 KB.

What changes for the player: at a high place he meets the best-known twelve of each kind, not
any of the kind. With 276 things that is hardly felt. It is the price of a file that stays
small when a kind holds ten thousand.

The full list, `things.json`, is still written. The job reads it, and the game falls back to
it where there are no files by place. Tests that give the game all its things at once are
unaffected.

Command: `python tools/catalogue/places.py` builds the map and lists it;
`python tools/catalogue/places.py show PLACE` prints one record.

## 8c. Clues live with the kinds

Owner, 24 Nov 2026: "it is a bad habit to have to deal with this - when we create it... as meta
data of classification is extracted. can you look at the meta data, dictionary entries etc...
and add clues parallel to the particular metadata (for classification) we use when we pick the
card as clue? if we don't have this, can you add them yourself?"

**What was wrong.** A group's clues were written afterwards, by a separate pass that looked at
the things that happened to be in the group that day. A group that grew was left with clues
that were no longer true, or with none. "Wild animals on land" was twice given "they live far
from people's homes", with a housefly in it.

**The rule now.** A clue comes from what defines the kind, so it is true of every thing that
can ever belong to it.

- Each question in the dictionary carries, beside `values`, a `clues` entry: for each kind a
  ladder of three, from a gentle hint to nearly there.
- **A kind is made with its clues.** Whoever proposes or chooses a question, or adds a kind to
  one, gives the three clues of each group with it (`tools/job/fields.py`, `widen.py`), and
  they go into the dictionary with the kind.
- Every group a player can meet takes its ladder from the dictionary each time the catalogue is
  saved. A ladder is used only if it passes the check that needs no model, against the things
  the group holds now: three clues, none too long, none holding a thing's name.
- The writer of words (`tools/content/group_words.py`) no longer writes or replaces these
  clues. It writes the explanation, and it is now told what defines the kind: the reason it
  gives must say that and claim nothing more. The fact in an explanation is still taken from
  a saved page, word for word.

**The one move for what was already there** (`tools/content/clues_into_dictionary.py`): all 71
kinds of the questions that sort sets have their ladder in the dictionary. 58 were taken over
as they stood. 13 were written by the assistant by hand, from the kind's definition, as the
owner asked: the eleven kinds that had none, and two whose clues were no longer true of the
kind ("Wild animals on land", "The fruit"). Two explanations were written by hand the same
way, each fact checked word for word against its saved page.

The group "in between" at the first question is named **"Hard to place"** in the dictionary,
with its own three clues (the owner: "the branch in the main node which saying 'hard to
classify' (or some apt shorter name)").

## 8d. One voice

Owner, 26 Nov 2026: "fix the sound overlap please... when a set moves on nothing from that set
must be playing... when a new audio starts playing all the previous one must shut up and go
away.... you can add more".

Every sound of the game goes through one place (`lib/services/sound_service.dart`): the
recorded clips and the device's own voice alike. Its rules:

1. **One sound at a time.** A clip or the device's voice, never both. Before this the two
   did not know of each other and could speak over one another.
2. **The newest wins** (his). What starts now stops whatever was playing and whatever was
   waiting. Before this, a name waited its turn: four quick touches were said one after
   another, long after the touches.
3. **One chain only.** A group's explanation waits for the sound that says "right", and
   nothing else waits for anything.
4. **When a set moves on, nothing of it is heard** (his). The game hushes the moment a set
   is left (Next, a new set, deeper, back), before the next set shows, even while the next
   set is still being fetched.
5. **A page opened or closed hushes** (added). Opening his web or the map, or coming back
   from it. A dialog does not.
6. **Put away, silent** (added). When the page is hidden (another tab, a locked phone) or
   the app is put away, everything stops.
7. **Nothing hushed comes back** (added). A clip still loading when it was hushed never
   starts, and what waited behind it is dropped. The calls to the player run one after
   another, so a stop can never land in the middle of a start.
8. **Taking a picture back is silent.** A touch that unselects says nothing (as before).

Tests: `test/one_voice_test.dart` (8), with a stand-in player.

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
| The end of a branch (6) | built: never a line, leaf on the web | built: counted before a question is looked for |
| In between (7) | built | the two keys are written, tested and tried; no run uses them yet (one rule is open) |
| Widening (8) | meets a wider place by rule 5 | built as a command; the helper does not widen by itself |
| Circles that cross (8a) | built | one question widened by a command; the job and helper still know one road |
| The map of places (8b) | reads it, works out no place for itself, and loads things place by place | the helper reads only the map; the job makes crossing places from it, and plans old-road places from its tree still |

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
- **Circles that cross, beyond the proof.** Section 8a. Which other questions to widen, and
  whether the job and the helper should learn that a place has more than one road.
- **How broad a group may be.** A widened group can lose its clues (section 8a). Is a group
  with no clue acceptable, or should a question not be widened that far?
- **A kind that is in between.** The rule in section 7 that would let four viruses fill the
  group at the first place. It needs the owner's word, because it decides what stands beside
  Animals and Plants on the first set.

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
| 24 Nov 2026, late | The concentric-circles paradigm itself: a thing belongs to more than one circle. "Yes, build the small proof" (section 8a). |
| 24 Nov 2026, night | One record for each place, integrated: "the nerve system of the whole thing". "Yes, start with step 1" (section 8b). |
| 26 Nov 2026 | One voice: a new sound stops all before it; when a set moves on, nothing of it is heard (section 8d). |
