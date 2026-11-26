# The Instagram reel of the game

`docs/insta_connections.mp4`: upright, 1080 x 1920, 30 frames a second, about 51 seconds; its cover
is `docs/insta_connections_cover.jpg`. Neither is in git (large, and made again with every cut);
everything that makes them is.

Asked for by the owner on 26 Nov 2026: "make an insta video of the game that way", that way being
his Glym promos 4 and 8 (`vocabulary_swipe_app/tool/deck_engine/blender`, read and never changed):
the app's own film playing on a phone that lies on a desk, a camera that follows the story, words
over the top, a voice.

## What happens in it

Two halves (the owner, 26 Nov 2026: "let there be 2 halves... the first one as we have now, and the
second one is a bit more fast forwarded... such that when you show the diagram... it looks more rich").

| From | On the phone | The words over it | Heard |
|---|---|---|---|
| 0:00 | The first set: sixteen pictures, close | **16 pictures. 4 hidden groups.** then *Can your child find them?* | The narrator says the same |
| 0:05 | Two animals touched, each named | Touch a picture: it says its name. | The game: "Dog", "Hen" |
| 0:08 | The four animals, Submit: "Yes! Animals" over the set | Find four that belong together. | The game: "Wonderful, you got it" |
| 0:11 | Three plants and the soil, Submit: "So close, one away!" | **Wrong?** It tells him how close he was. | The game: "Nearly perfect, check one more time"; then the narrator |
| 0:19 | The Clue button; the clue appears | **Stuck?** A clue, never the answer. | The narrator; then the game reads its clue |
| 0:28 | Ten sets at five times speed: Animals, Plants, Vegetable plants, Mammals, Wild animals on land, Dinosaurs and others; the web opens once by itself after the fourth | Set after set, deeper and wider. A sign: "5x speed" | The narrator; the game's own sounds are left out while it runs fast |
| 0:40 | His web: "Your web grew", 35 ends, depth 2.5 on average, 4 at the deepest | Everything he finds grows his own web. | The narrator |
| 0:45 | The camera draws back to the desk | **Connections.** A picture game that grows with your child. | The narrator |

## What is real, and what is drawn

Real: the game. `insta_game_test.dart` starts the game's own screen in its own theme with the things,
pictures, clues and explanations as shipped, on a phone held upright (405 by 720 of the game's units),
and plays it by presses a finger would make. Automate is on, as on a new device, and the explanation is
kept small (the owner's own setting for a phone, 24 Nov 2026); it is still spoken. Every sound of the
game is the clip the game asked for, at the moment it asked. The deal is the first seed from 1 that
tells the story (seed 4 on 26 Nov 2026).

Drawn: the desk, the phone and the toys (Blender, `insta_scene.py`; the light and the wood are Poly
Haven's, CC0, listed in `set_sources.json`); the soft dot where the finger touches; the words, the
"5x speed" sign and the name at the top; the narrator: ElevenLabs Bella, with the calm settings of the
Glym films (the owner: "use 11 labs voice... something a bit more soothing"), from `insta.voice.json`.
The first cut's narrator was Kokoro `af_heart`, which said "Stuck?" as "Stock?".

The sound: the narrator and the game's clips take turns and never overlap; `insta_make.py` stops if two
would sound at once. On 26 Nov 2026 the finished sound was checked by drawing its loudness every tenth
of a second against the plan, and by having Whisper write down what is said. The game's "right" and "one
away" clips are in its older voice, not the voice of its names and clues.

Left out, each with a short dissolve on the phone's screen: two of the four animal touches, the rest of
the animals' explanation, the three plant touches before the wrong guess, and the rest of the set after
the clue. A clip the game began inside a cut, or while it ran fast, is not heard. In the fast half every
group is found at the first try, so each set's groups become lines and the game goes deeper.

## The rules it keeps (from the Glym shorts)

- Frame 0 already makes the promise in large type, readable without sound.
- Something moves from the first frame, and the voice starts at once.
- Within two seconds the viewer has something to do: find the four.
- The name is at the top from the first frame, but it is not the subject.
- The words stand above the phone, clear of Instagram's own buttons along the foot and the right edge.
- The narrator never speaks over the game.

## Not decided

- **Where to get it.** The Glym reels end on where to download the app. This one ends on the name and
  one line, because no address for getting the game was given for the reel. One line in `CLOSE` in
  `insta_make.py` adds it.
- **Music.** There is none: no music the owner holds the rights to is in the project.
- **The caption and hashtags** for the post are not written.

## To make it again

    python tools/insta/insta_voice.py                     the narrator (ElevenLabs, about 300 characters,
                                                          only for lines that changed), and the game's clips
    flutter test tools/insta/insta_game_test.dart         the game films itself (about 2 minutes)
    python tools/insta/insta_make.py --stills 1,9,24,32   a look at a few moments, at half size
    python tools/insta/insta_make.py                      the reel (about 35 minutes of Blender)

To change the words, edit `WORDS` and `CLOSE` in `insta_make.py` and run it again: the frames that are
already rendered are kept, so only the words, the sound and the encoding are done again. To change what
the narrator says, edit `insta.voice.json` and start from the top. To change the camera, edit the shots
in `make_times`, delete `tools/insta/out/frames`, and run `insta_make.py`.

Space: the screen's frames are kept as JPEG and the rendered frames too, and the finished frames are
streamed into the encoder, never saved; about 0.7 GB in `tools/insta/out` in all.
