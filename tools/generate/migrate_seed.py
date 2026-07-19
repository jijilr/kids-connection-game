"""P1 seed migration: convert the old picture-game data (tag *maps*) into the new
flat-tag Entity format (PRD Part II). Animals domain only — toys / transport / plants
are excluded (they belong to other domains).

Run from the repo root:  python tools/generate/migrate_seed.py
"""
import json
import pathlib

SRC = pathlib.Path("Assets/items_classification.json")
OUT = pathlib.Path("Assets/data/animals/entities.json")

# The "animals" domain = these categories only.
ANIMAL_CATEGORIES = {"dinosaur", "mammal", "bird", "fish", "insect", "reptile"}


def flatten(tags: dict) -> list[str]:
    """map {category:'dinosaur', flies:true, extinct:false}
        -> ['category:dinosaur', 'flies'].
    string value -> 'key:value' (namespaced, so a category value like 'reptile' can't
    collide with a bool trait 'reptile'); bool True -> bare 'key'; bool False -> dropped
    (absence encodes false; boolean dimensions handled by presence later)."""
    out: list[str] = []
    for k, v in tags.items():
        if isinstance(v, bool):
            if v:
                out.append(k)  # bare boolean trait
        elif isinstance(v, str):
            out.append(f"{k}:{v}")  # namespaced valued tag
    seen, res = set(), []
    for t in out:
        if t not in seen:
            seen.add(t)
            res.append(t)
    return res


def add_dino_kind(tags: list[str]) -> None:
    """Materialize a 4-valued 'dino_kind' compound (locomotion x diet) for dinosaurs so
    P1 can demonstrate descent (Animals -> Dinosaurs -> kinds -> back). Derived, not
    invented — provenance stamped 'derived:compound'."""
    if "category:dinosaur" not in tags:
        return
    if "flies" in tags:
        kind = "flyer"
    elif "swims" in tags or "habitat:water" in tags:
        kind = "swimmer"
    elif "diet:carnivore" in tags:
        kind = "land_hunter"
    elif "diet:herbivore" in tags:
        kind = "land_grazer"
    else:
        return
    tags.append(f"dino_kind:{kind}")


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    entities = []
    for it in data["items"]:
        if it["tags"].get("category") not in ANIMAL_CATEGORIES:
            continue
        tags = flatten(it["tags"])
        add_dino_kind(tags)
        prov = {"entity": "human:migrated", "tags": "human:migrated"}
        if any(t.startswith("dino_kind:") for t in tags):
            prov["dino_kind"] = "derived:compound"
        entities.append({
            "id": it["id"],
            "name": it["name"],
            "domain": "animals",
            "tags": tags,
            "facts": [],
            "recognizability": 0.6,  # placeholder; DeepSeek scores properly in P2
            "provenance": prov,
        })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"entities": entities}, indent=2) + "\n", encoding="utf-8")
    cats: dict[str, int] = {}
    for e in entities:
        for t in e["tags"]:
            if t.startswith("category:"):
                c = t.split(":", 1)[1]
                cats[c] = cats.get(c, 0) + 1
    print(f"wrote {len(entities)} entities -> {OUT}")
    print("per category:", dict(sorted(cats.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
