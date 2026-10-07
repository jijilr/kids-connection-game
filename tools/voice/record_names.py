"""Record every name in the catalogue with Kokoro, once, and keep the clips in this project.

Kokoro is the owner's own installation at D:\\Projects\\Kokoro. It is used where it stands:
nothing of it is downloaded, installed or copied, and nothing is written into its folder.
The speaking itself is done by tools/voice/kokoro_clips.py, run by Kokoro's own Python.

What is said for each thing is the catalogue's `voice.say` (the name as the child says it).
For a hard name, tools/voice/pronunciation.json may give Kokoro the sounds outright.

    tools/voice/clips/<thing>.mp3          one clip for every thing in the catalogue (the cache)
    tools/voice/clips.json                 the ledger: what was said, by which voice, when
    Assets/audio/names/name_<thing>.mp3    the clips of the things in the game, which the game plays
    tools/voice/older_clips/               clips of the older game that a new one replaced, kept

The game plays a thing's clip if it has one, and falls back to the browser's own voice
if not. No clip here has been checked by ear: the catalogue says so for each.

    python tools/voice/record_names.py             record what has no clip yet, then publish
    python tools/voice/record_names.py --again NAME [NAME...]    record these again
    python tools/voice/record_names.py --publish   only put the cached clips of things in the game into the game

The same voice speaks the clues and the explanation of every group (tools/content/
group_words.py writes them): tools/voice/clips/groups/ is their cache, and
Assets/audio/groups/ is where the game plays them from.
"""
import datetime
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/catalogue"))
import catalogue as cat        # noqa: E402

KOKORO = pathlib.Path(r"D:\Projects\Kokoro")
KOKORO_PYTHON = KOKORO / ".venv/Scripts/python.exe"
SPEAKER = ROOT / "tools/voice/kokoro_clips.py"
PRONUNCIATION = ROOT / "tools/voice/pronunciation.json"
CACHE = ROOT / "tools/voice/clips"
LEDGER = ROOT / "tools/voice/clips.json"
OLDER = ROOT / "tools/voice/older_clips"
GAME = ROOT / "Assets/audio/names"
VOICE, SPEED = "bf_emma", 0.9      # a British voice, a little slower than talk: nearer to how English is spoken in India


def read_ledger() -> dict:
    return cat.read_json(LEDGER) or {
        "about": "Every name clip made with Kokoro: what was said, by which voice, and when. Written by "
                 "tools/voice/record_names.py. No clip has been checked by ear unless the catalogue says so.",
        "clips": {}}


def record(keys_again: set) -> int:
    """Speak the names that have no clip yet, or that were asked for again. Returns how many."""
    catalogue = cat.load()
    hard = (cat.read_json(PRONUNCIATION) or {}).get("names", {})
    ledger = read_ledger()
    wanted = []
    for key, entry in catalogue["things"].items():
        say = (entry.get("voice") or {}).get("say") or entry.get("shown_as") or entry["name"]
        text = hard.get(key, {}).get("kokoro") or say
        made = ledger["clips"].get(key)
        fresh = made and made["text"] == text and made["voice"] == VOICE and (CACHE / f"{key}.mp3").exists()
        if key in keys_again or not fresh:
            wanted.append({"key": key, "text": text, "say": say, "out": str(CACHE / f"{key}.mp3")})
    if not wanted:
        print("Every name in the catalogue has its clip already.")
        return 0
    if not KOKORO_PYTHON.exists():
        print(f"Kokoro is not at {KOKORO}, so {len(wanted)} name(s) were not recorded. The game uses the browser's voice for them.")
        return 0
    CACHE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        listing, result = pathlib.Path(folder) / "list.json", pathlib.Path(folder) / "result.json"
        listing.write_text(json.dumps({"kokoro": str(KOKORO), "voice": VOICE, "speed": SPEED, "clips": wanted},
                                      ensure_ascii=False), encoding="utf-8")
        done = subprocess.run([str(KOKORO_PYTHON), str(SPEAKER), str(listing), str(result)], capture_output=True,
                              text=True, encoding="utf-8", errors="replace")
        if done.returncode != 0 or not result.exists():
            print("Kokoro did not run, so nothing was recorded:", (done.stdout + done.stderr).strip()[-400:])
            return 0
        spoken = json.loads(result.read_text(encoding="utf-8"))
    for item in wanted:
        made = spoken["clips"].get(item["key"])
        if not made:
            continue
        clip = CACHE / f"{item['key']}.mp3"
        ledger["clips"][item["key"]] = {
            "say": item["say"], "text": item["text"], "voice": VOICE, "speed": SPEED, "sounds": made["phonemes"],
            "seconds": made["seconds"], "cache": cat.relative(clip), "sha256": cat.fingerprint(clip),
            "recorded_on": datetime.date.today().isoformat(), "made_on": spoken["device"]}
    cat.write_json(LEDGER, ledger)
    for key, why in spoken["failed"].items():
        print(f"  not recorded - {key}: {why}")
    print(f"{len(spoken['clips'])} name(s) recorded with Kokoro, voice {VOICE}, on {spoken['device']}.")
    return len(spoken["clips"])


def publish() -> int:
    """Put the cached clip of every thing in the game where the game plays it from. A clip
    of the older game that is replaced is moved to tools/voice/older_clips, not deleted."""
    catalogue, ledger = cat.load(), read_ledger()
    file_names = (cat.read_json(cat.PICTURE_NAMES) or {}).get("file_names", {})
    ours = {made["sha256"] for made in ledger["clips"].values()}
    GAME.mkdir(parents=True, exist_ok=True)
    put = 0
    for key, entry in catalogue["things"].items():
        made = ledger["clips"].get(key)
        if entry["status"] != cat.IN_GAME or not made or not (ROOT / made["cache"]).exists():
            continue
        target = GAME / f"name_{file_names.get(key, key)}.mp3"
        if target.exists():
            if cat.fingerprint(target) == made["sha256"]:
                continue
            if cat.fingerprint(target) not in ours:
                OLDER.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(OLDER / target.name))
        shutil.copyfile(ROOT / made["cache"], target)
        put += 1
    with cat.changing("record_names.py") as changed:
        cat.sync_voice(changed)
    print(f"{put} clip(s) put into the game; the catalogue now names each thing's clip.")
    return put


def group_parts(catalogue: dict) -> list:
    """Every clue and explanation that has words: (ledger key, file stem, text)."""
    parts = []
    for key, group in catalogue.get("groups", {}).items():
        stem = key.replace("=", "__")
        for i, clue in enumerate(group.get("clues", []), 1):
            parts.append((f"{key}:clue{i}", f"{stem}__clue{i}", clue["text"]))
        if (group.get("explanation") or {}).get("text"):
            parts.append((f"{key}:explanation", f"{stem}__explanation", group["explanation"]["text"]))
    return parts


def record_groups(again: bool = False) -> int:
    """Speak the clues and explanations that have no clip yet, or whose words have changed,
    put them where the game plays them from, and tell the catalogue."""
    catalogue, ledger = cat.load(), read_ledger()
    spoken = ledger.setdefault("groups", {})
    wanted = []
    for key, stem, text in group_parts(catalogue):
        made = spoken.get(key)
        fresh = made and made["text"] == text and made["voice"] == VOICE and (ROOT / made["cache"]).exists()
        if again or not fresh:
            wanted.append({"key": key, "text": text, "out": str(CACHE / "groups" / f"{stem}.mp3"), "stem": stem})
    if wanted and not KOKORO_PYTHON.exists():
        print(f"Kokoro is not at {KOKORO}, so {len(wanted)} clue(s) and explanation(s) were not recorded. "
              "The game uses the browser's voice for them.")
        wanted = []
    if wanted:
        (CACHE / "groups").mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as folder:
            listing, result = pathlib.Path(folder) / "list.json", pathlib.Path(folder) / "result.json"
            listing.write_text(json.dumps({"kokoro": str(KOKORO), "voice": VOICE, "speed": SPEED, "clips": wanted},
                                          ensure_ascii=False), encoding="utf-8")
            done = subprocess.run([str(KOKORO_PYTHON), str(SPEAKER), str(listing), str(result)], capture_output=True,
                                  text=True, encoding="utf-8", errors="replace")
            if done.returncode != 0 or not result.exists():
                print("Kokoro did not run, so no clue was recorded:", (done.stdout + done.stderr).strip()[-400:])
                return 0
            answer = json.loads(result.read_text(encoding="utf-8"))
        for item in wanted:
            made = answer["clips"].get(item["key"])
            if not made:
                continue
            clip = CACHE / "groups" / f"{item['stem']}.mp3"
            spoken[item["key"]] = {
                "text": item["text"], "voice": VOICE, "speed": SPEED, "seconds": made["seconds"],
                "cache": cat.relative(clip), "sha256": cat.fingerprint(clip),
                "game_file": f"Assets/audio/groups/{item['stem']}.mp3",
                "recorded_on": datetime.date.today().isoformat(), "made_on": answer["device"]}
        cat.write_json(LEDGER, ledger)
        for key, why in answer["failed"].items():
            print(f"  not recorded - {key}: {why}")
        print(f"{len(answer['clips'])} clue(s) and explanation(s) recorded with Kokoro, voice {VOICE}.")
    # into the game's own folder; a clip whose words are no longer in the catalogue is left out of it
    GROUP_GAME = ROOT / "Assets/audio/groups"
    GROUP_GAME.mkdir(parents=True, exist_ok=True)
    live = {key for key, _, _ in group_parts(catalogue)}
    for key, made in spoken.items():
        target = ROOT / made["game_file"]
        if key in live and (ROOT / made["cache"]).exists():
            if not target.exists() or cat.fingerprint(target) != made["sha256"]:
                shutil.copyfile(ROOT / made["cache"], target)
        elif target.exists():
            target.unlink()         # the cached copy stays
    with cat.changing("record_names.py") as changed:
        cat.sync_group_voice(changed)
    return len(wanted)


def main():
    args = sys.argv[1:]
    again = set()
    if "--again" in args:
        again = {cat.slug(name) for name in args[args.index("--again") + 1:]}
    if "--publish" not in args:
        record(again)
    publish()
    record_groups(again="--again-groups" in args)


if __name__ == "__main__":
    main()
