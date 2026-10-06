"""Step 5 - what tells each animal from its look-alikes?

This is the one research step that needs judgement, not copying. Animals that appear
together in the game (the same kind of dinosaur, the giant snakes) are shown to a
judge side by side, each with its own features, already checked against the saved
pages. For each animal the judge chooses the few features of shape and proportion that set it
apart, and may add its body covering (feathers, fuzz, armour) as one more. It can only choose from the lists, so nothing ungrounded gets in.

The judges are listed in config.json: the everyday DeepSeek model, DeepSeek's stronger
model with reasoning on, and an OpenAI model. All get the same lists and the same
question, so their choices can be compared.

    python tools/research/tell_apart.py --judge deepseek-pro [--cap 0.30]
    python tools/research/tell_apart.py --use deepseek-pro      write that judge's choice into the results

Each judge's choice is saved in tools/research/out/tell_apart_<judge>.json.
"""
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from fetch import prehistoric
from reslib import CONFIG, OUT, Spend, ask, deepseek, openai_client, read_json, slug, today, write_json

# plain skin or scales tell nothing apart in a small picture; kept out even if a judge chooses them
PLAIN = re.compile(r"\b(scales?|scaly|skin)\b", re.I)

JUDGE = "You compare lists. You choose only from the lists given and add nothing of your own."

TASK = """These extinct animals appear together in a sorting game for a small child. Each is shown as one small picture on a plain white background, so the pictures must be told apart at a glance. Each animal below has a list of features, already checked against sources.

First compare the animals: for each one, what does its outline have that the others here do not?

Then, for EACH animal, choose from ITS OWN list in two steps.

"shape": the 2 to 4 features of SHAPE and PROPORTION that best tell it from the other animals here. These are the build of the body, the stance, the neck, the shape of the head, snout or beak, whether the jaws carry teeth or end in a toothless beak, crests, horns, plates, sails, spines, fins, flippers, wings, the tail, and how long one part is beside another.
- Do not choose size in metres or weight: nothing on a plain background shows how big an animal is.
- Do not choose fine detail a small picture cannot show, such as the shape of the scales, the number or exact shape of the teeth, single claws, or bones.
- Do not choose a feature every other animal here has too.
If an animal's list holds nothing of shape that sets it apart, choose its best one or two features and say so in "why".

"covering": after that, at most ONE more feature: what covers its body, if its list names it and it helps tell the animal apart. Feathers, fur or fuzz, and bony armour are coverings. Plain skin or scales are not: leave those out. A covering is ADDED to the shape features. It never takes the place of one: choose the shape features first, exactly as you would if no covering were listed.

Return JSON: {{"<animal name>": {{"shape": ["f2", "f5"], "covering": ["f9"], "why": "a few words"}}, ...}} using the ids given. Use "covering": [] when there is none to add.

{lists}"""


def choose(client, config, spend, judge: dict, members: list) -> dict:
    """For each member: the features chosen from its own checked list, and the judge's reason.
    Shape traits come first, up to four. A body covering may be added as one more, and
    is kept apart so that it can never push a shape trait out (the owner's ruling)."""
    lists, index = [], {}
    for record in members:
        lines = []
        for i, item in enumerate(record["features"], 1):
            index[(record["name"], f"f{i}")] = item
            lines.append(f"  f{i}. {item['claim']}")
        lists.append(f"{record['name']}:\n" + "\n".join(lines))
    answer = ask(client, config, spend, JUDGE, TASK.format(lists="\n\n".join(lists)), judge)
    chosen = {}
    for record in members:
        reply = answer.get(record["name"])
        reply = reply if isinstance(reply, dict) else {}
        known = lambda ids: list(dict.fromkeys(str(i) for i in ids or [] if (record["name"], str(i)) in index))
        shape = known(reply.get("shape"))[:4]
        covering = [i for i in known(reply.get("covering")) if i not in shape
                    and not PLAIN.search(index[(record["name"], i)]["claim"])][:1]
        shape = [i for i in shape if not PLAIN.search(index[(record["name"], i)]["claim"])] or shape
        chosen[record["name"]] = {
            "must_show": [index[(record["name"], i)] for i in shape + covering],
            "covering": [index[(record["name"], i)]["claim"] for i in covering],
            "why": str(reply.get("why", "")).strip(),
        }
    return chosen


def checked_records() -> dict:
    """group -> the animals in it, each with its checked features."""
    by_group = {}
    for name, group in prehistoric().items():
        record = read_json(OUT / f"{slug(name)}.json")
        if record and not record.get("problem"):
            by_group.setdefault(group, []).append(record)
    return by_group


def judge_all(name: str, cap: float) -> dict:
    config = read_json(CONFIG)
    judge = config["judges"].get(name)
    if not isinstance(judge, dict):
        raise SystemExit(f"No judge '{name}' in config.json.")
    client = openai_client() if judge["provider"] == "openai" else deepseek()
    spend, started = Spend(config, cap, judge["usd_per_million_tokens"]), time.time()
    by_group = checked_records()
    # one group at a time: under a hard cap, calls made together would each set aside
    # their worst case at once, and five small calls take only seconds anyway
    with ThreadPoolExecutor(max_workers=1) as pool:
        results = list(pool.map(lambda members: choose(client, config, spend, judge, members), by_group.values()))
    animals = {animal: choice for result in results for animal, choice in result.items()}
    record = {"judge": name, "model": judge["model"], "date": today(), "seconds": round(time.time() - started),
              "spend": spend.summary(), "animals": animals}
    write_json(OUT / f"tell_apart_{name}.json", record)
    empty = [a for a, c in animals.items() if not c["must_show"]]
    print(f"{name} ({judge['model']}): {sum(len(c['must_show']) for c in animals.values())} traits for "
          f"{len(animals)} animals in {record['seconds']} seconds." + (f"  Nothing chosen for: {', '.join(empty)}" if empty else ""))
    print("  " + spend.line())
    return record


def use(name: str):
    """Write one judge's choice into each animal's result and into prehistoric.json."""
    chosen = read_json(OUT / f"tell_apart_{name}.json")
    if chosen is None:
        raise SystemExit(f"Run the judge first: python tools/research/tell_apart.py --judge {name}")
    whole = read_json(OUT / "prehistoric.json")
    for record in whole["animals"]:
        choice = chosen["animals"].get(record["name"], {"must_show": [], "why": ""})
        record["must_show"], record["told_apart_by"] = choice["must_show"], {
            "judge": name, "model": chosen["model"], "date": chosen["date"], "why": choice["why"]}
        write_json(OUT / f"{slug(record['name'])}.json", record)
    write_json(OUT / "prehistoric.json", whole)
    print(f"The choice of {name} is now in the results.")


def main():
    argv, cap = sys.argv[1:], 0.01
    if "--cap" in argv:   # in US dollars; a hard cap
        cap = float(argv[argv.index("--cap") + 1])
    if "--judge" in argv:
        judge_all(argv[argv.index("--judge") + 1], cap)
    elif "--use" in argv:
        use(argv[argv.index("--use") + 1])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
