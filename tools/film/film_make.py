"""Lays the sound under the frames and writes the film. It costs nothing.

The frames and events.json come from film_game_test.dart. events.json says on which frame
the narrator starts each line and on which frame the game itself began which clip. Here
the narrator's clips (tools/film/out/voice) and the game's own clips (Assets/audio, as
shipped) are laid at those moments, and the frames are made into an MP4.

A clip of the game's that is still being heard when the film cuts forward is faded out at
the cut. A clip the game began inside a stretch that was cut is not heard, as its picture
is not seen. Nothing else is done to the game's voice but to bring every clip to one
loudness, the narrator's too, so that no clip is much louder than the next.

    python tools/film/film_make.py                 -> docs/how_the_game_is_played.mp4
    python tools/film/film_make.py --out FILE
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tools/film/out"
FRAMES = OUT / "frames"
LEVEL = -18.0       # every clip is brought to this mean loudness, in dB
FADE = 0.35         # how long a clip takes to fade where the film cuts forward
HEARD_AT_LEAST = 0.6    # a clip that would be cut off sooner than this is not started at all


def mean_volume(path: pathlib.Path) -> float:
    done = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    found = re.search(r"mean_volume: (-?[0-9.]+) dB", done.stderr)
    return float(found.group(1)) if found else LEVEL


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "docs/how_the_game_is_played.mp4"))
    args = parser.parse_args()

    events = json.loads((FRAMES / "events.json").read_text(encoding="utf-8"))
    voice = json.loads((OUT / "voice/manifest.json").read_text(encoding="utf-8"))["lines"]
    every, fps = events["every"], events["fps"]
    length = events["frames"] / fps
    cuts = sorted(cut["t"] for cut in events["cuts"])

    clips = []      # (file, starts at, heard for or None, what it is)
    for said in events["voice"]:
        line = voice[said["id"]]
        if line["clip"]:
            clips.append((OUT / "voice" / line["clip"], said["t"], None, "narrator: " + said["id"]))
    left_out = faded = 0
    for heard in events["game"]:
        if not heard["filmed"]:
            left_out += 1
            continue
        start, lasts = heard["t"], heard["seconds"]
        cut = next((c for c in cuts if start < c < start + lasts), None)
        if cut is not None and cut - start < HEARD_AT_LEAST:
            left_out += 1
            continue
        if cut is not None:
            faded += 1
        clips.append((ROOT / heard["asset"], start, None if cut is None else cut - start, "game: " + heard["asset"]))
    clips.sort(key=lambda clip: clip[1])

    # no two voices at once: the film must never have the narrator over the game, or the game over itself
    until, last = 0.0, ""
    for path, start, lasts, what in clips:
        if start < until - 0.05:
            sys.exit(f"two voices at once at {start:.1f} s: {what} begins while {last} is still heard")
        seconds = lasts if lasts is not None else float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
            capture_output=True, text=True, check=True).stdout)
        until, last = start + seconds, what

    command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-framerate", f"{fps}/{every}",
               "-i", str(FRAMES / "f%05d.png")]
    parts, names = [], []
    for i, (path, start, lasts, what) in enumerate(clips, start=1):
        command += ["-i", str(path)]
        gain = max(-12.0, min(12.0, LEVEL - mean_volume(path)))
        chain = ["aformat=sample_rates=48000:channel_layouts=stereo", f"volume={gain:.1f}dB"]
        if lasts is not None:
            chain += [f"atrim=0:{lasts:.3f}", f"afade=t=out:st={max(0.0, lasts - FADE):.3f}:d={FADE}"]
        chain.append(f"adelay={round(start * 1000)}:all=1")
        parts.append(f"[{i}:a]{','.join(chain)}[a{i}]")
        names.append(f"[a{i}]")
    parts.append(f"{''.join(names)}amix=inputs={len(names)}:normalize=0:dropout_transition=0,"
                 f"alimiter=limit=0.9,apad,atrim=0:{length:.3f}[sound]")
    parts.append("[0:v]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[picture]")
    script = OUT / "sound.txt"
    script.write_text(";\n".join(parts), encoding="utf-8")
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    command += ["-filter_complex_script", str(script), "-map", "[picture]", "-map", "[sound]",
                "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-r", str(fps),
                "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", f"{length:.3f}", str(out)]
    done = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if done.returncode != 0:
        sys.exit("ffmpeg failed:\n" + done.stderr[-3000:])
    minutes, seconds = divmod(round(length), 60)
    print(f"{out}: {minutes} min {seconds:02d}, {out.stat().st_size / 1e6:.1f} MB")
    print(f"sound: {sum(1 for c in clips if c[3].startswith('narrator'))} lines of the narrator, "
          f"{sum(1 for c in clips if c[3].startswith('game'))} clips of the game ({faded} faded at a cut); "
          f"{left_out} clips the game played inside the cuts are not heard")


if __name__ == "__main__":
    main()
