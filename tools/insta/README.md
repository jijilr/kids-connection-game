# The Instagram reel of the game

`docs/insta_connections.mp4`: upright, 1080 x 1920, 30 frames a second, about 46 seconds; its cover is
`docs/insta_connections_cover.jpg`. Neither is in git (large, and made again with every cut); everything
that makes them is.

Asked for by the owner on 26 Nov 2026: "make an insta video of the game that way", pointing at his Glym
promos (`vocabulary_swipe_app/tool/deck_engine/blender`, read and never changed). After two cuts he said:
"the vocabulary app's details I had given was not for you to replicate (the wooden background) but to be
inspired and make better than that", and "supress the voice from the app and you tell what is that you are
clicking". This is the third cut, with one change after a review of it (below): the clue is given time.

The review said: "the clue frame is mostly hidden behind the 'Stuck?' caption. Let it show for a beat longer
so people can read 'Think about things you can see outside that are not alive.'" So once the clue appears the
"Stuck?" words go, the dark band over the top and the small name lift, the camera goes close on the clue's
words, and the narrator reads them aloud: about five seconds on the clue alone, where there had been two
and a half under the words.

## What happens in it

| From | On screen | The words over it | Heard |
|---|---|---|---|
| 0:00 | The sixteen real pictures of the first set float as cards in front of the phone, then fly in, each onto its own tile, as the screen wakes | **16 pictures. 4 hidden groups.** then *Can your child find them?* | The narrator says the same; a breath of air as the cards fly |
| 0:05 | The finger touches each animal as it is named; Submit; "Yes! Animals" | Find four that belong together. | "Dog. Hen. A fish. And a stegosaurus." A chime. "Yes! Four animals." |
| 0:11 | Coconut tree, grass, rose and soil; Submit; "So close, one away!" | **Wrong?** It tells him how close he was. | "Coconut tree. Grass. Rose. And... soil?" A low note. "So close. One away." |
| 0:18 | The Clue button; the clue appears | **Stuck?** A clue, never the answer. | The narrator |
| 0:22 | Close on the clue's words, nothing over them | (none) | The narrator reads the clue: "Think about things you can see outside that are not alive." |
| 0:27 | Ten sets at five times speed, going deeper | Set after set, deeper and wider. A sign: "5x speed" | The narrator |
| 0:36 | His web on the phone; the phone slides away and the web grows in 3D behind it, knot by knot, each knot one of his own pictures, joined by threads of light in its branch's colour | Everything he finds grows his own web. | The narrator; a faint sparkle as each knot comes in |
| 0:41 | The whole web | **Connections.** A picture game that grows with your child. | The narrator |

## The look

The game's own studio, not a borrowed desk: a deep violet room in the game's colours, a glowing wall, a dark
glossy floor that mirrors the web, and soft lights in the four colours of the game's groups far behind, out of
focus. The phone stands in the light. The 3D web is the very web the game drew for him in the film (its knots
and threads, laid out as the game lays it out: `insta_web.py`), shown as the "threads of light" of the owner's
`TARGET_UI.md`. Built from nothing in Blender on every run (`insta_scene.py`).

## The sound

One voice: the narrator, ElevenLabs Bella with the calm settings of the Glym films (`insta.voice.json`). The
game's own voice is left out altogether, so nothing can overlap; the narrator says what is touched, and the
finger touches each picture as its name is said (Whisper finds when each name is said in the line:
`insta_voice.py`). Under her, quiet sounds made here from formulas (nothing borrowed, nothing to license): a
soft tap for each touch, a chime when a group is right, a low note when it is one away, a breath of air as the
pictures fly in, a faint sparkle as each knot of the web comes in. `insta_make.py` stops if two lines of the
narrator would ever overlap.

## What is real, and what is drawn

Real: the game on the phone. `insta_game_test.dart` starts the game's own screen in its own theme with the
things, pictures, clues and explanations as shipped, on a phone held upright (405 by 720 of the game's units),
and plays it by presses a finger would make. Automate is on, as on a new device, and the explanation is kept
small (the owner's own setting for a phone). The deal is seed 4: the narrator names its pictures, and the film
checks they are the ones it touches. The sixteen cards of the opening are the game's own pictures and names
from that deal, and the 3D web is his web as the game holds it at the end of the film.

Drawn: the studio, the phone, the cards in the air and the 3D web; the soft dot where the finger touches; the
words, the "5x speed" sign and the name at the top.

Left out, with a short dissolve on the phone's screen: the rest of the first set after the clue. In the fast
half every group is found at the first try, so each set's groups become lines and the game goes deeper.

## Not decided

- **Where to get the game.** The close has the name and one line; no address was given for the reel. One line
  in `CLOSE` in `insta_make.py` adds it.
- **Music.** None: no music the owner holds the rights to is in the project.
- **The caption and hashtags** for the post are not written.

## To make it again

    python tools/insta/insta_voice.py                     the narrator (ElevenLabs; only lines that changed are
                                                          spoken), and when each name is said
    flutter test tools/insta/insta_game_test.dart --dart-define=SEED=4      the game films itself (2 minutes)
    python tools/insta/insta_make.py --stills 0.3,6,20,36 a look at a few moments, at half size
    python tools/insta/insta_make.py                      the reel (about 35 minutes of Blender)

To change the words, edit `WORDS` and `CLOSE` in `insta_make.py` and run it again: rendered frames are kept,
so only the words, the sound and the encoding are done again. To change the camera or the set, or after the
game has filmed itself again, delete `tools/insta/out/frames` first (a new film replaces the phone's screen
track by itself). Space: about 0.6 GB in `tools/insta/out`; the finished frames are streamed into
the encoder, never saved.
