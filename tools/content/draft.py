"""Step 1 of 3 - draft things for the circles nearest the seed.

For each group in PLAN, DeepSeek is asked for familiar things. The group's own
field (kind_of_thing / kind_of_animal) is set here, not by the model. The model
supplies the names, how familiar each one is, and any other field the dictionary
expects on that group. Nothing in the draft is trusted until check.py passes it.

    python tools/content/draft.py PLAN_NAME
"""
import sys

from lib import (DICTIONARY, DRAFT, THINGS, allowed_values, applies, ask_json, deepseek, read_json,
                 write_json)

PLANS = {}

# Nearest the seed first: the three non-animal seed groups, then the animals circle.
# Dinosaurs are not drafted here - they come from the owner's list (owner_list.py).
PLANS["seed_and_animals"] = [
    {"fields": {"kind_of_thing": "plant"}, "count": 10,
     "ask": "plants: trees, flowers, crops and grasses",
     "avoid": "mushrooms and other fungi, seaweed, and foods that are only a product of a plant"},
    {"fields": {"kind_of_thing": "nature_not_alive"}, "count": 10,
     "ask": "things found in nature that are not alive and were not made by people, such as the Sun, a river or a rock",
     "avoid": "anything alive or once alive (wood, shells, coral, fossils), anything people make, and fire"},
    {"fields": {"kind_of_thing": "made_by_people"}, "count": 12,
     "ask": "things people make: vehicles, tools, household objects, buildings and toys",
     "avoid": "food, brand names, and anything that also occurs in nature"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "mammal"}, "count": 12,
     "ask": "mammals that are alive today", "avoid": "anything a child might take for a fish or a bird unless it is very well known"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "bird"}, "count": 10,
     "ask": "birds that are alive today", "avoid": "bats and flying insects"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "fish"}, "count": 8,
     "ask": "fish that are alive today", "avoid": "whales, dolphins, starfish, jellyfish, octopus, crabs and prawns"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "insect"}, "count": 8,
     "ask": "insects that are alive today", "avoid": "spiders, scorpions, centipedes, worms and snails"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "reptile"}, "count": 8,
     "ask": "reptiles that are alive today", "avoid": "frogs, salamanders and dinosaurs"},
    {"fields": {"kind_of_thing": "animal", "kind_of_animal": "amphibian"}, "count": 6,
     "ask": "amphibians that are alive today", "avoid": "lizards, turtles and snakes"},
]

# 6 Oct 2026: the groups still short of four after the owner approved kind_of_made_thing
# and kind_of_nature. One or two spares are asked for in each. (The new plants are the
# owner's own list, in owner_list.py.)
PLANS["made_and_nature"] = [
    {"fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "toy"}, "count": 2,
     "ask": "toys a small child plays with",
     "avoid": "vehicles, tools, food, brand names, and anything with a screen"},
    {"fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "household"}, "count": 2,
     "ask": "things found in a house: furniture and kitchen things",
     "avoid": "toys, tools, vehicles, food, and electrical gadgets"},
    {"fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "tool"}, "count": 4,
     "ask": "hand tools used for fixing, cutting or digging",
     "avoid": "kitchen things, toys, and machines with engines"},
    {"fields": {"kind_of_thing": "nature_not_alive", "kind_of_nature": "water"}, "count": 4,
     "ask": "bodies of water found in nature, such as a sea or a lake",
     "avoid": "rain, ice, snow, drinks, and anything made by people such as a tap, a well or a swimming pool"},
    {"fields": {"kind_of_thing": "nature_not_alive", "kind_of_nature": "land"}, "count": 4,
     "ask": "places and landforms found in nature, such as a hill or a desert",
     "avoid": "anything made by people, forests and other living things, and anything in the sky"},
    {"fields": {"kind_of_thing": "nature_not_alive", "kind_of_nature": "ground"}, "count": 3,
     "ask": "natural materials the ground is made of, such as soil or clay",
     "avoid": "anything made by people, anything once alive such as wood or coal, and metals a child would not know"},
]

# "Places on land" was still one short after made_and_nature.
PLANS["land_top_up"] = [
    {"fields": {"kind_of_thing": "nature_not_alive", "kind_of_nature": "land"}, "count": 3,
     "ask": "places and landforms found in nature, such as a hill or a volcano",
     "avoid": "rivers, lakes and other water, anything made by people, forests and other living things"},
]

# Tiles are drawn with emoji until proper pictures exist, and a board must use one style
# throughout. Only two toys had an emoji, so the made-things board could not be drawn.
PLANS["toys_top_up"] = [
    {"fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "toy"}, "count": 3,
     "ask": "toys a small child plays with, choosing ones that have a common emoji, such as a kite or a balloon",
     "avoid": "vehicles, tools, food, brand names, and anything with a screen"},
]

SYSTEM = (
    "You draft content for a sorting game played by a four-year-old who lives in India. "
    "He cannot read yet; he recognises things from daily life and from picture books. "
    "Every statement must be true in the everyday sense a careful parent would use. "
    "A wrong fact teaches a child a falsehood, so leave out anything borderline. "
    "Reply with a single JSON object and nothing else."
)


def extra_fields(dictionary: dict, fields: dict) -> dict:
    """Fields the dictionary expects on this group that the plan has not already set."""
    out = {}
    for name, definition in dictionary["fields"].items():
        if name in fields:
            continue
        if definition.get("meaning") == "academic":
            continue  # looked up in a reference, never guessed by the drafting model
        if applies(definition["expected_on"], fields):
            out[name] = definition
    return out


def already_have(things: dict, fields: dict) -> list:
    """Names already in the data for this group, so the draft does not repeat them."""
    return [t["name"] for t in things.values()
            if all(t["fields"].get(name) == value for name, value in fields.items())]


def prompt(group: dict, extras: dict, have: list) -> str:
    lines = [
        f"List {group['count']} {group['ask']}.",
        "Choose single, specific things a four-year-old would recognise, most familiar first.",
        f"Do not include: {group['avoid']}.",
    ]
    if have:
        lines.append(f"We already have these, so do not repeat them: {', '.join(have)}.")
    lines += [
        "Use the name a child would say (for example 'Mango tree', not 'Trees').",
        "",
        "For each thing give:",
        "  name     - string",
        "  familiar - 0.0 to 1.0, how sure you are a four-year-old in India would recognise it",
    ]
    for name, definition in extras.items():
        values = ", ".join(str(v).lower() for v in allowed_values(definition))
        lines.append(f"  {name} - one of: {values}  ({definition['wording']})")
    lines += [
        "  unsure   - empty string, or one sentence if anything about this thing is debatable",
        "",
        'Return exactly: {"things": [ ... ]}',
    ]
    return "\n".join(lines)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in PLANS:
        raise SystemExit(f"Say which plan to draft: {', '.join(PLANS)}")
    dictionary = read_json(DICTIONARY)
    things = (read_json(THINGS, {}) or {}).get("things", {})
    client = deepseek()
    drafted = []
    for group in PLANS[sys.argv[1]]:
        extras = extra_fields(dictionary, group["fields"])
        have = already_have(things, group["fields"])
        reply = ask_json(client, SYSTEM, prompt(group, extras, have), temperature=0.3)
        for item in reply.get("things", []):
            fields = dict(group["fields"])
            for name in extras:
                if name in item and item[name] is not None:
                    fields[name] = item[name]
            drafted.append({
                "name": str(item["name"]).strip(),
                "fields": fields,
                "familiar": float(item.get("familiar", 0)),
                "unsure": str(item.get("unsure") or "").strip(),
            })
        print(f"  {group['fields']}: {len(reply.get('things', []))} drafted")
    write_json(DRAFT, {"plan": sys.argv[1], "dictionary_version": dictionary["version"],
                       "things": drafted})
    print(f"Drafted {len(drafted)} things -> {DRAFT.name}. Next: python tools/content/check.py")


if __name__ == "__main__":
    main()
