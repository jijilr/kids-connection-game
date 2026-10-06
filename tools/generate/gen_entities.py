"""P2 — DeepSeek content generator (dev-time). Produces well-known, richly-tagged
animals in the Entity format, using a CONTROLLED vocabulary (only the allowed values,
so lazily-added tags always compose — PRD VI.0). Provenance = 'deepseek:generated'
(verify.py promotes to '+verified').

Reads DEEPSEEK_API_KEY from the environment. Never commits the key.
  python tools/generate/gen_entities.py
"""
import json
import os
import pathlib
import re

from openai import OpenAI

OUT = pathlib.Path("tools/generate/_generated_raw.json")

CATEGORIES = {
    "mammal": 12, "bird": 10, "fish": 10, "insect": 8,
    "reptile": 8, "amphibian": 6, "dinosaur": 16,
}
ALLOWED = {
    "category": list(CATEGORIES),
    "diet": ["carnivore", "herbivore", "omnivore"],
    "habitat": ["land", "water"],
    "size": ["tiny", "small", "big", "huge"],
}

SYSTEM = (
    "You generate accurate zoology data for a children's classification game. "
    "Every fact and tag must be TRUE — a wrong tag teaches a child a falsehood. "
    "Use ONLY the allowed values. Output ONLY a single JSON object."
)


def prompt() -> str:
    lines = ["Produce well-known, kid-recognizable animals, exactly this many per category:"]
    for c, n in CATEGORIES.items():
        lines.append(f"  - {c}: {n}")
    lines += [
        "",
        "Each animal is a JSON object with keys:",
        f"  name (string), category (one of {ALLOWED['category']}),",
        f"  diet (one of {ALLOWED['diet']} or null),",
        f"  habitat (one of {ALLOWED['habitat']}),",
        f"  size (one of {ALLOWED['size']}),",
        "  flies (boolean), swims (boolean),",
        "  recognizability (0.0-1.0, how well an 8-year-old knows it),",
        "  fact (ONE short, TRUE, kid-friendly sentence).",
        "For dinosaurs, spread across: pterosaur flyers, marine-reptile swimmers,",
        "land carnivores, land herbivores (at least 4 of each).",
        'Return exactly: {"animals": [ ... ]}',
    ]
    return "\n".join(lines)


def nice_name(name: str) -> str:
    """Kid-facing display name: 'dog' -> 'Dog', 'komodo dragon' -> 'Komodo Dragon'.
    Names that already start with a capital (e.g. 'Tyrannosaurus rex') are kept."""
    name = name.strip()
    return name if name[:1].isupper() else " ".join(w[:1].upper() + w[1:] for w in name.split())


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def to_entity(a: dict) -> dict | None:
    try:
        cat = a["category"]
        if cat not in ALLOWED["category"]:
            return None
        tags = [f"category:{cat}", f"size:{a['size']}", f"habitat:{a['habitat']}"]
        if a.get("diet") in ALLOWED["diet"]:
            tags.append(f"diet:{a['diet']}")
        if a.get("flies"):
            tags.append("flies")
        if a.get("swims"):
            tags.append("swims")
        if cat == "dinosaur":
            if a.get("flies"):
                k = "flyer"
            elif a.get("swims") or a.get("habitat") == "water":
                k = "swimmer"
            elif a.get("diet") == "carnivore":
                k = "land_hunter"
            elif a.get("diet") == "herbivore":
                k = "land_grazer"
            else:
                k = None
            if k:
                tags.append(f"dino_kind:{k}")
        return {
            "id": slug(a["name"]),
            "name": nice_name(a["name"]),
            "domain": "animals",
            "tags": tags,
            "facts": [a["fact"]] if a.get("fact") else [],
            "recognizability": float(a.get("recognizability", 0.5)),
            "provenance": {"entity": "deepseek:generated", "tags": "deepseek:generated"},
        }
    except (KeyError, TypeError, ValueError):
        return None


def main() -> None:
    client = OpenAI(api_key=os.environ["DEEPSEEK_API_KEY"],
                    base_url="https://api.deepseek.com")
    resp = client.chat.completions.create(
        model="deepseek-chat",
        messages=[{"role": "system", "content": SYSTEM},
                  {"role": "user", "content": prompt()}],
        response_format={"type": "json_object"},
        temperature=0.3,
        max_tokens=8000,
    )
    content = resp.choices[0].message.content
    try:
        animals = json.loads(content)["animals"]
    except (json.JSONDecodeError, KeyError) as e:
        print("Bad JSON from model:", e)
        print(content[:500])
        raise SystemExit(1)

    entities, seen = [], set()
    for a in animals:
        e = to_entity(a)
        if e and e["id"] not in seen:
            seen.add(e["id"])
            entities.append(e)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"entities": entities}, indent=2) + "\n", encoding="utf-8")

    cats: dict[str, int] = {}
    for e in entities:
        for t in e["tags"]:
            if t.startswith("category:"):
                cats[t.split(":", 1)[1]] = cats.get(t.split(":", 1)[1], 0) + 1
    print(f"generated {len(entities)} entities -> {OUT}")
    print("per category:", dict(sorted(cats.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
