"""Carry new dictionary fields back to the things that already exist.

When the dictionary gains a field, every existing thing is reviewed against it: the
field is added where it applies and deliberately left out where it does not, and the
thing is then stamped with the new dictionary version. A missing field on a stamped
thing was therefore left out on purpose.

For now the values come only from what the owner has approved (field_proposals.json:
the `have` lists, `assign` and `twins`). If a thing needs a value nobody has approved,
the run stops and names it; nothing is guessed. Filling such gaps with an AI draft and
an independent check is the planned next step.

    python tools/content/fill.py
"""
import sys

from lib import DICTIONARY, ROOT, THINGS, applies, read_json, write_json

PROPOSALS = ROOT / "tools/content/field_proposals.json"


def approved_values() -> tuple:
    """field -> {thing: value}, and thing -> {field: note}, from the approved proposals."""
    values, notes = {}, {}
    for key, proposal in read_json(PROPOSALS).items():
        if key == "about" or not proposal["status"].startswith("approved"):
            continue
        chosen = values.setdefault(proposal["field"], {})
        for value, group in proposal["values"].items():
            for thing in group["have"]:
                chosen[thing] = value
        chosen.update(proposal.get("assign", {}))
        for field, by_thing in proposal.get("twins", {}).items():
            values.setdefault(field, {}).update(by_thing)
        for thing, by_field in proposal.get("notes", {}).items():
            notes.setdefault(thing, {}).update(by_field)
    return values, notes


def main():
    dictionary = read_json(DICTIONARY)
    version = dictionary["version"]
    store = read_json(THINGS)
    values, notes = approved_values()

    filled, unanswered = 0, []
    for key, thing in store["things"].items():
        seen = thing.get("reviewed", 0)
        if seen >= version:
            continue
        changed = True
        while changed:  # one new field can make another apply (kind_of_plant -> tree_academic)
            changed = False
            for name, definition in dictionary["fields"].items():
                if definition["since"] <= seen or name in thing["fields"]:
                    continue
                if not applies(definition["expected_on"], thing["fields"]):
                    continue
                if key not in values.get(name, {}):
                    unanswered.append(f"{key}: needs '{name}', and the owner has approved no value for it")
                    continue
                thing["fields"][name] = values[name][key]
                if name in notes.get(key, {}):
                    thing.setdefault("notes", {})[name] = notes[key][name]
                filled += 1
                changed = True
        unanswered = sorted(set(unanswered))

    if unanswered:
        print(f"STOPPED - nothing written. {len(unanswered)} value(s) are not approved:")
        for line in unanswered:
            print("  -", line)
        sys.exit(1)

    stamped = 0
    for thing in store["things"].values():
        if thing.get("reviewed", 0) < version:
            thing["reviewed"] = version
            stamped += 1
    store["dictionary_version"] = version
    write_json(THINGS, store)
    print(f"Filled {filled} value(s); stamped {stamped} thing(s) as reviewed against version {version}.")


if __name__ == "__main__":
    main()
