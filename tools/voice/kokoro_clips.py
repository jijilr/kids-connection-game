"""Speak a list of names with Kokoro, using the owner's own installation and nothing else.

This file is run by the Python of that installation (D:\\Projects\\Kokoro\\.venv), never by
the project's own Python: the model, its voices and its packages stay where they are.
Nothing is downloaded (the model hub is switched to offline), nothing is installed, and
nothing is written into the Kokoro folder. The clips are written where the list says.

    D:\\Projects\\Kokoro\\.venv\\Scripts\\python.exe tools/voice/kokoro_clips.py LIST.json RESULT.json

LIST.json:   {"kokoro": "D:/Projects/Kokoro", "voice": "bf_emma", "speed": 0.9,
              "clips": [{"key": "lion", "text": "Lion", "out": ".../lion.mp3"}]}
RESULT.json: {"device": "...", "clips": {"lion": {"phonemes": "...", "seconds": 0.8}}, "failed": {"x": "why"}}
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import warnings

listing = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
kokoro_home = pathlib.Path(listing["kokoro"])
os.environ["HF_HOME"] = str(kokoro_home / "models")       # the model files already there
os.environ["HF_HUB_OFFLINE"] = "1"                         # and never a download
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_VERBOSITY", "error")
warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

import numpy as np                      # noqa: E402
import soundfile as sf                  # noqa: E402
import torch                            # noqa: E402
from kokoro import KModel, KPipeline    # noqa: E402

REPO, RATE = "hexgrad/Kokoro-82M", 24000
ffmpeg = shutil.which("ffmpeg")
device = "cuda" if torch.cuda.is_available() else "cpu"
model = KModel(repo_id=REPO).to(device).eval()
voice, speed = listing["voice"], listing.get("speed", 1.0)
pipeline = KPipeline(lang_code=voice[0], repo_id=REPO, model=model)
quiet = np.zeros(int(0.12 * RATE), dtype=np.float32)     # a breath of silence at each end

done, failed = {}, {}
for clip in listing["clips"]:
    try:
        parts, phonemes = [], []
        for result in pipeline(clip["text"], voice=voice, speed=speed, split_pattern=None):
            if result.audio is not None:
                parts.append(result.audio.cpu().numpy())
            phonemes.append(result.phonemes or "")
        if not parts:
            failed[clip["key"]] = "Kokoro gave no sound for it"
            continue
        audio = np.concatenate([quiet] + parts + [quiet])
        out = pathlib.Path(clip["out"])
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.suffix.lower() == ".mp3":
            if not ffmpeg:
                failed[clip["key"]] = "ffmpeg is needed for an mp3 and is not on this machine"
                continue
            wav = pathlib.Path(tempfile.gettempdir()) / f"name_clip_{os.getpid()}.wav"
            sf.write(str(wav), audio, RATE)
            made = subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(wav), "-ac", "1", "-b:a", "64k", str(out)],
                                  capture_output=True, text=True)
            wav.unlink(missing_ok=True)
            if made.returncode != 0:
                failed[clip["key"]] = "ffmpeg: " + made.stderr.strip()[-200:]
                continue
        else:
            sf.write(str(out), audio, RATE)
        done[clip["key"]] = {"phonemes": " ".join(phonemes), "seconds": round(len(audio) / RATE, 2)}
    except Exception as error:      # one bad name must not stop the rest
        failed[clip["key"]] = f"{type(error).__name__}: {error}"[:300]

pathlib.Path(sys.argv[2]).write_text(json.dumps(
    {"device": torch.cuda.get_device_name(0) if device == "cuda" else "CPU", "voice": voice, "speed": speed,
     "clips": done, "failed": failed}, indent=1, ensure_ascii=False), encoding="utf-8")
print(f"{len(done)} clip(s) spoken, {len(failed)} failed, on {device}")
