"""Step 3 of 3 - the guard. Purely mechanical; no AI. Fails loudly, naming the thing and the field.

It refuses the data if any thing:
  - carries a field that is not in the dictionary, or a value the field does not allow;
  - is missing a field the dictionary expects on it;
  - carries a field the dictionary does not expect on it;
  - is not stamped as reviewed against the current dictionary version.
It also reports which fields can fill a board (four values, four things each).

    python tools/content/guard.py
"""
import sys
from collections import Counter, defaultdict

from lib import DICTIONARY, THINGS, allowed_values, applies, catalogue, label, read_json


def allowed(value, definition: dict) -> bool:
    """One allowed value; or, for a thing that truly fits several, a list of them; or 'depends'."""
    choices = allowed_values(definition)
    if isinstance(value, list):
        return len(value) >= 2 and all(v in choices for v in value)
    return value == "depends" or value in choices


def problems(dictionary: dict, store: dict) -> list:
    out = []
    version = dictionary["version"]
    fields = dictionary["fields"]
    for key, thing in store["things"].items():
        for name, value in thing["fields"].items():
            if name not in fields:
                out.append(f"{key}: field '{name}' is not in the dictionary")
            elif not allowed(value, fields[name]):
                out.append(f"{key}: '{name}: {value}' is not an allowed value")
            elif value == "depends" and name not in thing.get("notes", {}):
                out.append(f"{key}: '{name}: depends' needs a note saying why")
        for name, definition in fields.items():
            expected = applies(definition["expected_on"], thing["fields"])
            differs_only = definition.get("only_where_science_differs")
            if expected and name not in thing["fields"] and not differs_only:
                out.append(f"{key}: missing '{name}', which the dictionary expects on it")
            if differs_only and thing["fields"].get(name) is not None \
                    and thing["fields"].get(name) == thing["fields"].get(definition["everyday_partner"]):
                out.append(f"{key}: '{name}' is the same as its everyday value; it is recorded only where science differs")
            if not expected and name in thing["fields"]:
                out.append(f"{key}: carries '{name}', which does not apply to it")
        for name in thing.get("notes", {}):
            if name != "general" and name not in thing["fields"]:
                out.append(f"{key}: has a note on '{name}' but no such field")
        if thing.get("reviewed") != version:
            out.append(f"{key}: not stamped as reviewed against dictionary version {version}")
    return out


def report(dictionary: dict, store: dict):
    things = store["things"]
    print(f"{len(things)} things, dictionary version {dictionary['version']}")
    print("by source:", dict(Counter(t.get("source", "?") for t in things.values())))
    for name, definition in dictionary["fields"].items():
        counts = defaultdict(int)
        for thing in things.values():
            value = thing["fields"].get(name)
            if value is not None and value != "depends" and not isinstance(value, list):
                counts[label(definition, value)] += 1
        full = [v for v, n in counts.items() if n >= 4]
        can = "can fill a board" if len(full) >= 4 and definition.get("sorts_boards", True) else "cannot fill a board yet"
        print(f"  {name}: {dict(counts)}  -> {can}")


def main():
    dictionary = read_json(DICTIONARY)
    store = read_json(THINGS)
    if store is None:
        raise SystemExit("No things file yet.")
    report(dictionary, store)
    found = problems(dictionary, store)
    if found:
        print(f"\nGUARD FAILED - {len(found)} problem(s):")
        for line in found:
            print("  -", line)
        sys.exit(1)
    print("\nGuard passed: no orphans, nothing missing, every thing stamped.")

    # the catalogue is the master record: check it against the real files too
    master = catalogue()
    wrong = master.problems(master.load())
    if wrong:
        print(f"\nCATALOGUE GUARD FAILED - {len(wrong)} problem(s):")
        for line in wrong:
            print("  -", line)
        sys.exit(1)
    print("Catalogue guard passed: it agrees with the real files, the tile records, the game's copy and the queue.")


if __name__ == "__main__":
    main()
