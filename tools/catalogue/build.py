"""Build the catalogue, once, from the files that held its contents until now.

Nothing is deleted and nothing in the game changes. Before anything is written, this
PROVES that nothing was lost:
  - the game's copy the new catalogue would write equals today's things.json,
    thing for thing and in the same order;
  - the queue it would write equals today's review queue;
  - the catalogue's own guard finds nothing wrong.
If any of the three fails, it stops and writes nothing.

    python tools/catalogue/build.py
"""
import json
import sys

import catalogue as cat
from catalogue import (CATALOGUE, EXCLUDED, IN_GAME, LATER, NOT_YET, QUEUE, ROOT, STATUSES, THINGS, WAITING,
                       read_json, slug, write_json)

sys.path.insert(0, str(ROOT / "tools/content"))
import owner_list   # noqa: E402  the owner's lists: what is excluded, and why

PRONUNCIATION = ROOT / "tools/voice/pronunciation.json"


def main():
    if CATALOGUE.exists() and "--again" not in sys.argv:
        raise SystemExit("The catalogue already exists. It is the master record now; it is not rebuilt from the "
                         "older files. (--again rebuilds it, and loses anything recorded only in it.)")
    store, queue = read_json(THINGS), read_json(QUEUE)
    catalogue = {
        "about": "The master record of every thing: what is known about it, where that came from, its picture "
                 "and its voice clip, and (worked out, never set by hand) its circles and boards. Read and "
                 "written only through tools/catalogue/catalogue.py. Assets/data/things.json is the game's copy "
                 "of it, and tools/content/review_queue.json is its list of what is held.",
        "dictionary_version": store["dictionary_version"],
        "statuses": STATUSES,
        "things": {},
    }
    things = catalogue["things"]

    # 1. the things in the game, in today's order, each key kept in its place
    for key, record in store["things"].items():
        entry = things[key] = {}
        for name, value in record.items():
            entry[name] = value
            if name == "name":
                entry["status"] = IN_GAME

    # 2. what is held: the review queue, in its order
    candidates = {slug(name) for name in owner_list.FLYER_CANDIDATES}
    for item in queue["for_the_owner"]:
        key, sender = slug(item["name"]), item.get("from", "")
        status = WAITING if sender.startswith("check:") else NOT_YET if key in candidates else LATER
        entry = things[key] = {"name": item["name"], "status": status, "status_why": item["why"],
                               "held_from": sender, "fields": item["fields"]}
        if "familiar" in item:
            entry["familiar"] = item["familiar"]

    # 3. what the owner ruled out
    for key, why in owner_list.EXCLUDED.items():
        things[key] = {"name": key.replace("_", " ").capitalize(), "status": EXCLUDED, "status_why": [why],
                       "held_from": "owner", "fields": {}}

    # 4. pictures, clips and sources, from their ledgers; the pronunciation list folded in
    cat.sync_pictures(catalogue)
    cat.sync_voice(catalogue)
    spoken = read_json(PRONUNCIATION)
    for key, how in spoken["names"].items():
        if key in things:
            things[key]["voice"].update(say=how["say"], sounds_like=how["sounds_like"],
                                        checked_by_ear=how["checked_by_ear"])
    cat.sync_sources(catalogue)
    cat.work_out(catalogue)

    # 5. the proof, before anything is written
    failed = []
    if json.dumps(cat.game_copy(catalogue)) != json.dumps(store):
        failed.append("the game's copy would differ from today's things.json")
    if cat.queue_view(catalogue) != queue:
        failed.append("the queue would differ from today's review queue")
    failed += cat.problems(catalogue, about_to_save=True)
    if failed:
        raise SystemExit("NOTHING WAS WRITTEN. The proof failed:\n  - " + "\n  - ".join(failed))

    catalogue["built"] = {"on": cat.today(), "from": "things.json, the review queue, the owner's lists, the tile "
                                                     "records, the pronunciation list and the research results"}
    cat.save(catalogue)
    spoken["moved"] = ("Folded into the catalogue on " + cat.today() + ": each entry's `voice` part now holds how to "
                       "say its name. This file is kept, and is no longer read.")
    write_json(PRONUNCIATION, spoken)

    counts = catalogue["worked_out"]["things_by_status"]
    print("Built tools/catalogue/catalogue.json: " + ", ".join(f"{n} {status}" for status, n in counts.items()) + ".")
    print("Proved: the game's copy equals today's things.json, the queue equals today's review queue, "
          "and the guard finds nothing wrong.")
    wrong = cat.problems(cat.load())
    print("After saving, the full guard says: " + ("nothing wrong." if not wrong else "; ".join(wrong)))


if __name__ == "__main__":
    main()
