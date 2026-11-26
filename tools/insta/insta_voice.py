"""The sound the Instagram film needs before it is filmed. It costs nothing.

The narrator's lines (insta.voice.json) are spoken by Kokoro, the owner's own installation at
D:/Projects/Kokoro, used where it stands, through the same speaker as the game's other film
(tools/film/film_voice.py). And the game's own clips are measured, so that the film lets each
one finish as the game does.

    python tools/insta/insta_voice.py           speak what is missing or changed
    python tools/insta/insta_voice.py --again   speak every line again

Writes tools/insta/out/voice/<id>.wav, tools/insta/out/voice/manifest.json and
tools/insta/out/game_audio.json.
"""
import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "film"))
import film_voice  # noqa: E402  the same speaker and the same measuring, pointed at this film's files

film_voice.LINES = HERE / "insta.voice.json"
film_voice.OUT = HERE / "out"

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--again", action="store_true", help="speak every line again")
    args = parser.parse_args()
    film_voice.narrator(args.again)
    film_voice.game_clips()
