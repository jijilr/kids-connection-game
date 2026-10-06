"""Move things the owner has approved out of the review queue and into the data.

A drafted thing is held whenever the drafter, the checker or the job had a doubt. The
owner knows the child; when he says yes, the thing goes in as drafted, marked as
approved by him. Nothing is changed about it here except that mark. A thing approved
this way has no picture yet: the next run of tools/prepare_next.py draws it.

    python tools/content/approve.py "Volcano" "Desert" "Cave"
"""
import sys

from lib import DICTIONARY, catalogue, read_json, slug

SOURCE = "deepseek:drafted+checked, approved by the owner"
FAMILIAR_IF_UNKNOWN = 0.75  # older queue entries did not record the drafter's figure


def main():
    names = sys.argv[1:]
    if not names:
        raise SystemExit("Name the queued things to approve.")
    dictionary = read_json(DICTIONARY)
    master = catalogue()
    store = master.game_store()
    queue = master.queue_view(master.load())["for_the_owner"]

    wanted = {slug(name) for name in names}
    found = [e for e in queue if slug(e["name"]) in wanted and e.get("from", "").startswith(("check:", "job:"))]
    missing = wanted - {slug(e["name"]) for e in found}
    if missing:
        raise SystemExit(f"Not in the queue as a drafted thing: {sorted(missing)}. Nothing changed.")
    clash = [e["name"] for e in found if slug(e["name"]) in store["things"]]
    if clash:
        raise SystemExit(f"Already in the data: {clash}. Nothing changed.")

    for entry in found:
        store["things"][slug(entry["name"])] = {
            "name": entry["name"],
            "fields": entry["fields"],
            "familiar": entry.get("familiar", FAMILIAR_IF_UNKNOWN),
            "reviewed": dictionary["version"],
            "source": "job:grounded+checked, approved by the owner" if entry["from"].startswith("job:") else SOURCE,
            "drafted_in": entry["from"].split(":", 1)[1],
            "notes": {"general": "Held at first: " + "; ".join(entry["why"])},
        }
    # in the catalogue the thing's status becomes "in the game", which takes it off the queue
    master.put_game_store(store, by="approve.py")
    print(f"Approved by the owner and added: {', '.join(e['name'] for e in found)}.")


if __name__ == "__main__":
    main()
