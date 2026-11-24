"""A question asked of a wider circle, so that its answers are circles that cross the others.

The owner, on the night of 24 Nov 2026: "inspite of being accomodating, we still assume
concentric circles paradigm. but knowledge is never that... how do we accomadate other
possible circles along with the main center and concentric circle". And then: "yes, build
the small proof." (DESIGN.md, section 8a.)

The data was never concentric: a thing is a list of answers to questions. What made the
game concentric is that a question lived inside one circle. "Is it mostly a pet, a farm
animal or a wild animal?" was asked of mammals, and asked again, as a second field, of
birds. So "Pets at home" could never hold a dog and a parrot together.

This tool widens the reach of ONE question that is already in the dictionary to every
thing of a circle above it:

  1. Another field that asks the very same library question inside that circle is the
     same question, answered already: its answers are taken over, and it is marked
     `merged_into` (kept, with its values on the things; it sorts nothing and is no longer
     compared with anything).
  2. Every other thing of the circle is sorted twice, by two calls that share no wording,
     with the question's own groups and a few of each group's things as examples, taken
     from every kind that has answered so far. Both must give the same single group. A
     thing the two put in different groups lists both, as the dictionary rules, and so
     stays off sets sorted by the question until four such things can be the group "in
     between".
  3. A QUESTION HAS A REACH. A thing that neither check can place is not forced into a
     group and does not stop the run: the question is not about it, and it does not carry
     the answer. (The first real run, 24 Nov 2026: both checks placed the fish and the
     insects, and both refused every dinosaur. A dinosaur is not a pet, a farm animal or
     a wild animal; it is gone.) So a question belongs to every thing it is true of, and
     only to those. The dictionary then says the question is asked `where_it_fits`.
  4. The dictionary says where the question is now asked. A field that hung from one of
     its answers (what a wild land animal eats, asked of mammals) is told to stay where
     it was.

Nothing is drawn and no thing is added: a crossing circle is made of things the game
already has. The game then finds the wider circle by itself: a place may ask more than
one question, and a place is where circles overlap, whatever the road to it.

    python tools/job/cross.py FIELD --of CIRCLE --dry-run     what would be done; nothing is sent
    python tools/job/cross.py FIELD --of CIRCLE --cap 5       do it, under a hard cap in rupees
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
for folder in ("tools/research", "tools/content", "tools/catalogue", "tools/job"):
    if str(ROOT / folder) not in sys.path:
        sys.path.insert(0, str(ROOT / folder))
import catalogue as cat                         # noqa: E402
import reslib                                   # noqa: E402
import fields as field_rules                    # noqa: E402  the two sortings
import expand                                   # noqa: E402

LIBRARY = ROOT / "tools/content/field_library.json"
DEFAULT_CAP_INR = 5
EXAMPLES = 4          # things of each group shown to the two sortings


def same_question(a: dict, b: dict) -> bool:
    """Two fields that ask one library question with the same groups."""
    return bool(a.get("library")) and a.get("library") == b.get("library") and a["values"] == b["values"]


def inside(rule, path: list) -> bool:
    """Is a field's `expected_on` rule narrower than the circle the path leads to?"""
    return isinstance(rule, dict) and all(rule.get(f) == v or f not in rule for f, v in path) and any(
        f not in dict(path) for f in rule)


def plan(dictionary: dict, things: dict, field: str, path: list) -> dict:
    """What widening `field` to the circle at `path` would do, before anything is asked.
    `things` are the things in the game. Returns {"keep": keys that carry it, "take_over":
    {key: (twin field, value)}, "to_sort": keys, "twins": [fields], "hangs": [fields that
    hang from one of its answers]}."""
    definition = dictionary["fields"][field]
    twins = [name for name, other in dictionary["fields"].items()
             if name != field and same_question(definition, other) and not other.get("merged_into")
             and inside(other.get("expected_on"), path)]
    members = [k for k, t in things.items() if all(t["fields"].get(f) == v for f, v in path)]
    keep = [k for k in members if field in things[k]["fields"]]
    take_over = {k: next((twin, things[k]["fields"][twin]) for twin in twins if twin in things[k]["fields"])
                 for k in members if k not in keep and any(twin in things[k]["fields"] for twin in twins)}
    to_sort = [k for k in members if k not in keep and k not in take_over]
    hangs = [name for name, other in dictionary["fields"].items()
             if isinstance(other.get("expected_on"), dict) and (field in other["expected_on"]
                                                              or any(t in other["expected_on"] for t in twins))]
    return {"keep": keep, "take_over": take_over, "to_sort": to_sort, "twins": twins, "hangs": hangs}


def sort_them(client, config, spend, chain: str, definition: dict, such_as: dict, names: list) -> tuple:
    """Two separate sortings of `names`. Returns (name -> its one group; name -> the
    groups the two named, where they did not agree on one; names neither could place)."""
    values = [{"key": key, "label": label, "such_as": such_as.get(key, [])[:EXAMPLES]}
              for key, label in definition["values"].items()]
    keys, labels = [v["key"] for v in values], {v["key"]: v["label"] for v in values}
    placed, several, nowhere, alone = {}, {}, [], []
    for start in range(0, len(names), 12):      # a dozen cards to a call: a long list is sorted less carefully
        batch = names[start:start + 12]
        first, second = field_rules.sort_twice(client, config, spend, chain,
                                               {"wording": definition["wording"], "values": values}, batch)
        one, _ = field_rules.one_value_each(batch, first, second, keys, labels)
        placed.update(one)
        for name in batch:
            if name in one:
                continue
            named = [v for v in keys if v in field_rules.values_named(name, first, second, keys, labels)]
            if len(named) >= 2:
                several[name] = named
            elif len(named) == 1:
                alone.append(name)      # one check gave it a group and the other gave it none
            else:
                nowhere.append(name)
    # A card among cards that fit nowhere is itself called "none" too easily (the mango tree,
    # asked beside the rose and the grass). Where only one check placed a thing, it is asked
    # again by itself; it is placed only if both checks then agree.
    for name in alone:
        first, second = field_rules.sort_twice(client, config, spend, chain,
                                               {"wording": definition["wording"], "values": values}, [name])
        one, _ = field_rules.one_value_each([name], first, second, keys, labels)
        if name in one:
            placed[name] = one[name]
        else:
            named = [v for v in keys if v in field_rules.values_named(name, first, second, keys, labels)]
            several[name] = named if len(named) >= 2 else several.get(name)
            if not several[name]:
                del several[name]
                nowhere.append(name)
    return placed, several, nowhere


def examples(things: dict, answered: dict, kinds_by: str = None) -> dict:
    """A few things of each group to show the two sortings: the best known, and from every
    kind of thing that has answered so far, so that a pile does not look as if it were
    for one kind only. (With mammals alone as examples, one check placed no fish at all.)"""
    by = {}
    for key in sorted(answered, key=lambda k: -things[k].get("familiar", 0)):
        if isinstance(answered[key], str):
            kind = things[key]["fields"].get(kinds_by) if kinds_by else None
            by.setdefault(answered[key], {}).setdefault(str(kind), []).append(things[key]["name"])
    out = {}
    for value, kinds in by.items():
        out[value] = []
        for i in range(EXAMPLES):
            for names in kinds.values():
                if i < len(names) and len(out[value]) < EXAMPLES:
                    out[value].append(names[i])
    return out


def rules_after(dictionary: dict, field: str, path: list, twins: list, everywhere: bool = True) -> dict:
    """The dictionary as it stands once the question is asked of the whole circle. A field
    that hung from one of the question's answers stays where it was: it is still expected
    only where the question used to be asked."""
    fields = dictionary["fields"]
    was = {name: dict(fields[name]["expected_on"]) for name in [field] + twins}
    for name, other in fields.items():
        rule = other.get("expected_on")
        if not isinstance(rule, dict) or name == field or name in twins:
            continue
        for asked in [field] + twins:
            if asked in rule:
                answer = rule.pop(asked)
                other["expected_on"] = {**was[asked], **rule, field: answer}
                rule = other["expected_on"]
    already = fields[field].get("expected_on") == dict(path)
    fields[field]["expected_on"] = dict(path)
    if not everywhere:
        # it is asked wherever it fits inside the circle: a thing it does not fit carries no answer
        fields[field]["where_it_fits"] = True
    if not already:
        fields[field].setdefault("crossed", []).append({
            "on": reslib.today(), "now_asked_of": dict(path), "was_asked_of": was[field],
            "why": "the owner, 24 Nov 2026: circles cross; a question belongs to every thing it is true of"})
    for twin in twins:
        fields[twin]["merged_into"] = field
        fields[twin]["sorts_boards"] = False
        fields[twin]["merged"] = {"on": reslib.today(), "why": f"it asks the same question as {field}, which is now asked of "
                                                              "the whole circle; its values are kept on the things"}
    return dictionary


def main():
    args = sys.argv[1:]
    if not args or "--of" not in args:
        raise SystemExit("Usage: python tools/job/cross.py FIELD --of CIRCLE [--dry-run] [--cap RUPEES]")
    field, cid = args[0], args[args.index("--of") + 1]
    config, dictionary = cat.read_json(reslib.CONFIG), cat.read_json(cat.DICTIONARY)
    catalogue = cat.load()
    things = cat.game_copy(catalogue)["things"]
    circles = expand.build_circles(dictionary, things, cat.read_json(cat.SETTINGS))
    if field not in dictionary["fields"] or cid not in circles or cid == "seed":
        raise SystemExit(f"No such field or circle. Circles: python tools/catalogue/catalogue.py circles")
    path = cat.circle_path(circles, cid)
    definition = dictionary["fields"][field]
    again = definition.get("expected_on") == dict(path)     # asked of this circle already: only what is left is sorted
    if not again and not inside(definition.get("expected_on"), path):
        raise SystemExit(f'"{definition["wording"]}" is not asked inside {circles[cid]["label"]} today, so it cannot be widened to it.')
    todo = plan(dictionary, things, field, path)
    print(f'"{definition["wording"]}" is to be asked of all of {circles[cid]["label"]}.')
    print(f"  {len(todo['keep'])} thing(s) already carry it.")
    for twin in todo["twins"]:
        count = sum(1 for t, _ in todo["take_over"].values() if t == twin)
        print(f"  {count} thing(s) answered the same question under the field '{twin}'; their answers are taken over.")
    print(f"  {len(todo['to_sort'])} thing(s) are to be sorted by two checks: "
          + ", ".join(things[k]["name"] for k in todo["to_sort"][:12]) + (" ..." if len(todo["to_sort"]) > 12 else ""))
    for name in todo["hangs"]:
        print(f"  '{name}' hangs from one of its answers and stays where it was.")
    if "--dry-run" in args:
        print("A dry run: nothing was sent, nothing was spent, nothing was changed.")
        return

    cap = float(args[args.index("--cap") + 1]) if "--cap" in args else DEFAULT_CAP_INR
    spend = reslib.Spend(config, cap / config["inr_per_usd"])
    names = [things[k]["name"] for k in todo["to_sort"]]
    answered = {k: things[k]["fields"][field] for k in todo["keep"]}
    answered.update({k: value for k, (_, value) in todo["take_over"].items()})
    such_as = examples(things, answered, circles[cid].get("sorted_by"))
    chain = " > ".join(dictionary["fields"][f]["values"][str(v)] for f, v in path)
    client = reslib.deepseek() if names else None
    placed, several, nowhere = sort_them(client, config, spend, chain, definition, such_as, names) if names else ({}, {}, [])
    if nowhere and (placed or several):
        # One pass over a long list is not careful enough to say that a question does not fit a
        # thing (the first run left the mango tree out of "the fruit"). What was not placed is
        # asked once more, a few at a time, with what was placed shown among the examples.
        for name, value in placed.items():
            such_as.setdefault(value, []).insert(0, name)
        more, more_several, nowhere = sort_them(client, config, spend, chain, definition, such_as, nowhere)
        placed.update(more)
        several.update(more_several)
    spent = f"Spent: Rs {spend.usd * config['inr_per_usd']:.2f}."

    saved = {p: p.read_text(encoding="utf-8") for p in (cat.DICTIONARY, LIBRARY)}
    reslib.write_json(cat.DICTIONARY, rules_after(dictionary, field, path, todo["twins"],
                                                  everywhere=not nowhere and not definition.get("where_it_fits")))
    library = cat.read_json(LIBRARY)
    for question in library.get("questions", []):
        # noted, not offered more widely: `for` still says which circles may take the question
        # as their own, and a circle whose things already answer it is never offered it again
        if question.get("id") == definition.get("library") and cid not in question.get("asked_across", []):
            question.setdefault("asked_across", []).append(cid)
    reslib.write_json(LIBRARY, library)
    labels = definition["values"]
    try:
        with cat.changing(f"cross.py: {field} asked of {cid}") as changed:
            for key, (twin, value) in todo["take_over"].items():
                changed["things"][key]["fields"][field] = value
                if twin in changed["things"][key].get("notes", {}):
                    changed["things"][key].setdefault("notes", {})[field] = changed["things"][key]["notes"][twin]
            for key in todo["to_sort"]:
                name = things[key]["name"]
                if name in nowhere:
                    continue        # the question is not about it
                if name in placed:
                    changed["things"][key]["fields"][field] = placed[name]
                else:
                    changed["things"][key]["fields"][field] = several[name]
                    changed["things"][key].setdefault("notes", {})[field] = (
                        "Two checks could not give it one group: " + " and ".join(labels[v] for v in several[name])
                        + f". It stays off sets sorted by this question. Asked of all of {circles[cid]['label']} on {reslib.today()}.")
    except SystemExit:
        for p, text in saved.items():       # the guard refused: the dictionary and the library are put back
            p.write_text(text, encoding="utf-8", newline="\n")
        raise
    expand.rebuild()
    counts = {}
    for name, value in placed.items():
        counts[labels[value]] = counts.get(labels[value], 0) + 1
    print("Sorted: " + ", ".join(f"{n} in '{label}'" for label, n in counts.items()) + ".")
    for name, values in several.items():
        print(f"  {name}: the two checks named {' and '.join(labels[v] for v in values)}; it lists both.")
    if nowhere:
        print(f"The question does not fit {len(nowhere)} thing(s), by both checks or by one; they carry no answer to it: "
              + ", ".join(nowhere) + ".")
    print(f'Done. "{definition["wording"]}" is now asked of all of {circles[cid]["label"]}. ' + spent)


if __name__ == "__main__":
    main()
