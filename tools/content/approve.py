"""Move things the owner has approved out of the review queue and into the data.

A drafted thing is held whenever the drafter or the checker had a doubt. The owner
knows the child; when he says yes, the thing goes in as drafted, marked as approved by
him. Nothing is changed about it here except that mark.

    python tools/content/approve.py "Volcano" "Desert" "Cave"
"""
import sys

from lib import DICTIONARY, REVIEW_QUEUE, THINGS, read_json, slug, write_json

SOURCE = "deepseek:drafted+checked, approved by the owner"
FAMILIAR_IF_UNKNOWN = 0.75  # older queue entries did not record the drafter's figure


def main():
    names = sys.argv[1:]
    if not names:
        raise SystemExit("Name the queued things to approve.")
    dictionary = read_json(DICTIONARY)
    store = read_json(THINGS)
    queue = read_json(REVIEW_QUEUE)["for_the_owner"]

    wanted = {slug(name) for name in names}
    found = [e for e in queue if slug(e["name"]) in wanted and e.get("from", "").startswith("check:")]
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
            "source": SOURCE,
            "drafted_in": entry["from"].split(":", 1)[1],
            "notes": {"general": "Held at first: " + "; ".join(entry["why"])},
        }
    write_json(THINGS, store)
    write_json(REVIEW_QUEUE, {"for_the_owner": [e for e in queue if e not in found]})
    print(f"Approved by the owner and added: {', '.join(e['name'] for e in found)}.")


if __name__ == "__main__":
    main()
