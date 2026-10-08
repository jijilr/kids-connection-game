"""The sound the film needs to know about before it is filmed. It costs nothing.

1. The narrator. Each line of how_it_is_played.voice.json is spoken by Kokoro, the owner's
   own installation at D:\\Projects\\Kokoro, used where it stands (nothing of it is downloaded,
   installed or copied). The speaking is done by tools/voice/kokoro_clips.py, run by
   Kokoro's own Python. A line that has a clip and has not changed is not spoken again.
       tools/film/out/voice/<id>.wav, tools/film/out/voice/manifest.json
2. The game's own clips. How long each one is and what it says, so that the film can let a
   clip finish as the game does, and can show its words for a viewer with the sound off.
       tools/film/out/game_audio.json

    python tools/film/film_voice.py            speak what is missing or changed
    python tools/film/film_voice.py --again    speak every line again
"""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "out"
LINES = HERE / "how_it_is_played.voice.json"
SPEAKER = ROOT / "tools/voice/kokoro_clips.py"
MAP = ROOT / "tools/illustration/game_map.json"

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen " \
       "seventeen eighteen nineteen".split()
TENS = "twenty thirty forty fifty sixty seventy eighty ninety".split()


def in_words(n: int) -> str:
    """A number as it is said, up to 999: 243 -> two hundred and forty-three."""
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10 - 2] + ("-" + ONES[n % 10] if n % 10 else "")
    rest = n % 100
    return ONES[n // 100] + " hundred" + (" and " + in_words(rest) if rest else "")


def numbers() -> dict:
    """What the film says about the size of the game comes from the map's own data."""
    data = json.loads(MAP.read_text(encoding="utf-8"))
    return {"things": data["things"], "boards": data["boards"],
            "things_said": in_words(data["things"]), "boards_said": in_words(data["boards"])}


def seconds(path: pathlib.Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True)
    return round(float(out.stdout.strip()), 3)


def narrator(again: bool) -> None:
    spec = json.loads(LINES.read_text(encoding="utf-8"))
    facts = numbers()
    folder = OUT / "voice"
    folder.mkdir(parents=True, exist_ok=True)
    manifest_file = folder / "manifest.json"
    old = json.loads(manifest_file.read_text(encoding="utf-8")) if manifest_file.exists() else {"lines": {}}
    same_voice = (old.get("voice"), old.get("speed")) == (spec["voice"], spec["speed"])
    lines, wanted = {}, []
    for line in spec["lines"]:
        text = line["text"].format(**facts)
        said = line.get("say", line["text"]).format(**facts)
        clip = folder / f"{line['id']}.wav"
        before = old["lines"].get(line["id"], {})
        if line.get("shown_only"):      # on screen while the game speaks; the narrator keeps quiet
            lines[line["id"]] = {"label": line.get("label", ""), "text": text, "said": "", "clip": None}
            continue
        lines[line["id"]] = {"label": line.get("label", ""), "text": text, "said": said, "clip": clip.name}
        if again or not same_voice or not clip.exists() or before.get("said") != said:
            wanted.append({"key": line["id"], "text": said, "out": str(clip)})
    if wanted:
        kokoro = pathlib.Path(spec["kokoro"])
        with tempfile.TemporaryDirectory() as temp:
            listing, result = pathlib.Path(temp) / "list.json", pathlib.Path(temp) / "result.json"
            listing.write_text(json.dumps({"kokoro": str(kokoro), "voice": spec["voice"], "speed": spec["speed"],
                                           "clips": wanted}, ensure_ascii=False), encoding="utf-8")
            done = subprocess.run([str(kokoro / ".venv/Scripts/python.exe"), str(SPEAKER), str(listing), str(result)],
                                  capture_output=True, text=True, encoding="utf-8", errors="replace")
            if done.returncode != 0 or not result.exists():
                sys.exit("Kokoro did not run:\n" + (done.stderr or done.stdout)[-1500:])
            report = json.loads(result.read_text(encoding="utf-8"))
        if report["failed"]:
            sys.exit("Kokoro could not speak: " + json.dumps(report["failed"], ensure_ascii=False))
        print(f"  spoken: {len(wanted)} line(s), on {report['device']}")
    for key, line in lines.items():
        line["seconds"] = seconds(folder / line["clip"]) if line["clip"] else 0.0
    manifest_file.write_text(json.dumps({"voice": spec["voice"], "speed": spec["speed"], "lines": lines},
                                        indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    total = sum(line["seconds"] for line in lines.values())
    print(f"narrator: {len(lines)} lines, {total:.1f} s of speech, voice {spec['voice']} -> {manifest_file.relative_to(ROOT)}")


def game_clips() -> None:
    """Every clip the game can play in the film: its length, and its words."""
    things = json.loads((ROOT / "Assets/data/things.json").read_text(encoding="utf-8"))["things"]
    groups = json.loads((ROOT / "Assets/data/groups.json").read_text(encoding="utf-8"))["groups"]
    words = {}
    for key, thing in things.items():
        words[f"Assets/audio/names/name_{key}.mp3"] = ("name", thing.get("shown_as") or thing["name"])
    for group in groups.values():
        for i, clue in enumerate(group.get("clues") or []):
            if clue.get("audio"):
                words[clue["audio"]] = (f"clue {i + 1}", clue["text"])
        explanation = group.get("explanation") or {}
        if explanation.get("audio"):
            words[explanation["audio"]] = ("explanation", explanation["text"])
    tasks = ROOT / "audio_tasks.json"       # the older list that made the game's "right" and "wrong" clips
    if tasks.exists():
        for task in json.loads(tasks.read_text(encoding="utf-8")):
            path = task.get("output", "").replace("\\", "/")
            if "/feedback/" in path and task.get("text"):
                words[path] = ("feedback", task["text"])
    out_file = OUT / "game_audio.json"
    old = json.loads(out_file.read_text(encoding="utf-8")) if out_file.exists() else {}
    clips = {}
    for folder in ("names", "groups", "feedback"):
        for path in sorted((ROOT / "Assets/audio" / folder).glob("*.mp3")):
            key = path.relative_to(ROOT).as_posix()
            stamp = path.stat().st_mtime_ns
            before = old.get(key, {})
            length = before["seconds"] if before.get("stamp") == stamp else seconds(path)
            kind, text = words.get(key, ("", ""))
            clips[key] = {"seconds": length, "kind": kind, "text": text, "stamp": stamp}
    OUT.mkdir(parents=True, exist_ok=True)
    out_file.write_text(json.dumps(clips, indent=0, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"the game's clips: {len(clips)} measured, {sum(1 for c in clips.values() if c['text'])} with their words "
          f"-> {out_file.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--again", action="store_true", help="speak every line again")
    args = parser.parse_args()
    narrator(args.again)
    game_clips()
