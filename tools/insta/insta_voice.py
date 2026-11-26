"""The sound the Instagram reel needs before it is filmed.

1. The narrator. Each line of insta.voice.json is spoken by the voice the file names:
   ElevenLabs (since 26 Nov 2026, the owner's word: "use 11 labs voice... something a bit more
   soothing"; Bella, with the calm settings of his Glym films) or Kokoro (the owner's installation at
   D:/Projects/Kokoro, used where it stands). ElevenLabs is sent each line with the lines before and
   after it, so the delivery runs on as one; its key is read from ELEVENLABS_API_KEY and never
   printed or written. Inner silences are capped and the ends trimmed, as in the Glym films. A line
   that has a clip and has not changed is not spoken again, so a run costs nothing unless a line
   changed (ElevenLabs counts characters from the owner's plan: about 300 for all six lines).
       tools/insta/out/voice/<id>.mp3, tools/insta/out/voice/manifest.json
2. The game's own clips, measured, so that the film lets each one finish as the game does.
       tools/insta/out/game_audio.json

    python tools/insta/insta_voice.py           speak what is missing or changed
    python tools/insta/insta_voice.py --again   speak every line again
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "film"))
import film_voice  # noqa: E402  the game's clips are measured as for the game's other film

LINES = HERE / "insta.voice.json"
OUT = HERE / "out"
PAUSE_CAP = 0.18        # seconds of silence kept anywhere inside a line
SILENCE_DB = "-45dB"
LEAD_PAD, TAIL_PAD = 0.04, 0.15


def tighten(raw: pathlib.Path, path: pathlib.Path):
    """Inner silences capped, the ends trimmed to a little air; from the untouched clip, so it never costs a re-voice."""
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-af",
                    f"silenceremove=start_periods=1:start_threshold={SILENCE_DB}:start_silence={LEAD_PAD}:"
                    f"stop_periods=-1:stop_duration={PAUSE_CAP}:stop_threshold={SILENCE_DB},"
                    f"areverse,silenceremove=start_periods=1:start_threshold={SILENCE_DB}:start_silence={TAIL_PAD},areverse",
                    "-c:a", "libmp3lame", "-b:a", "160k", str(path)], check=True, capture_output=True)
    if film_voice.seconds(path) < 0.2:
        path.write_bytes(raw.read_bytes())


def eleven(spec: dict, text: str, previous: str, following: str, out: pathlib.Path):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set")
    body = {"text": text, "model_id": spec["model"], "voice_settings": spec["settings"]}
    if previous:
        body["previous_text"] = previous
    if following:
        body["next_text"] = following
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{spec['voice']}?output_format=mp3_44100_128",
        data=json.dumps(body).encode("utf-8"),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            out.write_bytes(response.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"ElevenLabs returned {e.code} for '{text}': {e.read().decode('utf-8', 'replace')[:300]}")


def cue_times(clip: pathlib.Path, cues: list) -> list:
    """The start of each cue word in the clip, in order, from Whisper's word times (on the GPU)."""
    from faster_whisper import WhisperModel
    model = WhisperModel("medium.en", device="cuda", compute_type="float16")
    segments, _ = model.transcribe(str(clip), word_timestamps=True)
    words = [(w.word.strip(" .,?!").lower(), w.start) for s in segments for w in s.words]
    out, k = [], 0
    for cue in cues:
        while k < len(words) and not words[k][0].startswith(cue[:4]):
            k += 1
        if k == len(words):
            sys.exit(f"the cue '{cue}' was not heard in {clip.name}: {[w for w, _ in words]}")
        out.append(round(words[k][1], 3))
        k += 1
    return out


def narrator(again: bool):
    spec = json.loads(LINES.read_text(encoding="utf-8"))
    if spec.get("provider") != "elevenlabs":     # Kokoro: the game's other film's speaker does it
        film_voice.LINES, film_voice.OUT = LINES, OUT
        film_voice.narrator(again)
        return
    folder = OUT / "voice"
    folder.mkdir(parents=True, exist_ok=True)
    manifest_file = folder / "manifest.json"
    old = json.loads(manifest_file.read_text(encoding="utf-8")) if manifest_file.exists() else {"lines": {}}
    who = {"provider": "elevenlabs", "voice": spec["voice"], "model": spec["model"], "settings": spec["settings"]}
    same_voice = old.get("who") == who
    said = [line.get("say", line["text"]) for line in spec["lines"]]
    lines, spoken = {}, 0
    for i, line in enumerate(spec["lines"]):
        clip, raw = folder / f"{line['id']}.mp3", folder / f"{line['id']}.raw.mp3"
        before = old["lines"].get(line["id"], {})
        if again or not same_voice or not clip.exists() or before.get("said") != said[i]:
            eleven(spec, said[i], said[i - 1] if i else "", said[i + 1] if i + 1 < len(said) else "", raw)
            tighten(raw, clip)
            spoken += 1
        lines[line["id"]] = {"label": "", "text": line["text"], "said": said[i], "clip": clip.name,
                             "seconds": film_voice.seconds(clip)}
        if line.get("cues"):     # when, in the clip, each cue word is said: the film touches each picture then
            before_cues = before.get("cue_times") if before.get("said") == said[i] and not again else None
            lines[line["id"]]["cue_times"] = before_cues or cue_times(clip, line["cues"])
    manifest_file.write_text(json.dumps({"who": who, "lines": lines}, indent=1, ensure_ascii=False) + "\n",
                             encoding="utf-8", newline="\n")
    total = sum(line["seconds"] for line in lines.values())
    print(f"narrator: {len(lines)} lines ({spoken} spoken now, {sum(len(said[i]) for i in range(len(said)))} characters "
          f"in all), {total:.1f} s of speech, ElevenLabs {spec.get('voice_name', spec['voice'])}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--again", action="store_true", help="speak every line again")
    args = parser.parse_args()
    narrator(args.again)
    film_voice.OUT = OUT
    film_voice.game_clips()
