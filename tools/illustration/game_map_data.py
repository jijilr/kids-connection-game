"""What the game holds, laid out as a map: the seed, the four kinds of thing, and the circles
inside each. For every circle: how many things it holds, whether a child can open a board
there, and a tile from each of four of its groups. It reads the game's own data, asks the
board maker what can open (tools/content/boards.py, the same rules as the game), and writes
game_map.json for the Blender script beside it. It costs nothing and changes nothing else.

    python tools/illustration/game_map_data.py
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/content"))
import boards  # noqa: E402

OUT = pathlib.Path(__file__).with_name("game_map.json")
DEPTH = 2       # the seed, the kinds of thing, and the circles inside each kind


# The thing that stands for its group in the picture, where the group holds one of these;
# otherwise the thing a child is most likely to know.
FACES = """dog cow elephant whale crow parrot hen penguin goldfish butterfly house_lizard frog
tyrannosaurus_rex brachiosaurus mosasaurus pterodactylus mango_tree rose rice_plant tomato_plant
carrot_plant coriander_plant pea_plant sun rock mountain sea car chair house ball train boat
aeroplane teddy_bear building_blocks kite toy_drum cup bucket fan hammer temple shop bridge
airport""".split()


def best(things: dict, keys: list) -> str:
    known = [face for face in FACES if face in keys]
    return known[0] if known else min(keys, key=lambda k: (-things[k].get("familiar", 0), k))


def walk(dictionary, things, path, node_id, label, level, parent, nodes):
    keys = boards.members(things, path)
    field = boards.sub_kind(dictionary, things, keys, path, path[-1][0] if path else None)
    groups = boards.split(things, keys, field) if field else {}
    opens = boards.make_board(dictionary, things, path) is not None
    values = dictionary["fields"][field]["values"] if field else {}
    full = [v for v in values if len(groups.get(v, [])) >= boards.PER_GROUP][:boards.GROUPS]
    shown = [best(things, groups[v]) for v in full] if opens else [best(things, keys)] if keys else []
    nodes.append({
        "id": node_id, "label": label, "level": level, "parent": parent, "open": opens, "things": len(keys),
        "tiles": [f"Assets/pictures/{key}.webp" for key in shown],
        "groups": [values[v] for v in full] if opens else [],
        "question": dictionary["fields"][field]["wording"] if opens else None,
    })
    if level < DEPTH and field:
        for value, name in values.items():
            if groups.get(value):
                child = value if node_id == "seed" else f"{node_id}/{value}"
                walk(dictionary, things, path + [(field, value)], child, name, level + 1, node_id, nodes)


def main():
    dictionary = json.loads((ROOT / "Assets/data/dictionary.json").read_text(encoding="utf-8"))
    things = json.loads((ROOT / "Assets/data/things.json").read_text(encoding="utf-8"))["things"]
    nodes = []
    walk(dictionary, things, [], "seed", "Everything", 0, None, nodes)
    missing = [t for n in nodes for t in n["tiles"] if not (ROOT / t).exists()]
    if missing:
        sys.exit("no picture for: " + ", ".join(missing))
    data = {"things": len(things), "boards": sum(n["open"] for n in nodes), "nodes": nodes}
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(things)} things, {data['boards']} boards a child can open, {len(nodes)} circles -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
