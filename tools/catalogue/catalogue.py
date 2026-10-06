"""The catalogue: the master record of every thing, and the only code that reads or writes it.

tools/catalogue/catalogue.json has one entry for each thing. An entry has a RECORDED
part, set by a script or by the owner:
    name, status, fields, familiarity, review stamp, notes   what is known about it
    sources      the pages read, and the sentence behind each field value
    picture      the chosen tile, its files and their fingerprints
    voice        how to say the name, and its clip
and a WORKED-OUT part, computed again on every save, so it cannot go stale:
    circles      the circles it belongs to
    boards       the boards it can appear on, and its group on each
The catalogue also works out, for every circle, whether it can open now and, if not,
what it needs. Nothing about which groups offer "Dig deeper" is decided by hand: it
follows from what is in here.

How it relates to the other files (the owner's rulings of 6 Oct 2026):
    Assets/data/dictionary.json       the fields and values. The catalogue obeys it.
    Assets/data/things.json           the GAME'S COPY, written from the catalogue on every
                                      save: only things in the game, only what the game
                                      needs. Nobody edits it.
    tools/pictures/records.json       the full ledger of every sheet and tile. The catalogue
                                      holds only each thing's chosen tile and points to it.
    tools/content/review_queue.json   a VIEW, written from the catalogue: every entry that
                                      is held, with its reason.
    tools/content/expansion_tree.json the engine's proposals and the owner's decisions on
                                      them. What a circle holds and needs is worked out here.
    tools/research/out/               what the pages say. The catalogue points to it.

Scripts change the catalogue only through `changing()`, which locks the file, works
everything out again, runs the guard, and rewrites the game's copy and the queue.

    python tools/catalogue/catalogue.py check       the guard: catalogue against dictionary and real files
    python tools/catalogue/catalogue.py circles     which circles can open now, and what each closed one needs
    python tools/catalogue/catalogue.py queue       what is held, and why
    python tools/catalogue/catalogue.py show ID     one entry
    python tools/catalogue/catalogue.py refresh     read pictures, clips and sources again from their ledgers
"""
import contextlib
import copy
import datetime
import hashlib
import json
import os
import pathlib
import re
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/catalogue"
CATALOGUE = HERE / "catalogue.json"
LOCK = HERE / "catalogue.lock"
DICTIONARY = ROOT / "Assets/data/dictionary.json"
SETTINGS = ROOT / "Assets/data/settings.json"
THINGS = ROOT / "Assets/data/things.json"            # the game's copy
PICTURE_NAMES = ROOT / "Assets/data/pictures.json"
PICTURES = ROOT / "Assets/pictures"
CLIPS = ROOT / "Assets/audio/names"
RECORDS = ROOT / "tools/pictures/records.json"
QUEUE = ROOT / "tools/content/review_queue.json"
RESEARCH = ROOT / "tools/research/out"

sys.path.insert(0, str(ROOT / "tools/content"))
import guard as dictionary_guard          # noqa: E402  the rules a thing's fields must obey
from boards import GROUPS, PER_GROUP, members, value_of   # noqa: E402
from expand import build_circles          # noqa: E402  one working-out of what a circle is missing

IN_GAME = "in the game"
WAITING = "waiting for the owner"
LATER = "kept for later"
NOT_YET = "not in the game yet"
EXCLUDED = "excluded"
TAKEN_OUT = "taken out of the game"
HELD = (WAITING, LATER, NOT_YET)          # these make up the owner's queue
STATUSES = {
    IN_GAME: "The game shows it. It is in the game's copy.",
    WAITING: "A check had a doubt about it. The owner decides.",
    LATER: "The owner is keeping it for a later board or a field that does not exist yet.",
    NOT_YET: "Ready, but deliberately not in the game yet.",
    EXCLUDED: "The owner ruled it out.",
    TAKEN_OUT: "It was in the game or the queue and a script took it out. Kept, so nothing is lost.",
}
# what the game's copy carries for each thing, and nothing else
GAME_KEYS = ("name", "shown_as", "fields", "familiar", "reviewed", "source", "notes", "drafted_in")
HELD_KEYS = ("status_why", "held_from", "also_offered")


def today() -> str:
    return datetime.date.today().isoformat()


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def read_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    """Write beside the file, then swap it in: a crash cannot leave half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(path.suffix + ".writing")
    with open(partial, "w", encoding="utf-8", newline="\n") as file:
        file.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.replace(partial, path)


def relative(path: pathlib.Path) -> str:
    return path.relative_to(ROOT).as_posix()


def fingerprint(path: pathlib.Path) -> str:
    """sha256 of a file. A full-size picture kept in Git LFS may be present only as a
    pointer; the pointer states the real file's sha256, so it is read from there."""
    data = path.read_bytes()
    if data.startswith(b"version https://git-lfs"):
        found = re.search(rb"oid sha256:([0-9a-f]{64})", data)
        if found:
            return found.group(1).decode()
    return hashlib.sha256(data).hexdigest()


# ------------------------------------------------------------------ reading

def load() -> dict:
    catalogue = read_json(CATALOGUE)
    if catalogue is None:
        raise SystemExit("There is no catalogue yet. Build it with: python tools/catalogue/build.py")
    return catalogue


def game_copy(catalogue: dict) -> dict:
    """What the game reads: the things in the game, each with only what the game needs."""
    return {"dictionary_version": catalogue["dictionary_version"],
            "things": {key: {k: entry[k] for k in entry if k in GAME_KEYS}
                       for key, entry in catalogue["things"].items() if entry["status"] == IN_GAME}}


def queue_view(catalogue: dict) -> dict:
    """What is held for the owner, in the shape the queue file has always had."""
    held = []
    for entry in catalogue["things"].values():
        if entry["status"] in HELD:
            item = {"name": entry["name"], "fields": entry.get("fields", {}),
                    "why": entry.get("status_why", []), "from": entry.get("held_from", "")}
            if "familiar" in entry:
                item["familiar"] = entry["familiar"]
            held.append(item)
        held += [dict(offer) for offer in entry.get("also_offered", [])]
    return {"for_the_owner": held}


# ------------------------------------------------------------------ working out

def circle_path(circles: dict, cid: str) -> list:
    """The (field, value) steps that lead from the seed to a circle."""
    if cid == "seed":
        return []
    path, here = [], "seed"
    for part in cid.split("/"):
        path.append((circles[here]["sorted_by"], part))
        here = part if here == "seed" else f"{here}/{part}"
    return path


def climb(circles: dict, fields: dict) -> list:
    """The circles a thing with these fields belongs to, from the seed inward."""
    found, here = ["seed"], "seed"
    while True:
        field = circles[here].get("sorted_by")
        value = value_of({"fields": fields}, field) if field else None
        if value is None:
            return found
        child = str(value) if here == "seed" else f"{here}/{value}"
        if child not in circles:
            return found
        found.append(child)
        here = child


def work_out(catalogue: dict):
    """Compute, from the recorded part, each thing's circles and boards, and for every
    circle whether it can open now and what it needs. Nothing here is decided by hand."""
    dictionary, settings = read_json(DICTIONARY), read_json(SETTINGS)
    things = game_copy(catalogue)["things"]
    raw = build_circles(dictionary, things, settings)
    need_pictures = settings.get("boards_need_pictures", False)
    has_picture = lambda key: bool((catalogue["things"][key].get("picture") or {}).get("game_file"))

    circles = {}
    for cid, circle in raw.items():
        keys = members(things, circle_path(raw, cid))
        out = {"label": circle["label"], "things": len(keys), "steps_from_seed": circle["steps_from_seed"]}
        needs, field = [], circle.get("sorted_by")
        if field:
            labels = dictionary["fields"][field]["values"]
            held_back = [str(v) for v in settings.get("hold_back", {}).get(field, [])]
            groups = {}
            for key in keys:
                value = value_of(things[key], field)
                if value is not None:
                    group = groups.setdefault(str(value).lower() if isinstance(value, bool) else str(value),
                                              {"things": 0, "with_picture": 0})
                    group["things"] += 1
                    group["with_picture"] += has_picture(key)
            out["sorted_by"] = field
            out["groups"] = {value: dict(label=labels.get(value, value), **groups[value],
                                         **({"held_back_in_settings": True} if value in held_back else {}))
                             for value in labels if value in groups}
        missing = circle.get("missing", {})
        if "why" in missing:
            needs.append(f"{missing['things']} more thing(s): it has fewer than four, so it is not yet a group on the board above it")
        if missing.get("field"):
            needs.append("a field to sort it by: no field in the dictionary splits it four ways"
                         + (f", and about {missing['things']} more things" if missing.get("things") else ""))
        for value, short in (missing.get("short") or {}).items():
            needs.append(f"{short} more thing(s) in '{dictionary['fields'][field]['values'].get(str(value), value)}'")
        if "one_solution" in missing:
            needs.append("boards with one clean solution: " + missing["one_solution"])
        ready = [v for v, g in out.get("groups", {}).items()
                 if g["things"] >= PER_GROUP and not g.get("held_back_in_settings")]
        drawn = [v for v in ready if out["groups"][v]["with_picture"] >= PER_GROUP]
        if circle["open"] and need_pictures and len(drawn) < GROUPS:
            for value in ready:
                group = out["groups"][value]
                if group["with_picture"] < PER_GROUP:
                    needs.append(f"pictures for {PER_GROUP - group['with_picture']} more in '{group['label']}'")
        # things recorded here but not in the game that would fill a gap in this circle
        path = circle_path(raw, cid)
        waiting = [{"name": e["name"], "status": e["status"],
                    **({"group": str(e["fields"][field])} if field and field in e["fields"] else {})}
                   for e in catalogue["things"].values()
                   if e["status"] in HELD and e.get("fields")
                   and all(e["fields"].get(f) == v for f, v in path)
                   and (cid != "seed")]
        if waiting and not circle["open"]:
            out["could_be_filled_by"] = waiting
        out["open_by_its_things"] = circle["open"]
        out["can_open_now"] = circle["open"] and (not need_pictures or len(drawn) >= GROUPS)
        out["needs"] = needs
        circles[cid] = out

    for key, entry in catalogue["things"].items():
        fields = entry.get("fields", {})
        if entry["status"] == IN_GAME:
            inside = climb(raw, fields)
            boards = []
            for cid in inside:
                field = raw[cid].get("sorted_by")
                value = value_of({"fields": fields}, field) if field else None
                if raw[cid]["open"] and value is not None:
                    boards.append({"circle": cid, "sorted_by": field, "group": value,
                                   "open_now": circles[cid]["can_open_now"]})
            entry["worked_out"] = {"circles": inside, "boards": boards}
        else:
            # not in the game: where it would go if it were
            entry["worked_out"] = {"would_join": climb(raw, fields) if fields else []}

    counts = {}
    for entry in catalogue["things"].values():
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1
    catalogue["worked_out"] = {
        "things_by_status": counts,
        "circles_that_can_open_now": [cid for cid, c in circles.items() if c["can_open_now"]],
        "circles": circles,
    }


# ------------------------------------------------------------------ the guard

def problems(catalogue: dict, about_to_save: bool = False) -> list:
    """Everything that is wrong, each as one plain line. Empty means the catalogue is sound."""
    out = []
    dictionary = read_json(DICTIONARY)
    things = catalogue["things"]

    # 1. the dictionary
    if catalogue["dictionary_version"] != dictionary["version"]:
        out.append(f"the catalogue is at dictionary version {catalogue['dictionary_version']}, the dictionary at {dictionary['version']}")
    out += dictionary_guard.problems(dictionary, game_copy(catalogue))
    for key, entry in things.items():
        if entry["status"] not in STATUSES:
            out.append(f"{key}: '{entry['status']}' is not a status")
        if key != slug(entry["name"]):
            out.append(f"{key}: its id does not match its name '{entry['name']}'")
        if entry["status"] != IN_GAME:
            for name, value in entry.get("fields", {}).items():
                if name not in dictionary["fields"]:
                    out.append(f"{key}: field '{name}' is not in the dictionary")
                elif not dictionary_guard.allowed(value, dictionary["fields"][name]):
                    out.append(f"{key}: '{name}: {value}' is not an allowed value")

    # 2. the real files
    named = {}
    for key, entry in things.items():
        picture = entry.get("picture") or {}
        for part, mark in (("game_file", "game_sha256"), ("master_file", "master_sha256")):
            if picture.get(part):
                path = ROOT / picture[part]
                if not path.exists():
                    out.append(f"{key}: its picture {picture[part]} is not there")
                elif fingerprint(path) != picture.get(mark):
                    out.append(f"{key}: {picture[part]} is not the file the catalogue recorded (its fingerprint differs)")
        if picture.get("game_file"):
            named.setdefault(picture["game_file"], []).append(key)
        voice = entry.get("voice") or {}
        if voice.get("clip"):
            path = ROOT / voice["clip"]
            if not path.exists():
                out.append(f"{key}: its clip {voice['clip']} is not there")
            elif fingerprint(path) != voice.get("clip_sha256"):
                out.append(f"{key}: {voice['clip']} is not the file the catalogue recorded (its fingerprint differs)")
    for file, keys in named.items():
        if len(keys) > 1:
            out.append(f"{file} is named by more than one entry: {', '.join(keys)}")
    for path in sorted(PICTURES.glob("*.webp")):
        if relative(path) not in named:
            out.append(f"{relative(path)} is in the game's picture folder, and no entry names it")

    # 3. the tile records
    tiles = (read_json(RECORDS) or {"tiles": {}})["tiles"]
    chosen = set()
    for key, entry in things.items():
        tile_id = (entry.get("picture") or {}).get("tile")
        if tile_id:
            chosen.add(tile_id)
            tile = tiles.get(tile_id)
            if tile is None:
                out.append(f"{key}: its tile {tile_id} is not in the tile records")
            elif tile["review"] != "approved" or tile["thing_id"] != key:
                out.append(f"{key}: its tile {tile_id} is not an approved tile for it in the tile records")

    if about_to_save:
        return out   # the worked-out part and the two written files are about to be made afresh

    # 4. the worked-out part
    fresh = copy.deepcopy(catalogue)
    work_out(fresh)
    if fresh["worked_out"] != catalogue.get("worked_out"):
        out.append("the worked-out circles are out of date")
    out += [f"{key}: its worked-out circles and boards are out of date"
            for key in things if fresh["things"][key].get("worked_out") != things[key].get("worked_out")]

    # 5. the game's copy   6. the queue
    if json.dumps(read_json(THINGS)) != json.dumps(game_copy(catalogue)):
        out.append("Assets/data/things.json is not what the catalogue would write: someone edited the game's copy")
    if read_json(QUEUE) != queue_view(catalogue):
        out.append("tools/content/review_queue.json is not what the catalogue would write")
    return out


def notes(catalogue: dict) -> list:
    """Worth knowing, but not wrong."""
    out = []
    things, circles = catalogue["things"], catalogue["worked_out"]["circles"]
    bare = [e["name"] for e in things.values() if e["status"] == IN_GAME and not (e.get("picture") or {}).get("game_file")]
    if bare:
        out.append(f"{len(bare)} thing(s) in the game have no picture: {', '.join(bare)}")
    silent = sum(1 for e in things.values() if e["status"] == IN_GAME and not (e.get("voice") or {}).get("clip"))
    out.append(f"{silent} thing(s) in the game have no voice clip yet")
    used = {(e.get("voice") or {}).get("clip") for e in things.values()}
    spare = [p.name for p in sorted(CLIPS.glob("*.mp3")) if relative(p) not in used] if CLIPS.exists() else []
    if spare:
        out.append(f"{len(spare)} clip(s) in the clip folder belong to no entry; they are from the older game")
    tiles = (read_json(RECORDS) or {"tiles": {}})["tiles"]
    chosen = {(e.get("picture") or {}).get("tile") for e in things.values()}
    waiting = [t["thing_id"] for tile_id, t in tiles.items() if t["review"] == "approved" and tile_id not in chosen]
    if waiting:
        out.append(f"approved in the tile records but not yet in the catalogue (run publish.py): {', '.join(waiting)}")
    held = [v for c in circles.values() for v, g in c.get("groups", {}).items() if g.get("held_back_in_settings")]
    if held:
        out.append(f"held off boards by hand in settings.json, not worked out: {', '.join(sorted(set(held)))}")
    return out


# ------------------------------------------------------------------ saving

def save(catalogue: dict):
    work_out(catalogue)
    wrong = problems(catalogue, about_to_save=True)
    if wrong:
        raise SystemExit("The catalogue was NOT saved. The guard found:\n  - " + "\n  - ".join(wrong))
    write_json(CATALOGUE, catalogue)
    write_json(THINGS, game_copy(catalogue))
    write_json(QUEUE, queue_view(catalogue))


@contextlib.contextmanager
def changing(by: str):
    """The only way to change the catalogue. One script at a time; the change is kept
    only if the guard passes, and the game's copy and the queue are rewritten with it."""
    HERE.mkdir(parents=True, exist_ok=True)
    started = time.time()
    while True:
        try:
            os.close(os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            break
        except FileExistsError:
            if time.time() - LOCK.stat().st_mtime > 600:
                LOCK.unlink()      # left behind by a script that died
            elif time.time() - started > 60:
                raise SystemExit("Another script is changing the catalogue. Try again in a moment.")
            else:
                time.sleep(0.2)
    try:
        catalogue = load()
        yield catalogue
        catalogue["last_change"] = {"by": by, "on": today()}
        save(catalogue)
    finally:
        LOCK.unlink(missing_ok=True)


# ------------------------------------------------------------------ what the older scripts call

def game_store() -> dict:
    """The things in the game, as the content scripts have always read them."""
    return game_copy(load())


def put_game_store(store: dict, by: str):
    """Take a changed copy of the game's things back into the catalogue. A thing keeps
    its place, its sources, picture and voice. A thing no longer in the copy is marked
    as taken out; it is never deleted."""
    with changing(by) as catalogue:
        things = catalogue["things"]
        for key, record in store["things"].items():
            entry = things.setdefault(key, {})
            kept = {k: v for k, v in entry.items() if k not in GAME_KEYS and k != "status" and k not in HELD_KEYS}
            fresh = {}
            for k, v in record.items():
                fresh[k] = v
                if k == "name":
                    fresh["status"] = IN_GAME
            entry.clear()
            entry.update(fresh, **kept)
        for key, entry in things.items():
            if entry["status"] == IN_GAME and key not in store["things"]:
                entry["status"], entry["status_why"] = TAKEN_OUT, [f"taken out by {by} on {today()}"]
        catalogue["dictionary_version"] = store["dictionary_version"]


def set_queue(sender: str, entries: list):
    """Replace what one script holds for the owner, leaving what the others hold alone.
    An entry may say its own `status`; otherwise a check's doubt is 'waiting for the owner'."""
    with changing(sender) as catalogue:
        things = catalogue["things"]
        wanted = {slug(e["name"]) for e in entries}
        for key, entry in things.items():
            if entry.get("held_from") == sender and entry["status"] in HELD and key not in wanted:
                entry["status"], entry["status_why"] = TAKEN_OUT, [f"no longer held by {sender}, {today()}"]
            entry["also_offered"] = [o for o in entry.get("also_offered", []) if o.get("from") != sender]
            if not entry["also_offered"]:
                del entry["also_offered"]
        for item in entries:
            item = dict(item)
            status = item.pop("status", WAITING)
            key = slug(item["name"])
            entry = things.get(key)
            if entry is not None and entry["status"] == IN_GAME:
                # a thing by this name is already in the game: keep the offer beside it
                entry.setdefault("also_offered", []).append(dict(item, **{"from": sender}))
                continue
            kept = {k: v for k, v in (entry or {}).items() if k in ("sources", "picture", "voice")}
            fresh = {"name": item["name"], "status": status, "status_why": item.get("why", []),
                     "held_from": sender, "fields": item.get("fields", {})}
            if "familiar" in item:
                fresh["familiar"] = item["familiar"]
            things[key] = dict(fresh, **kept)


# ------------------------------------------------------------------ reading the ledgers again

def sync_pictures(catalogue: dict):
    """Each thing's chosen tile, from the tile records: the one approved tile linked to it."""
    tiles = (read_json(RECORDS) or {"tiles": {}})["tiles"]
    for key, entry in catalogue["things"].items():
        approved = [(tile_id, t) for tile_id, t in tiles.items() if t["review"] == "approved" and t["thing_id"] == key]
        if len(approved) != 1:
            entry.pop("picture", None)   # none yet; or two, which the guard will name
            continue
        tile_id, tile = approved[0]
        game_file = PICTURES / f"{key}.webp"
        in_game = entry["status"] == IN_GAME and game_file.exists()
        master = ROOT / tile["master_file"]
        entry["picture"] = {
            "tile": tile_id,
            "game_file": relative(game_file) if in_game else None,
            "game_sha256": fingerprint(game_file) if in_game else None,
            "master_file": tile["master_file"],
            "master_sha256": fingerprint(master) if master.exists() else tile.get("master_sha256"),
            "style": tile.get("style_version"),
            "approved": tile.get("review_note") or "by the owner",
            "approved_on": tile.get("reviewed_on") or tile.get("date"),
            "other_tries": sum(1 for t in tiles.values() if t["expected_thing"] == key) - 1,
        }


def sync_voice(catalogue: dict):
    """A clip already in the game's clip folder, for each thing that has one."""
    file_names = (read_json(PICTURE_NAMES) or {}).get("file_names", {})
    for key, entry in catalogue["things"].items():
        voice = entry.setdefault("voice", {"say": entry.get("shown_as") or entry["name"], "checked_by_ear": False})
        clip = CLIPS / f"name_{file_names.get(key, key)}.mp3"
        if clip.exists():
            voice.update(clip=relative(clip), clip_sha256=fingerprint(clip))
            voice.setdefault("clip_from", "the older game")
        else:
            voice.update(clip=None)
            voice.pop("clip_sha256", None)


def sync_sources(catalogue: dict):
    """The pages read for each thing and the sentence behind each field value, from the
    research results. Only evidence for the value the catalogue actually holds is kept."""
    for key, entry in catalogue["things"].items():
        sources = {}
        research = RESEARCH / f"{slug(entry['name'])}.json"
        facts = RESEARCH / "facts" / f"{slug(entry['name'])}.json"
        if research.exists():
            record = read_json(research)
            sources["pages"] = record.get("sources", [])
            sources["research"] = relative(research)
            if record.get("told_apart_by"):
                sources["told_apart_by"] = record["told_apart_by"]["judge"]
            if record.get("for_the_owner"):
                sources["weak_spot"] = record["for_the_owner"]
        if facts.exists():
            record = read_json(facts)
            sources.setdefault("pages", record.get("pages", []))
            sources["facts"] = relative(facts)
            evidence = {}
            for name, value in entry.get("fields", {}).items():
                got = record["fields"].get(name)
                if got is not None and (got["value"] == value or (isinstance(value, list) and got["value"] in value)):
                    evidence[name] = {k: got[k] for k in ("basis", "source", "quote", "why") if got.get(k)}
                    evidence[name].setdefault("basis", "sourced")
            sources["evidence"] = evidence
            sources["no_sentence_for"] = [n for n in entry.get("fields", {}) if n not in evidence]
        if sources:
            entry["sources"] = sources
        else:
            entry.pop("sources", None)


# ------------------------------------------------------------------ the command line

def show_circles(catalogue: dict):
    for cid, circle in catalogue["worked_out"]["circles"].items():
        mark = "OPEN  " if circle["can_open_now"] else "closed"
        print(f"  {mark}  {cid}  ({circle['label']}, {circle['things']} things)"
              + (f"  sorted by {circle['sorted_by']}" if circle.get("sorted_by") and circle["can_open_now"] else ""))
        for need in circle["needs"]:
            print(f"            needs {need}")
        for thing in circle.get("could_be_filled_by", []):
            print(f"            recorded but not in the game: {thing['name']} ({thing['status']})")


def main():
    args = sys.argv[1:]
    command = args[0] if args else ""
    if command == "refresh":
        with changing("catalogue.py refresh") as catalogue:
            sync_pictures(catalogue)
            sync_voice(catalogue)
            sync_sources(catalogue)
        print("Pictures, clips and sources read again from their ledgers.")
        return
    catalogue = load()
    if command == "check":
        wrong = problems(catalogue)
        counts = catalogue["worked_out"]["things_by_status"]
        print(f"{sum(counts.values())} entries: " + ", ".join(f"{n} {status}" for status, n in counts.items()))
        for line in notes(catalogue):
            print("  note:", line)
        if wrong:
            print(f"\nCATALOGUE GUARD FAILED - {len(wrong)} problem(s):")
            for line in wrong:
                print("  -", line)
            sys.exit(1)
        print("\nCatalogue guard passed: it agrees with the dictionary, the real files, the tile records, "
              "the game's copy and the queue.")
    elif command == "circles":
        show_circles(catalogue)
    elif command == "queue":
        for entry in catalogue["things"].values():
            if entry["status"] in HELD:
                print(f"  {entry['name']}  [{entry['status']}]  " + "; ".join(entry.get("status_why", [])))
    elif command == "show" and len(args) == 2:
        entry = catalogue["things"].get(slug(args[1]))
        print(json.dumps(entry, indent=2, ensure_ascii=False) if entry else f"No entry for '{args[1]}'.")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
