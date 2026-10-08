# What has been done

A running record of the work on the learning game, kept in the project so it can be read without any chat.
It is updated after each piece of work. The fuller story, with the reasons, is in the Claude Doc
"The Learning Engine" (https://claude.ai/code/artifact/c3f3f0d3-5f91-4df4-8786-d894ef1d12df).

Last updated: 8 Oct 2026. Branch: `fresh-start`. The live site (branch `main`) has not been touched.

---

## 1. Where things stand

| | |
|---|---|
| Things in the game | 243, each with a drawn picture and a spoken name |
| Things recorded in all | 336 (62 held by the rules, 23 taken out and kept, 5 kept for later by the owner, 3 ruled out) |
| Boards a child can open | 13 |
| Dictionary | version 10, 19 fields (one withdrawn) |
| Field library | 32 questions, 2 retired, 3 three-way splits parked |
| Groups a child can meet | 57: 52 have a ladder of clues, 44 have an explanation |
| Tests | 47 in the game, 28 for the job, 8 for the catalogue, 10 for the pictures. All pass |

**The thirteen boards:** Everything, Animals, Mammals, Birds, Dinosaurs, Plants, Vegetable plants,
Things in nature that are not alive, Things people make, Vehicles, Toys, Things in the house, Buildings.

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
- After a solved board one button takes the child on: Dig deeper into the branch he has visited least, or,
  where nothing is deeper, a parallel board at the same depth, not recently seen.
- A fresh board is never the same sixteen again, where another is possible.
- **Clue button:** one step up a ladder of three clues for the group he is working on. A clue never names
  a tile and never costs a star.
- **Explanation:** when a group is found, the game shows and speaks why its things belong together, with
  one true fact.
- **The card that ends a board comes onto the screen by itself** (8 Oct). Under four solved groups it
  stood below the edge of a phone or small tablet, and the button that leads on had to be found by
  scrolling. Found while filming the game; tested at three screen sizes.
- **Saved progress:** boards opened and solved are kept on the device. A long press on the title opens a
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
| Take a run back | `python tools/prepare_next.py --undo RUN` |
| Take one field back | `python tools/prepare_next.py --withdraw-field FIELD --why "..."` |
| Take one thing out | `python tools/catalogue/catalogue.py take-out "NAME" --why "..."` |
| Check the data | `python tools/content/guard.py` |
| See which circles can open | `python tools/catalogue/catalogue.py circles` |
| What waits for the owner; what the rules hold | `python tools/catalogue/catalogue.py queue` ; `... held` |
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
