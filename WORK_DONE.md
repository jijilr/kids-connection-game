# What has been done

A running record of the work on the learning game, kept in the project so it can be read without any chat.
It is updated after each piece of work. The fuller story, with the reasons, is in the Claude Doc
"The Learning Engine" (https://claude.ai/code/artifact/c3f3f0d3-5f91-4df4-8786-d894ef1d12df).

Last updated: 24 Nov 2026. Branch: `fresh-start`. The live site (branch `main`) has not been touched.

---

## 1. Where things stand

| | |
|---|---|
| Things in the game | 258, each with a drawn picture and a spoken name |
| Things recorded in all | 368 (79 held by the rules, 23 taken out and kept, 5 kept for later by the owner, 3 ruled out) |
| Sets a child can open | 14 |
| Dictionary | version 12, 21 fields (two withdrawn) |
| Field library | 32 questions, 2 retired, 3 three-way splits parked |
| Groups with words | 61, each with a ladder of clues; 59 have an explanation |
| Tests | 61 in the game, 35 for the job, 4 for the helper, 8 for the catalogue, 10 for the pictures. All pass |

**The fourteen sets:** Everything, Animals, Mammals, Wild animals on land (made on 24 Nov by the helper,
while "playing"), Birds, Dinosaurs, Plants, Vegetable plants, Things in nature that are not alive, Things
people make, Vehicles, Toys, Things in the house, Buildings.

**Not yet seen by the first child.** The owner has played it. Nothing is deployed.

---

## 2. What was built

### The data: fields, not questions
- A fresh start on 6 Oct 2026. Everything before it is saved under the tag `before-fresh-start-2026-10-06`.
- Every thing carries fields with values from one dictionary (`Assets/data/dictionary.json`). A field that
  does not apply is left out. An everyday field sorts boards; an `_academic` twin records what a scientist
  says and never sorts a board.
- Three hard rules: one clean solution for every board; no board that re-sorts the same sixteen; values only
  from the dictionary.
- A guard (`tools/content/guard.py`) refuses unknown fields, values outside the dictionary, missing or
  misplaced fields, and things not stamped against the current dictionary.

### The catalogue: one master record
- `tools/catalogue/catalogue.json` is the master record of every thing: fields, sources, picture, voice,
  status, and the circles and boards it belongs to. `tools/catalogue/catalogue.py` is the only code that
  reads or writes it.
- `Assets/data/things.json` is the game's copy, written from the catalogue. Nobody edits it.
- The catalogue works out which circles can open and what each closed one needs. "Dig deeper" is never
  decided by hand.
- Statuses: in the game, waiting for the owner, held by the rules, kept for later, not in the game yet,
  excluded, taken out of the game. Nothing is ever deleted.

### Pictures
- Drawn by the OpenAI image model in sheets of nine, cut into tiles, checked by a vision model, and
  published as small WebP files in `Assets/pictures/`. Scripts are in `tools/pictures/`.
- Prehistoric animals are checked against features taken from museum and encyclopedia pages.
- Original sheets and full-size tiles are in Git LFS. Only the small game versions are in the project.
- 54 sheets and 329 tiles so far. A tile that is replaced is set aside and kept.

### Research without a chat assistant
- `tools/research/`: scripts fetch Wikipedia (English and Simple), the Natural History Museum and others.
  DeepSeek reads only the fetched text. Every value carries a sentence found word for word in the saved
  page, and a second reading must agree.
- An everyday field that no page states is judged twice in different words. Agreement is kept as
  "judged, not sourced".
- Benchmarked against hand research on 28 prehistoric animals. The everyday DeepSeek model is the judge.
- Every spending cap is a hard cap: the most a call could cost is set aside before the call is made.

### The one-command job
- `python tools/prepare_next.py` prepares the next level: plan, field, names, facts, boards, pictures,
  checks, words, digest. One commit for each run. It never pushes and never deploys.
- Default hard cap: 200 rupees a run. `--dry-run` shows the plan and spends nothing.
- `--undo RUN` takes a run back. `--withdraw-field FIELD` takes one field back.
  `python tools/catalogue/catalogue.py take-out NAME --why "..."` takes one thing back.

### The system runs itself (7 Oct)
- Nobody approves a circle or a field. The expansion engine (`tools/content/expand.py`) gives the order,
  with its balance rules. A digest after each run says what was done.
- A field must pass four tests (`tools/job/fields.py`): four familiar things in at least four of its
  values; one value for each thing, by two checks that agree; one clean solution on sample boards; not an
  existing field in other words.
- One thing in eight may truly fit two groups. It lists both and stays off that board.
- A suggested name counts only if it belongs to the circle, a four-year-old knows it, and it is a thing of
  its own, not another name for something already there.
- The owner is brought only: a change to a hard rule, a thing unsuitable for a young child, and what two
  checks could not settle about a thing already in the game.

### The field library (7 Oct)
- `tools/content/field_library.json`: real, teachable sorting questions from biology, geography and
  everyday life. The model chooses from it and does not invent. "Mostly" wording settles overlaps.
- A field may have more than four values. A board uses any four with enough familiar things.
- Never colour and never size. The colour and size questions are retired and kept in the file.
- Fields that came from the library: Mammals and Birds (pet, farm or wild), Toys (how we play with it),
  Buildings (what people do there), Places on land (what the land is like).

### Two functions (7 Oct, night)
- `make_board`: sixteen things, four groups, exactly one solution, from what exists. In the game it is
  `BoardAssembler.makeBoard`; for the worker it is `boards.make_board`. Never a padded group, never a
  shallower sorting.
- `fetch_nodes`: the only way new things are made. It is inside `tools/prepare_next.py`. An order is one
  group for one board. Until the game is online the worker treats every open board as solved.

### The game (Flutter, `lib/`)
- Starts at the four-group seed. Tiles are pictures. Tapping a tile says its name.
- A solved group becomes a coloured bar with its four pictures, centred and sized to the screen.
- **Less height spent** (23 Nov, the owner asked "Can you save some vertical space?"). The title bar is
  lower, the button that reads the question aloud sits beside the question, the pictures in a found
  group are at most 120 (never below 68 on a phone, larger than the first 64), the card "You did it!"
  has its stars and words on one line, and on a large screen the game's frame reaches nearer the top and
  foot of the window. At 1400 by 960 a finished board, its card and the explanation now stand on one
  screen; before, the last group was cut off and the card was below the edge.
- After a solved board one button takes the child on (the owner's ruling of 23 Nov, which replaced "the
  branch he has visited least"): **four boards in five go deeper where he has shown mastery, one in five
  to a set he has not mastered.** A group is mastered when he has found it cleanly (no wrong guess took in
  its things, no clue was asked for it) on two different days. Deeper first means a board inside a group
  just found, then the one he has solved least; the one in five goes to the board he has opened least,
  inside a group just found first. Until he has mastered anything, the button keeps the old balance: the
  least visited first. With nothing to choose, a parallel board at once. The share (0.8) and the days (2)
  are in `Assets/data/settings.json` under `next_board`. Stars are unchanged; a clue still costs no star.
  Code: `EngineProvider._chooseNext`; tests: `test/mastery_test.dart`.
- A fresh board is never the same sixteen again, where another is possible.
- **Clue button:** one step up a ladder of three clues for the group he is working on. A clue never names
  a tile and never costs a star.
- **Explanation:** when a group is found, the game shows and speaks why its things belong together, with
  one true fact.
- **The card that ends a board comes onto the screen by itself** (8 Oct). Under four solved groups it
  stood below the edge of a phone or small tablet, and the button that leads on had to be found by
  scrolling. Found while filming the game; tested at three screen sizes.
- **Saved progress:** boards opened and solved are kept on the device, and since 23 Nov each group he
  found, how often cleanly, and on which days (file version 2; a version 1 file still loads). A long press on the title opens a
  panel for the grown-up, which saves the record as a file. Put it at `tools/job/progress.json` and the job
  prepares one step ahead of where the child is.

### Voices
- Every name, clue and explanation is spoken with the owner's Kokoro at `D:\Projects\Kokoro`, in one
  British voice (`bf_emma`), a little slower than talk. Nothing of Kokoro was downloaded, installed or
  copied.
- `python tools/voice/record_names.py` records what is missing. Clips are cached in `tools/voice/clips/`.
  Those the game plays are in `Assets/audio/names/` and `Assets/audio/groups/`.
- The browser's own voice is only a fallback.
- No clip has been checked by ear. Fourteen names are flagged as unsure in `tools/voice/pronunciation.json`.

### Clues and explanations (7 Oct)
- Written for a group (a field and one of its values), not for a board, by `tools/content/group_words.py`.
- Checks: no clue holds the name of a thing of the group; the sentence quoted for the fact is in the saved
  page word for word; two or three sentences; a second reading agrees.
- The catalogue's `groups` section is the master record. `Assets/data/groups.json` is the game's copy.

### Every thing drawn from its sources (24 Nov)
The owner's ruling: no kind of thing is special. Until then the job refused anything under Dinosaurs
or marked extinct, because only a fixed list of prehistoric animals had been researched before drawing.
Now every thing the job draws goes through the same step, `tools/research/looks.py`:
- the whole Wikipedia articles of the pages already chosen for it (the job had kept only their
  openings), and any museum or Kew page already saved;
- DeepSeek lists what a picture of it would show, the mistakes pictures make, and what is uncertain,
  each with a sentence a script finds word for word in the page; a second reading keeps only what the
  sentence supports and a picture can show. Pages about something else of the same name (Glass the
  material) give nothing. Only what is true of every ordinary one counts: no variant, nothing "often";
- the judge picks the two to four features that tell it from the other things of its group;
- the painter's line is written from those, and the stricter picture check (`check_features.py`,
  begun for dinosaurs) compares the tile with them. A thing whose pages say nothing of its look is
  drawn from its typical look, as before. The owner's own `draw_as` still wins.
- A guard in the job's self-test fails if a kind of thing is ever named in the job's code again.
- Trial on 24 Nov, about Rs 4: Triceratops, Stegosaurus, Ankylosaurus, Cup, Spoon and Glass. The
  dinosaurs came out with frill, horns and beak; plates and tail spikes; tail club. Glass was found to be
  filed under the article about the material.
- It adds about Rs 2 a thing to a run (the reading, and the stricter check of two tiles).

### One game, dynamic data (24 Nov)
The owner's design, in his words in section 3. Built the same day, in five steps:
1. **The game ranks the groups of each set** by how well he did them: fewest wrong guesses that took in
   its things, then no clue, and a tie goes to the group he attempted earliest. The groups he did well
   become **lines to follow**, kept in his saved progress (file version 3), the newest set's first. A set
   played is used up as a line. Four times in five the button follows the first line whose set is ready;
   once in five it leads to a set he has not proven. This replaces the two-day rule of 23 Nov.
   (`EngineProvider.ranked`, `_chooseNext`; `test/lines_test.dart`.)
2. **The helper on this PC** (`tools/live/helper.py`) serves the built game and, live from the project,
   its data, pictures and sounds. It keeps his best three lines ready, best first: a missing set is made
   by the job while he plays others. At most Rs 200 a day and Rs 90 a set, as hard caps. It never pushes
   or deploys. Its log and ledger are in `tools/live/out/` (not in git).
3. **The game takes up a new set with no rebuild** (`lib/services/live_link.dart`): on the web it reads its
   data through the helper, tells it his lines when a set is finished, and re-reads the data when the
   helper says it has changed. With no helper there it plays from what it ships with.
4. **The clever-kid check** (his `PRD.md` IV.2 of June, never built until now): before a set's pictures are
   paid for, a model is shown sample sets of sixteen and asked for any other way to sort all of them; a
   script counts only a real second sorting. A set that can always be sorted another way is held.
5. **New sets are drawn twelve to a sheet**, and the job takes `--only CIRCLE` (one named set) and
   `--new-to-him` (the best-known things of the group, not only those a four-year-old already knows).

**The first real sets, and what they showed** (runs 2026-11-24-01 to -05, Rs 70.5 in all):
- *Land grazers* (the owner's own example, dinosaurs), three tries, Rs 19: no set. A question passed and
  three new dinosaurs were made (Torosaurus, Styracosaurus, Pentaceratops), but not four groups of four
  well-known ones: the armoured and the bone-headed dinosaurs run out. It is held by the rules. The tries
  found and fixed four general faults: the proposer offered only things a small child knows; a question
  could have only four groups (now four to six, any four that fill make a set); "extinct" needed the word
  itself (now a sentence that places a living thing in the far past shows it); names held by an earlier
  run could not be offered again.
- *Wild animals on land* (under Mammals): **made, Rs 51.5 over two runs, about ten minutes in all.** The
  job chose "What does this animal mostly eat?" (only plants, only meat, plants and meat, mostly insects),
  settled twelve new animals from their pages, drew them on one sheet of twelve, checked them, recorded
  their names, and the helper reported the set ready. The game's own set maker makes it in pictures, and
  the helper serves the new pictures, which are not in the build. Two more faults fixed on the way: the
  money set aside for the stricter picture check was five times its real cost and stopped the run; and
  a trait no picture can show (the shape of a chimpanzee's hips) failed three good pictures, where it
  should only be reported.
- The clever-kid check, tried on existing sets: nothing for the first set and Dinosaurs; one sample in
  three of Animals, Mammals' new set and Vehicles could also be sorted by number of legs or wheels.
- Not seen with my own eyes: the new set on the game's screen. It is behind four other lines in the test
  browser's progress, and I did not play through them.

### Twelve pictures on one sheet (24 Nov)
The owner asked for a grid of 3 by 4 to save cost. The picture tools now draw and cut a sheet that is
not square (`rows` and `cols` in `tools/pictures/plan.json`; `layout_rows` in its style). One trial,
Rs 17: twelve animals already in the game, drawn by their own lines. All twelve cut cleanly and the
vision check named each one. A tile comes out about 700 to 900 pixels across (900 to 1,050 from a sheet
of nine); the game shows 384. Rs 1.4 a picture in place of Rs 1.9. The comparison is
`tools/pictures/preview/trial_3x4_compare.png`. The trial tiles are set aside, not in the game. The job
does not use sheets of twelve yet.

### A picture of what the game holds (8 Oct)
- `docs/game_map.png`: a map of the game, made in Blender. The seed is in the middle, the four kinds of
  thing around it, and the circles inside each kind on the outer ring. A board a child can open is a
  coloured platform with four tiles, one from each of four of its groups. A group with no board inside it
  yet is a small grey pad with one tile. Each carries its name and how many things it holds.
- `docs/game_map.blend` is the Blender scene, for opening and changing by hand. The tiles on it are the
  game's own pictures in `Assets/pictures/`, linked, not copied.
- The picture is made from the game's own data, so it can be made again as the game grows:
  `tools/illustration/game_map_data.py` asks the board maker what can open and writes `game_map.json`;
  `tools/illustration/game_map_blender.py` builds the scene and renders it. It costs nothing.
- It shows the game as it stood on 8 Oct: 243 things, 13 boards. It does not update itself.

### A film of how the game is played (8 Oct)
- `docs/how_the_game_is_played.mp4`: 1920 x 1080, 2 min 48. The owner asked for it,
  with his Glym film as the thing to be parallel to. The film file is not in git; what makes it is.
- **The game in it is the game.** `tools/film/film_game_test.dart` starts the game's own screen with the
  things, pictures, clues and explanations as shipped, on a screen the size of a small tablet, plays it by
  presses a finger would make, and saves every frame. The boards are dealt from a fixed seed, so it can be
  made again. Every sound of the game in it is the clip the game asked for, at the moment it asked.
- **Drawn by the film:** the tablet's frame, the dot where the finger is, the narrator's line, a box with
  the words the game is saying (for a viewer with the sound off), the rings on the map, the two cards.
- **The narrator** is Kokoro's `bm_george`, a different voice from the game's own, from the owner's
  installation, used where it stands. His lines are in `tools/film/how_it_is_played.voice.json`.
- **What it shows:** a touch says a name; four that belong become a bar and the game says why; a wrong
  guess; two clues; the board done; Dig deeper into Animals, then Mammals; Next board where nothing is
  deeper; the map of the whole game with the path just played ringed.
- Four stretches of play are left out, each with a dissolve. It was made without hearing it.
- `tools/film/README.md` says what is real and what is drawn, what to check by ear, and how to change it.
- `tools/illustration/game_map_blender.py` now also writes where each circle stands in the picture
  (`game_map_points.json`), which the film reads.

---

## 3. The owner's rulings, in order

**6 Oct 2026**
- Realistic pictures on plain white. Originals kept out of the main project.
- Research and drafting must be scripts, not chat sessions. Sources: Wikipedia, the Natural History
  Museum, the American Museum of Natural History, Kew for plants. No fan wikis, film or toy sites.
- The catalogue is the master record. Which groups offer "Dig deeper" is never hand-decided.
- A cap he approves is a hard cap. With none named: 10 rupees a step, hard, and the spend is reported.
- Everyday things suitable for a four-year-old go in without asking. Religious places are not sensitive.
- Shop, Bridge and Tower count as buildings. Maize counts as a vegetable plant; the scientist's answer is
  kept in an academic field.
- Vegetable plants, Vehicles and Things in the house approved. Trees held: one tree gives several things.

**7 Oct 2026**
- Stop asking for routine decisions. Rules decide; report with a digest; he can undo anything.
- Fields come from a library of real questions. The model chooses and does not invent.
- Real, teachable distinctions only. Never colour or size.
- Birds a child in India sees often come first.
- Two functions: `make_board` and `fetch_nodes`. Never a shallow board, no filler, no surface fields.
- Kokoro for voices, from his own folder only.
- The four-group rule stays. The three-way splits of Reptiles, Fish and Water are parked for the
  odd-one-out and true-or-false games.
- A group must not be spotted by a word its labels share: the music toys are shown and spoken as Drum,
  Flute, Piano, Xylophone and Guitar.
- Port drawn again as a harbour with docks and cranes.
- Clues and explanations, for each group.

**23 Nov 2026**
- "Can you save some vertical space?": done (see section 2).
- Breadth and depth by mastery, like a recommender: four boards in five go deeper where he has shown
  mastery, one in five to a set he has not. This replaces "a well-rounded child, not a specialist: the
  branch he has visited least" of 6 Oct, which now lives on only in the one in five. The job follows the
  same rule, and the engine's depth gap no longer holds back a circle inside what he has mastered.
- His results reach this machine as the file a grown-up saves from the game, as before.
- The job runs by itself once a week, at most 200 rupees a week, and nothing goes to the live site without
  his yes.

**24 Nov 2026**
- "No one does it for prehistoric animals... that is hard coding. What I want is dynamically reaching all
  that. I gave you prehistoric as just an example." Nothing is special-cased by kind. Asked whether every
  thing should be drawn from what its sources say it looks like: "yes, build it for everything". His
  picture rule widens from "prehistoric animals are checked against sources" to every thing.
- **The direction, in his words: "there is a one game... data is dynamic."** The start and the sets under
  its four groups are shipped. After each set, the group "solved with most mastery and confidence" decides
  the next. A set that is not there is fetched (DeepSeek for facts, the image model for pictures) while
  he plays others. A buffer of "max 3 to 4 sets at any time"; "as one is used up... we prepare (either from
  the existing data or made from api calls)... just like how chess branches are assessed by engines". It
  is "as deep as wikipedia itself", "till virus to even covid and ebola in some line's end".
- Ties go to the group "the user attempted earliest". New things are "extension of what he has seen".
  The helper runs on this PC first. Rs 200 a day while it is a demo. Twelve pictures on a sheet.
- At least four sub-divisions; with six, "we can do combinations of that level". A set that could also be
  solved another way (by era, by eating habits) "must not be allowed".
- He pointed to his June documents for these exceptions. Found there and not built: the check where a
  model lists every grouping a sharp child might try (`PRD.md` IV.2), the ranking of groups by fewest
  wrong guesses, then earliest, then fastest (III.4), and preparing the likeliest next sets while he
  plays (VI.0). This replaces the weekly job and the two-day mastery rule of 23 Nov. Built on 24 Nov:
  see "One game, dynamic data" in section 2. The Sunday task is switched off (it can be switched on again
  in Windows Task Scheduler).

---

## 4. Job runs and what they cost

| Run | What it did | Rupees |
|---|---|---|
| 6 Oct, 01 to 04 | Building and testing the job on Buildings; Shop, Bridge and Tower added | 30.6 |
| 6 Oct, 05 to 09 | Vegetable plants: thirteen plants | 59.7 |
| 6 Oct, 10 to 12 | Maize, fifteen vehicles, twelve things in the house; three redraws | 76.2 |
| 7 Oct, 01 | Broom, Mop, Sponge drawn; every proposed field refused by a test that was too strict | 22.4 |
| 7 Oct, 02 | One field passed on padded groups and was withdrawn | 38.5 |
| 7 Oct, 03 | First run with the library: four fields; Mammals opened; 35 things | 115.6 |
| 7 Oct, 04 | Stopped by hand before it drew anything | 0.5 |
| 7 Oct, 05 | Birds opened | 12.0 |
| 7 Oct, 06 | Toys and Buildings opened; 19 things | 54.8 |
| 7 Oct, 07 and 08 | Top-ups; Places on land could not be filled | 17.5 |
| 7 Oct, 09 | Port drawn again | 5.2 |
| | **All job runs** | **433.0** |

Other spending, approximate: pictures before the job about 352; research and benchmarks about 90; clues
and explanations about 13.5; probes about 7. **About 900 rupees in all.** Kokoro costs nothing.

---

## 5. Taken out after looking, and why

All are kept in the catalogue, marked, with their pictures.

| Thing | Why |
|---|---|
| Pumpkin seeds | A part of Pumpkin plant, already in the game |
| Lady finger plant | Ladies finger plant again, under another spelling |
| Wet soil, Muck, Wet dirt | Other names for mud |
| Shrine | Its picture is a prayer cabinet in a house, not a building |
| Health centre | Its picture cannot be told from Clinic |
| Plain | Its picture cannot be told from Meadow |
| Ground | Its picture is a patch of soil |
| Cockatiel | Failed the familiarity check when asked again |
| Taxi stand | Its picture is a row of vehicles, not a building |
| Skipping rope, Hula hoop | Filed with toys we throw, kick or bat, and neither is |

Withdrawn field: "What happens when it gets wet?" for Rocks and soil. It had passed on groups padded with
other names for mud.

---

## 6. Open

**Waiting for the owner**
- The playtest fixes for Peacock, Mustard, Horse and Rabbit, and the weak toys. They did not reach the
  assistant, so nothing was changed for them.
- His own test of the end-of-board button, the clue button, the explanations and the clips in a browser.
- Listening to the fourteen flagged names, the five renamed toys, and the 200 clue and explanation clips.
- A glance at the picture review sheets in `tools/pictures/preview/`.
- Watching the film with the sound on. It was made without hearing it: `tools/film/README.md` lists what
  to listen for.
- A decision the film brought up: the explanation of the last group found stays at the foot of the screen
  until the next group is found. With a clue showing too, the lowest row of pictures is partly under them
  on a small tablet. Nothing was changed. One way: let the explanation leave when he touches the next
  picture.

- **Glass is filed under the article about glass the material** (since 6 Oct), so the pages it was
  settled from are not about a drinking glass. Its look is now drawn from its typical look; its fields
  could be settled again from the right page.
- The weekly run uses the progress file a grown-up last saved into `tools/job/progress.json`. None has
  been saved yet, so until one is, the job treats every open board as solved and knows nothing of his
  mastery.

- **Land grazers has no set** (see section 2): there are not four groups of four well-known plant-eating
  dinosaurs by any question tried. The bar for "well-known" is 0.4 (`WELL_KNOWN_ENOUGH` in
  `tools/prepare_next.py`); lowering it lets lesser-known dinosaurs in. The owner's to say.
- A sharp child could sort one sample in three of Animals and of Vehicles by number of legs or wheels
  (the clever-kid check). The game's own test cannot see this, because legs and wheels are not stored.
- The helper's choice of the next set to make has only been driven by test progress, not by a child.

**Closed for a reason**
- Places on land: only Beach, Island and River bank are familiar land beside water. No filler was added.
- No field passes for: Rocks and soil, Things in the sky, Water, Reptiles, Insects, Fish, Trees, Flowers,
  Grasses and grains, Tools.
- No clues yet for: Insects, Land grazers, Trees, Grasses and grains, Buildings. No explanation yet for
  those and eight more. Running `python tools/content/group_words.py` tries them again.
- Deeper circles wait behind the depth rule. Amphibians has three things and stays off the board.

**Agreed, not built**
- The odd-one-out and true-or-false games.
- An AI review of every board's groupings as text, with corrections applied, logged and undoable. The
  owner said later, not now.
- The spoken question, naming another real grouping, greeting a returning thing.
- Sending saved progress from the device by itself. Today a grown-up saves the file.
- A timetable for the job. Each run is still one command.
- Circles of prehistoric animals, which need the feature research first.

**Known flaws, accepted**
- Tylosaurus has a pale knob on its snout tip. Brontosaurus has a short tail.
- On plain white nothing shows size: Titanoboa looks like an anaconda, Vasuki indicus like a python.
- The Star tile stays on its dark patch, by the owner's choice.
- `PRD.md` is out of date. The old data (`Assets/data/animals/`) and old scripts (`tools/generate/`) stay
  until the first child has played the new version.

---

## 7. Commands

| To do this | Run this |
|---|---|
| Start the game | `flutter run -d web-server --web-port 8123 --web-hostname 127.0.0.1`, then open http://localhost:8123 |
| See what the job would do, spending nothing | `python tools/prepare_next.py --dry-run` |
| Prepare the next level | `python tools/prepare_next.py` |
| The weekly run (Sundays 11:00, at most 200 rupees a week) | runs by itself; its digest is in `tools/job/weekly/LATEST.md`. By hand: `python tools/job/weekly.py`; plan only: `--dry-run`; register again: `--install` |
| Take a run back | `python tools/prepare_next.py --undo RUN` |
| Take one field back | `python tools/prepare_next.py --withdraw-field FIELD --why "..."` |
| Take one thing out | `python tools/catalogue/catalogue.py take-out "NAME" --why "..."` |
| Check the data | `python tools/content/guard.py` |
| See which circles can open | `python tools/catalogue/catalogue.py circles` |
| What waits for the owner; what the rules hold | `python tools/catalogue/catalogue.py queue` ; `... held` |
| How a thing looks, from its sources | `python tools/research/looks.py NAME ... --group "Animals > Birds" --cap-inr 5` (the job runs it by itself) |
| Serve the game with sets made ahead of the child | `flutter build web` once, then `python tools/live/helper.py` and open http://localhost:8200 (`--lan` for a tablet on the same Wi-Fi; `--no-making` to spend nothing) |
| Make one named set by hand | `python tools/prepare_next.py --only CIRCLE --new-to-him --cap 90` |
| Write missing clues and explanations | `python tools/content/group_words.py` |
| Record missing voices | `python tools/voice/record_names.py` |
| Make the film again | `python tools/film/film_voice.py`, then `flutter test tools/film/film_game_test.dart --dart-define=SEED=40`, then `python tools/film/film_make.py` |
| Make the picture of the game again | `python tools/illustration/game_map_data.py`, then `blender --background --python tools/illustration/game_map_blender.py -- docs/game_map.png` |
| Run the tests | `flutter test` ; `python tools/job/selftest.py` ; `python tools/catalogue/selftest.py` ; `python tools/pictures/selftest.py` |

---

## 8. Day by day

**6 Oct 2026**
- Fresh start: dictionary version 1 and 105 things; the game switched to the new data.
- One style for each board, the one-clean-solution test, the expansion engine.
- Dictionary version 2: kinds of plant, nature and made thing.
- Picture pipeline, trial sheets, then a drawn tile for every thing. Originals moved to Git LFS.
- Solved groups show pictures.
- Research as scripts; the benchmark; grounded facts; hard caps.
- The catalogue.
- The one-command job, rehearsed on Buildings.
- Vegetable plants (version 3), then Vehicles and Things in the house (version 4).

**7 Oct 2026**
- Saved progress on the device.
- The system runs itself: the four tests, the digest, undo.
- The field library. Mammals and Birds opened by the rules.
- The library strengthened; Toys and Buildings opened.
- `make_board` and `fetch_nodes`; the end-of-board button; the parallel board; orders.
- Every name recorded with Kokoro.
- The owner's rulings: four groups stay; Port redrawn; the music toys renamed.
- Clues and explanations.

**8 Oct 2026**
- This record started.
- A picture of what the game holds, made in Blender: `docs/game_map.png`.
- A film of how the game is played: `docs/how_the_game_is_played.mp4`. The card that ends a board now
  comes onto the screen by itself.

**23 Nov 2026**
- Less height spent on the game's screen: the title bar, the question, the found groups, the card
  that ends a board.
- Mastery on the device; the button after a board goes deeper where he has shown mastery four times in
  five; the job orders its work the same way; a weekly run of the job, 200 rupees a week at most.
- Fixed: `prepare_next.py --progress FILE` stopped with an error for any file named on the command line.

**24 Nov 2026**
- No hard-coding: the job no longer names any kind of thing; every thing is drawn from what its sources
  say it looks like, and checked against them. Deeper dinosaur circles are planned like any other.
- The owner restated the direction: one game, dynamic data, a buffer of prepared sets (see section 3).
- A trial sheet of twelve pictures: it works, at Rs 1.4 a picture.
- One game, dynamic data: the ranking and the lines, the helper, the live link, the clever-kid check;
  the first set made while "playing" (Wild animals on land). Spent on the day: about Rs 93.
