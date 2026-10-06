"""Step 2 of 3 - an independent second pass over the draft.

Every drafted thing is put to DeepSeek again as a set of claims, with no sight of
the drafting conversation. A thing is accepted only if every claim comes back "ok"
and the checker agrees a four-year-old would recognise it. Anything else goes to
review_queue.json for the owner - it is never fixed silently.

Accepted things are written to Assets/data/things.json, stamped with the
dictionary version they were reviewed against.

    python tools/content/check.py
"""
from lib import (CHECKED, DICTIONARY, DRAFT, REVIEW_QUEUE, THINGS, ask_json, deepseek, label,
                 read_json, set_queue, slug, write_json)
from owner_list import EXCLUDED, FAMILIAR_KINDS

SOURCE = "deepseek:drafted+checked"
BATCH = 12

SYSTEM = (
    "You are a careful fact-checker for a sorting game played by a four-year-old in India. "
    "Judge each claim strictly, using words in their everyday sense: a tomato plant is a plant; "
    "a spider is NOT an insect; a whale is NOT a fish; a mushroom is NOT a plant; a bat is NOT a bird; "
    "a frog is NOT a reptile. If experts or everyday speech genuinely disagree, say 'debated'. "
    "Reply with a single JSON object and nothing else."
)


# How familiarity is judged. Recalibrated on 6 Oct 2026: the first wording was too strict.
FAMILIARITY = (
    "Also say whether a four-year-old in India would recognise the thing (true/false). "
    "Recognising means he would know it on sight or by name from daily life, picture books, "
    "cartoons or a visit to a zoo. Judge the thing itself, not whether he knows facts about it. "
    "Do not be strict: ordinary animals and everyday objects count as recognised. Answer false "
    "only for things most young children have never met. "
    f"The owner, who knows the child, confirms these kinds of thing are familiar to him: {', '.join(FAMILIAR_KINDS)}."
)


def probe(names: list):
    """Ask only the familiarity question about some names. Writes nothing; for checking
    the calibration, or for seeing whether a circle could be filled with familiar things."""
    lines = [FAMILIARITY, "", "Things:"] + [f"- {name}" for name in names]
    lines += ["", 'Return exactly: {"things": [{"name": "...", "recognisable": true, "why": "a few words"}]}']
    reply = ask_json(deepseek(), SYSTEM, "\n".join(lines), temperature=0.0)
    for item in reply.get("things", []):
        mark = "familiar  " if item.get("recognisable") is True else "UNFAMILIAR"
        print(f"  {mark}  {item.get('name')}  - {item.get('why', '')}")


def claims(thing: dict, dictionary: dict) -> list:
    out = []
    for name, value in thing["fields"].items():
        definition = dictionary["fields"][name]
        out.append({"field": name, "question": definition["wording"], "claimed": label(definition, value)})
    return out


def prompt(batch: list, dictionary: dict) -> str:
    lines = [
        "Check each thing below. For every claim give a verdict:",
        "  ok      - true in the everyday sense",
        "  wrong   - false; say what is true instead",
        "  debated - experts or everyday speech genuinely disagree; say why in one sentence",
        "",
        FAMILIARITY,
        "",
    ]
    for thing in batch:
        lines.append(f"- {thing['name']}")
        for claim in claims(thing, dictionary):
            lines.append(f"    {claim['field']}: \"{claim['question']}\" -> {claim['claimed']}")
    lines += [
        "",
        'Return exactly: {"things": [{"name": "...", "recognisable": true, '
        '"verdicts": {"<field>": {"verdict": "ok|wrong|debated", "say": "..."}}}]}',
    ]
    return "\n".join(lines)


def main():
    dictionary = read_json(DICTIONARY)
    draft = read_json(DRAFT)
    if draft is None:
        raise SystemExit("No draft found. Run draft.py first.")
    if draft["dictionary_version"] != dictionary["version"]:
        raise SystemExit("The draft was made against a different dictionary version. Draft again.")

    client = deepseek()
    drafted = [t for t in draft["things"] if slug(t["name"]) not in EXCLUDED]  # the owner ruled these out
    verdicts = {}
    for start in range(0, len(drafted), BATCH):
        batch = drafted[start:start + BATCH]
        reply = ask_json(client, SYSTEM, prompt(batch, dictionary), temperature=0.0)
        for item in reply.get("things", []):
            verdicts[slug(str(item.get("name", "")))] = item
        print(f"  checked {min(start + BATCH, len(drafted))}/{len(drafted)}")
    write_json(CHECKED, {"dictionary_version": dictionary["version"], "verdicts": verdicts})

    store = read_json(THINGS, {"dictionary_version": dictionary["version"], "things": {}})
    # Things this same plan produced on an earlier run are re-decided from scratch.
    # Everything else - other plans, the owner's list - is left exactly as it is.
    plan = draft["plan"]
    store["things"] = {k: v for k, v in store["things"].items() if v.get("drafted_in") != plan}
    queue = []
    seen = {}
    for thing in drafted:
        key = slug(thing["name"])
        reasons = []
        verdict = verdicts.get(key)
        if key in seen:
            reasons.append(f"drafted twice (also under {seen[key]})")
        if key in store["things"] and key not in seen:
            reasons.append("a thing with this name is already in the data")
        if verdict is None:
            reasons.append("the checker returned nothing for it")
        else:
            if verdict.get("recognisable") is not True:
                reasons.append("the checker doubts a four-year-old would recognise it")
            for name in thing["fields"]:
                found = (verdict.get("verdicts") or {}).get(name)
                if found is None:
                    reasons.append(f"{name}: not checked")
                elif found.get("verdict") != "ok":
                    reasons.append(f"{name}: {found.get('verdict')} - {found.get('say', '')}".strip())
        if thing["unsure"]:
            reasons.append(f"the drafter was unsure: {thing['unsure']}")
        seen.setdefault(key, thing["fields"])

        if reasons:
            queue.append({"name": thing["name"], "fields": thing["fields"], "why": reasons})
            continue
        store["things"][key] = {
            "name": thing["name"],
            "fields": thing["fields"],
            "familiar": round(thing["familiar"], 2),
            "reviewed": dictionary["version"],
            "source": SOURCE,
            "drafted_in": plan,
        }

    store["dictionary_version"] = dictionary["version"]
    write_json(THINGS, store)
    set_queue(f"check:{plan}", queue)
    accepted = len(drafted) - len(queue)
    print(f"Accepted {accepted}; {len(queue)} sent to {REVIEW_QUEUE.name}. Next: python tools/content/guard.py")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 2 and sys.argv[1] == "--probe":
        probe(sys.argv[2:])
    else:
        main()
