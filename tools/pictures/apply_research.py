"""Put the researched features of prehistoric animals into the picture plan.

For every planned cell whose animal has been researched (tools/pictures/research/*.json)
and curated (research/curated.json), this sets the cell's prompt wording, the features
the stricter check will compare the tile against, the mistakes to avoid, how to tell it
from its look-alikes, the sources, and - only where it changes how the animal looks -
the point the owner should see.

    python tools/pictures/apply_research.py
"""
from piclib import HERE, PLAN, read_json, write_json

RESEARCH = HERE / "research"


def main():
    curated = read_json(RESEARCH / "curated.json")["animals"]
    researched = {}
    for path in sorted(RESEARCH.glob("*.json")):
        if path.name != "curated.json":
            for animal in read_json(path)["animals"]:
                researched[animal["name"]] = dict(animal, file=path.name)

    plan = read_json(PLAN)
    done, waiting = [], set()
    for key, sheet in plan["sheets"].items():
        seen = set()
        for cell in sheet["cells"]:
            name = cell.get("name")
            if name not in curated and name not in researched:
                # the giant snakes are named by the game, not by the cell
                name = {"titanoboa": "Titanoboa", "vasuki_indicus": "Vasuki indicus"}.get(cell["thing"], name)
            if name in researched and name in curated:
                facts, choice = researched[name], curated[name]
                second = cell["thing"] in seen
                seen.add(cell["thing"])
                pose = choice.get("second_view" if second else "pose", "")
                cell["draw"] = choice["draw"] + (f"; {pose}" if pose else "")
                dropped = set(choice.get("drop_features", []))
                cell["features"] = [f for f in facts["features"] if f not in dropped]
                cell["not_this"] = facts["not_this"]
                cell["tell_apart"] = choice.get("tell_apart", facts["tell_apart"])
                cell["disagreement"] = choice["bring_to_owner"]
                cell["sources"] = facts["sources"]
                cell["research_file"] = facts["file"]
                cell.pop("look_closely", None)
                if second:
                    cell["look_closely"] = "a second try; the better of the two is kept"
                done.append(f"{key}: {name}" + (" (second view)" if second else ""))
            elif key.startswith("dinosaurs") or cell["thing"] in ("titanoboa", "vasuki_indicus"):
                waiting.add(name or cell["thing"])
    write_json(PLAN, plan)
    print(f"{len(done)} cells now carry researched features.")
    if waiting:
        print(f"Still waiting for research: {', '.join(sorted(waiting))}")


if __name__ == "__main__":
    main()
