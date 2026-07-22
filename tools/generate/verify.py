"""P2 — the QA gate. An INDEPENDENT DeepSeek pass over the generated entities that flags
factually-wrong tags for a child (spider tagged insect, penguin tagged flies, whale tagged
fish...). Wrong tags are stripped; entities with a wrong *category* are dropped. Survivors
are promoted to provenance 'deepseek:generated+verified' and written as the live
entities.json. This two-pass generate->verify is the discipline that keeps the corpus
trustworthy (PRD VI.0).

  python tools/generate/verify.py
"""
import json
import os
import pathlib

from openai import OpenAI

RAW = pathlib.Path("tools/generate/_generated_raw.json")
OUT = pathlib.Path("Assets/data/animals/entities.json")

SYSTEM = (
    "You are a fact-checker for a children's animal game. The game uses a kid-friendly FOLK "
    "grouping where 'category:dinosaur' is an umbrella for big prehistoric reptiles — so "
    "pterosaurs (Pteranodon, Pterodactylus, Quetzalcoatlus, Rhamphorhynchus) and marine reptiles "
    "(Mosasaurus, Plesiosaurus, Ichthyosaurus, Elasmosaurus) tagged 'category:dinosaur' are an "
    "INTENTIONAL folk choice — do NOT flag them. But DO flag genuinely wrong tags for MODERN "
    "animals (a whale or dolphin tagged 'category:fish', a bat tagged 'category:bird', a spider "
    "tagged 'category:insect', a penguin tagged 'flies', a clearly wrong diet) and any other clear "
    "falsehood. Do not nitpick size/habitat edge cases. Output ONLY JSON."
)


def main() -> None:
    ents = json.loads(RAW.read_text(encoding="utf-8"))["entities"]
    payload = [{"id": e["id"], "name": e["name"], "tags": e["tags"]} for e in ents]
    user = (
        'Check these animals. Return {"issues": {"<id>": {"wrong_tags": ["<tag>", ...], '
        '"note": "<why>"}}} including ONLY ids that have at least one wrong tag.\n\n'
        + json.dumps(payload)
    )
    client = OpenAI(api_key=os.environ["DEEPSEEK_API_KEY"],
                    base_url="https://api.deepseek.com")
    resp = client.chat.completions.create(
        model="deepseek-chat",
        messages=[{"role": "system", "content": SYSTEM},
                  {"role": "user", "content": user}],
        response_format={"type": "json_object"},
        temperature=0,
        max_tokens=4000,
    )
    issues = json.loads(resp.choices[0].message.content).get("issues", {})

    verified, dropped, fixed = [], [], []
    for e in ents:
        iss = issues.get(e["id"])
        if iss and iss.get("wrong_tags"):
            wrong = set(iss["wrong_tags"])
            if any(t.startswith("category:") for t in wrong):
                dropped.append((e["name"], iss.get("note", "")))
                continue
            e["tags"] = [t for t in e["tags"] if t not in wrong]
            fixed.append((e["name"], sorted(wrong), iss.get("note", "")))
        e["provenance"] = {
            "entity": "deepseek:generated+verified",
            "tags": "deepseek:generated+verified",
        }
        verified.append(e)

    OUT.write_text(json.dumps({"entities": verified}, indent=2) + "\n", encoding="utf-8")
    print(f"verified {len(verified)} entities  (dropped {len(dropped)}, fixed {len(fixed)}) -> {OUT}")
    for name, tags, note in fixed:
        print(f"  fixed  {name}: removed {tags}  ({note})")
    for name, note in dropped:
        print(f"  DROPPED {name}: {note}")


if __name__ == "__main__":
    main()
