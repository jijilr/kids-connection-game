"""The Instagram film of the game, end to end: an upright reel, 1080 x 1920, about 45 seconds.

Asked for by the owner on 26 Nov 2026: "make an insta video of the game that way", that way being his
Glym promos (vocabulary_swipe_app, tool/deck_engine/blender: read, never changed). So it is made as
they were:

  1. the game films itself     insta_game_test.dart plays the real game on a phone-shaped screen and
                               saves every frame, and when each moment and each clip begins
  2. the screen track          those frames, as the phone's screen in Blender (JPEG, to spare the disk)
  3. the camera                where the camera looks at each moment, from the moments the film wrote
  4. Blender                   insta_scene.py: a phone on a desk, the game playing on it, a camera that
                               is never still; rendered in batches, a failed batch tried again
  5. words and sound           the words laid over the top of the frames (so wording changes without a
                               render), the narrator and the game's own clips laid at their moments,
                               all streamed into one H.264 film with its cover

The rules the Glym shorts were held to, kept here: frame 0 already makes the promise in large type,
readable without sound; something moves from the first frame and the voice starts at once; within two
seconds the viewer has something to do (find the four); the name is there from the first frame but is
not the subject; the words stand above the phone, clear of Instagram's own buttons along the foot and
the right edge; the narrator never speaks over the game.

    python tools/insta/insta_voice.py                   the narrator (Kokoro) and the game's clips
    flutter test tools/insta/insta_game_test.dart       the game films itself
    python tools/insta/insta_make.py --stills 2,9,24,32 a look at a few moments, words on, at half size
    python tools/insta/insta_make.py                    everything else, to docs/insta_connections.mp4

It costs nothing: Kokoro, Blender and ffmpeg run on this PC.
"""
import argparse
import math
import json
import pathlib
import shutil
import subprocess
import sys
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import insta_web  # noqa: E402  when each knot of his web comes in, for its sparkle

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "out"
SCREEN = OUT / "screen"
TRACK = OUT / "track"
FRAMES = OUT / "frames"
STILLS = OUT / "stills"
TIMES = OUT / "times.json"
SET = HERE / "set"
# The CC0 light and wood, as the Glym films have them (read from there; copied here once, out of git).
SET_FROM = pathlib.Path("D:/Projects/FlutterProjects/vocabulary_swipe_app/.claude/worktrees/"
                        "project-end-to-end-study-93bbeb/tool/deck_engine/cache/parents")
BLENDER = pathlib.Path("C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
FILM = ROOT / "docs/insta_connections.mp4"
COVER = ROOT / "docs/insta_connections_cover.jpg"
FPS, W, H = 30, 1080, 1920
BATCH = 120
LEVEL = -18.0
FADE = 0.35
HEARD_AT_LEAST = 0.6

# ------------------------------------------------------------------ the words over the picture

INK = (255, 255, 255)
GOLD = (255, 201, 64)
# Each: from, to, the lines, which of them is large. The first is on frame 0.
WORDS = [
    ("hook", "touch", [("16 pictures.", "big"), ("4 hidden groups.", "big"), ("Can your child find them?", "mid")]),
    ("touch", "wrong", [("Find four that", "mid"), ("belong together.", "mid")]),
    ("wrong", "clue", [("Wrong?", "big"), ("It tells him how close he was.", "mid")]),
    ("clue", "fast", [("Stuck?", "big"), ("A clue, never the answer.", "mid")]),
    # the second half, fast forward (the owner, 26 Nov 2026), so the web at the end is rich
    ("fast", "web", [("Set after set,", "mid"), ("deeper and wider.", "mid")]),
    ("web", "close", [("Everything he finds", "mid"), ("grows his own web.", "mid")]),
]
FAST = ("fast", "slow")     # while the game runs fast forward, a small sign says so
CLOSE = [("Connections", "title"), ("A picture game that", "mid"), ("grows with your child.", "mid")]


def fonts_dir() -> pathlib.Path:
    return OUT / "fonts"


@lru_cache(maxsize=None)
def font(kind: str, size: int):
    pattern = {"quick": "Quicksand_700_*.ttf", "inter": "Inter_600_*.ttf"}[kind]
    found = sorted(fonts_dir().glob(pattern))
    if not found:
        sys.exit(f"no font {pattern} in {fonts_dir()}: run the game's film first, which fetches them")
    return ImageFont.truetype(str(found[0]), size)


STYLE = {"big": ("quick", 108, INK), "mid": ("quick", 66, INK), "title": ("quick", 132, GOLD)}


@lru_cache(maxsize=None)
def shade() -> Image.Image:
    """Dark over the top, to y 560, gone by y 820: white words read over the wood and the phone's edge."""
    alpha = Image.new("L", (1, H))
    for y in range(H):
        u = 1.0 if y < 560 else max(0.0, 1 - (y - 560) / 260)
        alpha.putpixel((0, y), round(255 * 0.78 * (u * u * (3 - 2 * u))))
    sheet = Image.new("RGBA", (W, H), (12, 9, 6, 255))
    sheet.putalpha(alpha.resize((W, H)))
    return sheet


@lru_cache(maxsize=None)
def mark() -> Image.Image:
    """The name, small, at the top left from the first frame: there, not the subject."""
    img = Image.new("RGBA", (520, 90), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, colour in enumerate(((108, 92, 231), (255, 193, 7), (19, 138, 124), (194, 78, 112))):
        x, y = 14 + (i % 2) * 26, 18 + (i // 2) * 26
        d.rounded_rectangle((x, y, x + 20, y + 20), radius=5, fill=colour + (255,))
    d.text((78, 45), "Connections", font=font("quick", 44), fill=INK + (235,), anchor="lm")
    return img


@lru_cache(maxsize=None)
def fast_sign() -> Image.Image:
    """A small pill under the words: two forward triangles and the speed, so no one takes it for the game's pace."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font("quick", 40)
    text = "5x speed"
    tw = d.textlength(text, font=f)
    w = round(tw + 120)
    x0, y0 = (W - w) // 2, 400
    d.rounded_rectangle((x0, y0, x0 + w, y0 + 64), radius=32, fill=(255, 201, 64, 235))
    for k in (0, 26):
        x = x0 + 30 + k
        d.polygon([(x, y0 + 18), (x + 24, y0 + 32), (x, y0 + 46)], fill=(45, 52, 54, 255))
    d.text((x0 + 92, y0 + 33), text, font=f, fill=(45, 52, 54, 255), anchor="lm")
    return img


@lru_cache(maxsize=None)
def block(lines: tuple, top: int) -> Image.Image:
    """A few lines of words, centred, with a soft shadow, starting at y = top."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    y = top
    for text, style in lines:
        kind, size, colour = STYLE[style]
        f = font(kind, size)
        d.text((W // 2, y), text, font=f, fill=colour + (255,), anchor="mt")
        y += round(size * 1.18)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(img.getchannel("A").filter(ImageFilter.GaussianBlur(10)).point(lambda a: a * 0.6))
    return Image.alpha_composite(shadow, img)


def ease(u: float) -> float:
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def words_at(t: float, marks: dict, total: float) -> list:
    """What is laid over the picture at time t: (image, opacity, rise in px)."""
    out = [(shade(), 1.0, 0)]
    for start, end, lines in WORDS:
        a, b = marks[start], marks[end]
        if a - 0.05 <= t < b:
            fade_in = 1.0 if start == "hook" else ease((t - a) / 0.35)
            fade_out = ease((b - t) / 0.3)
            # the hook's last line comes a moment after the first two
            if start == "hook":
                out.append((block(tuple(lines[:2]), 150), 1.0, 0))
                out.append((block(tuple(lines[2:]), 150 + 2 * round(108 * 1.18) + 22), ease((t - 2.3) / 0.4), 0))
            else:
                out.append((block(tuple(lines), 210), min(fade_in, fade_out), round(14 * (1 - fade_in))))
    a, b = marks[FAST[0]], marks[FAST[1]]
    if a <= t < b:
        out.append((fast_sign(), min(ease((t - a) / 0.3), ease((b - t) / 0.3)), 0))
    c = marks["close"]
    if t >= c - 0.1:
        u = ease((t - c) / 0.8)
        out.append((block(tuple(CLOSE), 170), u, round(18 * (1 - u))))
    if t < c + 0.2:
        out.append((mark(), 1.0, None))
    return out


def lay_words(frame: Image.Image, t: float, marks: dict, total: float) -> Image.Image:
    base = frame.convert("RGBA").resize((W, H)) if frame.size != (W, H) else frame.convert("RGBA")
    for img, opacity, rise in words_at(t, marks, total):
        if opacity <= 0:
            continue
        if rise is None:          # the mark, at the top left
            layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            layer.paste(img, (36, 42))
            img = layer
        elif rise:
            moved = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            moved.paste(img, (0, rise))
            img = moved
        if opacity < 1:
            img = img.copy()
            img.putalpha(img.getchannel("A").point(lambda a: round(a * opacity)))
        base = Image.alpha_composite(base, img)
    return base.convert("RGB")


# ------------------------------------------------------------------ 1-3: the track and the camera

def events() -> dict:
    return json.loads((SCREEN / "events.json").read_text(encoding="utf-8"))


def ensure_set():
    SET.mkdir(exist_ok=True)
    wanted = ["ferndale_studio_11_hdri_2k.hdr", "wood_table_001_diffuse_2k.jpg", "wood_table_001_nor_gl_2k.jpg",
              "wood_table_001_rough_2k.jpg"]
    for name in wanted:
        if not (SET / name).exists():
            source = SET_FROM / name
            if not source.exists():
                sys.exit(f"{name} is missing: fetch it from the address in tools/insta/set_sources.json into {SET}")
            shutil.copy2(source, SET / name)


def make_track():
    """The game's frames as the phone's screen: JPEG, numbered from 1 as Blender's frames are. The PNGs go."""
    TRACK.mkdir(parents=True, exist_ok=True)
    pngs = sorted(SCREEN.glob("f*.png"))
    for png in pngs:
        jpg = TRACK / f"t{int(png.stem[1:]) + 1:05d}.jpg"
        if not jpg.exists():
            Image.open(png).convert("RGB").save(jpg, quality=93)
        png.unlink()
    print(f"track: {len(list(TRACK.glob('t*.jpg')))} frames")


def make_times() -> dict:
    """When the pictures land, when the web grows, and where the camera looks: a box of the screen's picture
    (pixels; past it, the air around the phone) or of his web's plane (shares of its radius), and a view
    (elevation, azimuth: the phone stands, so the camera looks at it nearly level), at a time."""
    e = events()
    marks = {m["mark"]: m["t"] for m in e["marks"]}
    sw, sh = e["size"]
    boxes = e["boxes"]
    full = (-30, -40, sw + 30, sh + 40)
    board = tuple(boxes["board"])
    lower = (10, sh * 0.56, sw - 10, sh * 0.93)        # the clue's words and the buttons
    web_screen = (sw * 0.04, sh * 0.12, sw * 0.96, sh * 0.62)
    total = e["frames"] / FPS
    land_from, land_to = 1.7, 3.9                      # the sixteen pictures fly in as "Can your child..." is said
    web_slide = marks["web"] + 1.3                     # the phone goes, and his web grows behind it
    web_from, web_to = web_slide + 0.4, marks["close"] - 0.1
    # his web is lopsided (one branch holds most of it), so the camera frames where its knots are, not its radius
    angle, depth, _ = insta_web.layout(e["web"])
    deepest = max(depth.values()) or 1
    xs = [-math.sin(angle[i]) * depth[i] / deepest for i in angle]
    zs = [-math.cos(angle[i]) * depth[i] / deepest for i in angle]
    edge = 0.1                                           # a knot's own size, and a little air
    whole = lambda m: {"web": [min(xs) * m - edge, min(zs) * m - edge, max(xs) * m + edge, max(zs) * m + edge]}
    shots = [
        (0.0, board, (9, -13)),                                       # the cards in the air, from frame 0
        (land_to + 0.3, board, (6, -6)),
        (marks["touch"] + 0.6, board, (5, -3)),                       # the pictures as they are named
        (marks["right"] + 1.4, board, (5, 2)),
        (marks["wrong"] + 0.4, board, (6, 4)),
        (marks["oneaway"] + 1.0, full, (7, 0)),
        (marks["clue"] + 1.8, lower, (6, -3)),                        # in on the clue
        (marks["done"] - 0.5, lower, (6, -5)),
        (marks["done"] + 0.4, full, (8, -2)),
        (marks["fast"] + 1.0, full, (9, -8)),                         # the fast half: the whole phone, turning
        (marks["slow"] - 0.4, (0, sh * 0.08, sw, sh * 0.92), (8, 6)),
        (marks["web"] + 0.7, web_screen, (6, 0)),                     # the web on the phone
        (web_slide + 0.1, web_screen, (7, -2)),
        (web_from + 0.9, {"web": [-0.45, -0.45, 0.45, 0.45]}, (8, -5)),                        # then in 3D, from its middle
        (web_to, whole(1.0), (9, 2)),                               # the whole of it
        (marks["close"] + 2.2, whole(1.03), (11, 5)),
        (total, whole(1.05), (12, 6)),
    ]
    times = {"screen_px": [sw, sh], "total": round(total, 3), "marks": marks, "shots": shots,
             "tiles": e["tiles"], "web": e["web"], "land_from": land_from, "land_to": land_to,
             "web_slide": web_slide, "web_from": web_from, "web_to": web_to}
    TIMES.write_text(json.dumps(times, indent=1), encoding="utf-8")
    return times


# ------------------------------------------------------------------ 4: Blender

def blender(out: pathlib.Path, stills=None, frames=None, preview=False, tries=3):
    """One Blender run. EEVEE sometimes fails to get graphics memory as it starts a frame (the Glym promos,
    8 Nov), so a run that fails is tried again; the frames it finished stay."""
    cmd = [str(BLENDER), "-b", "--factory-startup", "-P", str(HERE / "insta_scene.py"), "--", "--times", str(TIMES),
           "--track", str(TRACK), "--out", str(out)]
    if stills:
        cmd += ["--stills", ",".join(f"{s:g}" for s in stills)]
    if frames:
        cmd += ["--frames", frames]
    if preview:
        cmd += ["--preview"]
    for attempt in range(1, tries + 1):
        run = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        tail = (run.stdout + run.stderr).strip().splitlines()[-6:]
        if run.returncode == 0 and any("insta scene: done" in line for line in tail):
            return
        print(f"  blender failed ({frames or 'stills'}), attempt {attempt} of {tries}:\n    " + "\n    ".join(tail),
              flush=True)
    sys.exit("blender failed")


def render_all(times: dict):
    total = round(times["total"] * FPS)
    FRAMES.mkdir(parents=True, exist_ok=True)
    for first in range(1, total + 1, BATCH):
        last = min(total, first + BATCH - 1)
        if all((FRAMES / f"f{n:04d}.jpg").exists() for n in range(first, last + 1)):
            continue
        blender(FRAMES, frames=f"{first}-{last}")
        print(f"  rendered {last} of {total}", flush=True)


# ------------------------------------------------------------------ 5: sound, and the film

def mean_volume(path: pathlib.Path) -> float:
    import re
    done = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    found = re.search(r"mean_volume: (-?[0-9.]+) dB", done.stderr)
    return float(found.group(1)) if found else LEVEL


def seconds_of(path: pathlib.Path) -> float:
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                 str(path)], capture_output=True, text=True, check=True).stdout)


def tone(name: str, expr: str, seconds: float) -> pathlib.Path:
    """A short sound made here, from a formula: nothing borrowed, nothing to license."""
    out = OUT / "sfx" / f"{name}.wav"
    if not out.exists():
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"aevalsrc='{expr}':s=48000:d={seconds}", "-ac", "2", str(out)], check=True)
    return out


def sound(times: dict) -> pathlib.Path:
    """The narrator alone, at one loudness: the game's own voice is left out of the reel (the owner, 26 Nov
    2026: "supress the voice from the app and you tell what is that you are clicking"), so there is one voice
    and nothing can overlap. Under it, quiet sounds made here: a soft tap for each touch, a chime when a group
    is right, a low note when it is one away, a breath of air as the pictures fly in, and a faint sparkle as
    each knot of his web comes in."""
    e = events()
    total = times["total"]
    voice = json.loads((OUT / "voice/manifest.json").read_text(encoding="utf-8"))["lines"]
    said = sorted(((OUT / "voice" / voice[s["id"]]["clip"], s["t"]) for s in e["voice"]), key=lambda c: c[1])
    until, last = 0.0, ""
    for path, start in said:
        if start < until - 0.05:
            sys.exit(f"two voices at once at {start:.1f} s: {path.name} begins while {last} is still heard")
        until, last = start + seconds_of(path), path.name
    tap = tone("tap", "0.5*sin(2*PI*1320*t)*exp(-55*t)+0.25*sin(2*PI*2640*t)*exp(-80*t)", 0.14)
    # each note its own sound, laid a moment apart: a formula with a comma in it is not read by ffmpeg's lavfi
    high, higher = tone("right1", "0.32*sin(2*PI*988*t)*exp(-5*t)", 0.9), tone("right2", "0.32*sin(2*PI*1319*t)*exp(-5*t)", 0.9)
    low, lower = tone("near1", "0.32*sin(2*PI*523*t)*exp(-6*t)", 0.8), tone("near2", "0.3*sin(2*PI*440*t)*exp(-6*t)", 0.8)
    air = tone("air", "0.10*sin(2*PI*(300+900*t)*t)*sin(PI*t/1.6)+0.05*sin(2*PI*(600+1500*t)*t)*sin(PI*t/1.6)", 1.6)
    notes = [1568, 1760, 2093, 2349, 2637]
    sparks = [tone(f"spark{n}", f"0.22*sin(2*PI*{n}*t)*exp(-14*t)", 0.35) for n in notes]
    # presses inside a cut have the cut's own moment; they were not seen, and are not heard
    seen = {}
    for p in e["presses"]:
        seen[round(p["t"], 2)] = seen.get(round(p["t"], 2), 0) + 1
    effects = [(air, times["land_from"] - 0.2, -2.0)]
    for p in e["presses"]:
        if seen[round(p["t"], 2)] > 1:
            continue
        kind = p["kind"]
        effects.append((tap, p["t"] + 0.06, -4.0))
        if kind == "submit":
            effects += [(high, p["t"] + 0.12, -3.0), (higher, p["t"] + 0.23, -3.0)]
        elif kind == "wrong":
            effects += [(low, p["t"] + 0.12, -4.0), (lower, p["t"] + 0.25, -4.0)]
    for k, (i, t) in enumerate(sorted(insta_web.appear_times(times["web"], times["web_from"], times["web_to"]).items(),
                                      key=lambda x: x[1])):
        effects.append((sparks[k % len(sparks)], t, -9.0))
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    parts, names = [], []
    clips = [(path, start, LEVEL - mean_volume(path)) for path, start in said] + effects
    for i, (path, start, gain) in enumerate(clips):
        cmd += ["-i", str(path)]
        gain = max(-14.0, min(12.0, gain))
        parts.append(f"[{i}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={gain:.1f}dB,"
                     f"adelay={max(0, round(start * 1000))}:all=1[a{i}]")
        names.append(f"[a{i}]")
    parts.append(f"{''.join(names)}amix=inputs={len(names)}:normalize=0:dropout_transition=0,"
                 f"alimiter=limit=0.9,apad,atrim=0:{total:.3f}[out]")
    script = OUT / "sound.txt"
    script.write_text(";\n".join(parts), encoding="utf-8")
    wav = OUT / "sound.wav"
    cmd += ["-filter_complex_script", str(script), "-map", "[out]", str(wav)]
    done = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if done.returncode != 0:
        sys.exit("ffmpeg (sound) failed:\n" + done.stderr[-2000:])
    print(f"sound: {len(said)} narrator lines, {len(effects)} quiet sounds made here; none of the game's own voice")
    return wav


def film(times: dict):
    """The rendered frames, the words laid over each, streamed into the encoder with the sound."""
    total = times["total"]
    marks = times["marks"]
    wav = sound(times)
    n = round(total * FPS)
    FILM.parent.mkdir(parents=True, exist_ok=True)
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
         "-i", "-", "-i", str(wav),
         "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-r", str(FPS),
         "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", str(FILM)],
        stdin=subprocess.PIPE)
    for i in range(1, n + 1):
        t = (i - 1) / FPS
        frame = lay_words(Image.open(FRAMES / f"f{i:04d}.jpg"), t, marks, total)
        if i == 1:
            frame.save(COVER, quality=92)
        enc.stdin.write(frame.tobytes())
    enc.stdin.close()
    if enc.wait() != 0:
        sys.exit("ffmpeg (film) failed")
    print(f"{FILM}: {total:.1f} s, {FILM.stat().st_size / 1e6:.1f} MB; cover {COVER.name}")


def stills(times: dict, at: list):
    """A few moments, rendered at half size, with the words on: to look before the long render."""
    blender(STILLS, stills=at, preview=True)
    sheet = []
    for t in at:
        img = Image.open(STILLS / f"still_{t:06.2f}.jpg")
        sheet.append(lay_words(img, t, times["marks"], times["total"]).resize((W // 3, H // 3)))
    out = Image.new("RGB", (len(sheet) * (W // 3 + 12), H // 3), "white")
    for i, img in enumerate(sheet):
        out.paste(img, (i * (W // 3 + 12), 0))
    path = OUT / "look.jpg"
    out.save(path, quality=90)
    print(f"look: {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stills", help="times, comma separated: a look at half size, words on")
    args = ap.parse_args()
    if any(SCREEN.glob("f*.png")):
        make_track()
    times = make_times()
    if args.stills:
        stills(times, [float(s) for s in args.stills.split(",")])
        return
    render_all(times)
    film(times)


if __name__ == "__main__":
    main()
