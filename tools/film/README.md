# The film: how the game is played

`docs/how_the_game_is_played.mp4`: 1920 x 1080, 30 frames a second, 2 min 48, 13.3 MB,
made 8 Oct 2026. It has been shown to nobody but the owner. The film itself is not
in git (it is a large file that changes with every cut); everything that makes it is.

Asked for by the owner on 8 Oct 2026: "generate video of how the game will be played", with
the Glym film for SATisfactory as the thing to be parallel to. So it is built the same way:
the app itself on the left, played for real; one plain line on the right; a voice; a last
card.

## What happens in it

| From | Scene | The narrator (also on screen) |
|---|---|---|
| 0:00 | Title, with four of the game's own tiles | none |
| 0:04 | The first board: sixteen pictures | The game opens on sixteen pictures. Hidden in them are four groups of four. |
| 0:11 | A touch on a picture; the game says "Sheep" | Touch a picture, and the game says its name. |
| 0:17 | Three more animals are touched, each named | The child looks for four that belong together. |
| 0:28 | Submit. The four become one bar. The game says "right", then its explanation of Animals, in full | Four are chosen. Then, Submit. (While the game speaks, the screen says: The game says why they belong together, and adds one true thing. The narrator keeps quiet.) |
| 0:46 | Three plants and a field are chosen. The game: "So close! You're one away!" | A wrong guess is answered kindly. Try again. |
| 1:01 | The Clue button, twice: the first clue for Plants, then the second | Stuck? There is a clue. / And then a clearer one. / A clue never names a picture, and never costs a star. |
| 1:24 | The plants are found. Cut: the third group, and the fourth chosen | none |
| 1:32 | Submit. The board is done: stars, "You did it!" | Group by group, until the board is done. |
| 1:39 | The button "Dig deeper: Animals"; the second board | Then one button leads on: Dig deeper. / Now every picture is an animal, and the question is finer. |
| 1:51 | Cut to that board solved; "Dig deeper: Mammals"; the third board; the pets are found | Deeper again: inside the mammals. |
| 2:05 | Cut to the third board solved | One idea on every board, and a finer one at each step down. |
| 2:11 | The button "Next board"; a board of birds | Where nothing is deeper yet, the button brings another board. No waiting. |
| 2:18 | The map of the whole game; the path just played is ringed | This is the whole game today: 243 things, on 13 boards. / From Everything, to Animals, to Mammals: that was the path just played. / The grey ones have no board inside them yet. The game is still growing. |
| 2:40 | The last card | Touch to hear. Choose four. Dig deeper. |

The times are those of the cut of 8 Oct; `tools/film/out/frames/events.json` has the exact ones.

## What is the real thing, and what is drawn by the film

Real: the game. `film_game_test.dart` starts the game's own screen in the game's own theme
(`appTheme()` and `ResponsiveWrapper` from `lib/main.dart`, `EngineScreen`, `EngineProvider`),
with the things, pictures, clues and explanations as shipped, on a screen of 600 by 960 (a
small tablet held upright). It is played by presses a finger would make, through Flutter's
gesture system, and every frame is saved. The boards are dealt by the game's own board
maker from a fixed seed (40), so the film can be made again. Every sound of the game in
the film is the clip the game asked its player for, at the moment it asked: the names, the
clues, the explanation (Kokoro, `bf_emma`), and the older "right", "one away" and "you did
it" clips. The game's sound queue runs for real, so a clip waits for the one before it as
on a device. The map is `docs/game_map.png`, made in Blender from the game's data.

Drawn by the film: the tablet's frame; the soft dot where the finger is; the narrator's
line; the box "The game says", which shows the words of the clip being heard, for a viewer
with the sound off; the rings on the map; the title and the last card.

Left out: four stretches of play, each a dissolve. The game lived through them (167 s in
all): the rest of each board being solved, and the explanations that follow. A clip the
game began inside a cut is not heard.

One thing differs from a child's device: the stars on "You did it!" are drawn with this
computer's emoji (Segoe UI Emoji). A browser or a tablet draws its own.

## What the film showed about the game

- **Fixed.** When the fourth group was found, the card "You did it!" with the button that
  leads on stood below the edge of a phone or small tablet screen, and a child would have
  had to scroll to find it. The card now comes onto the screen by itself
  (`_ShowOnScreen` in `lib/screens/engine_screen.dart`; three tests in
  `test/next_board_test.dart`).
- **Not changed, for the owner to decide.** The explanation of the last group found stays
  at the foot of the screen until the next group is found. With a clue showing as well, the
  lowest row of pictures is partly under them on a 600 by 960 screen (see the film at
  about 1:05 to 1:28). The finger in the film touches the part of the picture that shows,
  as a child would.
- The narrator says a wrong guess is "answered kindly". It does cost a star: three stars
  with no wrong guess, two after one or two, one after more. The film shows two stars on
  the first board and says nothing false, but it does not explain the stars.

## To check by ear (the film was made without hearing it)

- The narrator (Kokoro `bm_george`): "Stuck? There is a clue."; "Dig deeper"; "243" and "13"
  (given to Kokoro in words); the three short sentences of the last card.
- That the narrator's voice and the game's are easy to tell apart, and neither is much
  louder. Every clip is brought to one loudness (`LEVEL` in `film_make.py`); the whole
  track measures about -16 LUFS.
- The older clips (in this cut: "Awesome! You're so smart!", "So close! You're one away!",
  "Hooray! You won the game!", "Yay! You found a match!") are in a different voice from
  the names and clues. That is how the game is today. The game picks one of several at
  random each time, so another making of the film will have others, and its times will
  differ by parts of a second.
- There is no music.

## To make it again, or change it

    python tools/film/film_voice.py              the narrator's clips (Kokoro), and the length of the game's clips
    flutter test tools/film/film_game_test.dart --dart-define=SEED=40      the frames, about twelve minutes
    python tools/film/film_make.py               the sound laid under them -> docs/how_the_game_is_played.mp4

It costs nothing. A quick look first, in about a minute:

    flutter test tools/film/film_game_test.dart --dart-define=SEED=40 --dart-define=EVERY=6 --dart-define=WIDTH=960
    python tools/film/film_make.py --out tools/film/out/preview.mp4

| To change | Where |
|---|---|
| What the narrator says | `how_it_is_played.voice.json`, then all three commands. The film waits for each line, so the times follow. |
| The narrator's voice or pace | `voice` and `speed` in the same file. Only voices already in `D:\Projects\Kokoro` can be used. |
| What is played, and where the cuts are | the test at the foot of `film_game_test.dart`, written as a list of steps |
| Another deal of the boards | `--dart-define=SEED=n`; `--dart-define=SCOUT=40` prints what seeds 1 to 40 would deal. The film needs mammals on the second board and stops with a clear message if they are not there. |
| The look: sizes, places, colours | the constants and `_Stage` in `film_game_test.dart` |
| The map | `tools/illustration` (see `WORK_DONE.md`); the film reads `docs/game_map.png` and `game_map_points.json` |

The game's two fonts (Quicksand and Inter) are fetched by the game's own font package the
first time, exactly as when the game runs, and kept in `tools/film/out/fonts`. Everything
under `tools/film/out` is left out of git.
