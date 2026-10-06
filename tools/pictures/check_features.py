"""The stricter check for prehistoric animals: does the tile show what the sources say?

The owner cannot review every prehistoric animal himself. So each one carries, in
plan.json, a list of identifying features written from museum and encyclopedia
descriptions (with the sources), the mistakes to avoid, and how to tell it from its
look-alikes. This asks a stronger vision model to compare the full-resolution master
against that list, feature by feature.

A tile PASSES when every feature is seen or cannot be judged from the picture, none is
contradicted, none of the listed mistakes appears, and the animal is the one intended.
A passing tile is approved under the owner's standing rule of 6 Oct 2026. A tile that
fails, or whose sources disagree about its appearance, is left for the owner, with the
reasons. Nothing is linked to a thing in any other way.

    python tools/pictures/check_features.py SHEET_ID
"""
import base64
import json
import os
import sys

from piclib import PLAN, RECORDS, ROOT, load_records, read_json, today, write_json

RULE = "approved under the owner's standing rule of 2026-10-06: it passed the feature check against the cited sources"


def ask(client, model: str, picture: bytes, name: str, cell: dict) -> tuple:
    lines = [
        f"This picture is meant to be a scientifically accurate life reconstruction of {name}, "
        "for a children's game. Compare it with the description below, which was written from "
        "museum and encyclopedia sources. Judge only what you can see.",
        "",
        "Features it should show:",
    ]
    lines += [f"{i}. {feature}" for i, feature in enumerate(cell["features"], 1)]
    lines += ["", "Mistakes it must NOT show:"]
    lines += [f"- {mistake}" for mistake in cell.get("not_this", [])]
    if cell.get("tell_apart"):
        lines += ["", f"How it differs from its look-alikes: {cell['tell_apart']}"]
    lines += [
        "",
        "For each numbered feature answer \"yes\" (clearly shown), \"no\" (the picture contradicts it) "
        "or \"unclear\" (cannot be judged from this view).",
        "Reply with JSON only: {\"is_this_animal\": true, \"features\": [\"yes\", \"no\", ...], "
        "\"mistakes_shown\": [\"...\"], \"comment\": \"one sentence\"}",
    ]
    reply = client.chat.completions.create(
        model=model,
        response_format={"type": "json_object"},
        messages=[{"role": "user", "content": [
            {"type": "text", "text": "\n".join(lines)},
            {"type": "image_url",
             "image_url": {"url": "data:image/png;base64," + base64.b64encode(picture).decode()}},
        ]}],
    )
    return json.loads(reply.choices[0].message.content), reply.usage


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check_features.py SHEET_ID")
    sheet_id = sys.argv[1]
    records = load_records()
    sheet = records["sheets"].get(sheet_id)
    if sheet is None:
        raise SystemExit(f"No sheet '{sheet_id}'.")
    plan = read_json(PLAN)
    check = plan["feature_check"]
    cells = plan["sheets"][sheet["plan_key"]]["cells"]
    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is not set in the environment.")
    from openai import OpenAI

    client, spent = OpenAI(), 0.0
    passed, for_owner = [], []
    for tile_id, tile in records["tiles"].items():
        if tile["sheet_id"] != sheet_id:
            continue
        cell = cells[tile["cell"] - 1]
        if not cell.get("features"):
            continue  # not a prehistoric animal: the ordinary check and the owner's review apply
        name = sheet["names"][tile["expected_thing"]]
        answer, usage = ask(client, check["model"], (ROOT / tile["master_file"]).read_bytes(), name, cell)
        if usage is not None:
            spent += (usage.prompt_tokens * check["usd_per_million_input_tokens"]
                      + usage.completion_tokens * check["usd_per_million_output_tokens"]) / 1_000_000
        verdicts = [str(v).lower() for v in answer.get("features", [])]
        contradicted = [cell["features"][i] for i, v in enumerate(verdicts)
                        if v == "no" and i < len(cell["features"])]
        mistakes = [m for m in answer.get("mistakes_shown", []) if str(m).strip()]
        reasons = []
        if answer.get("is_this_animal") is not True:
            reasons.append("the checker does not think it is this animal")
        if len(verdicts) != len(cell["features"]):
            reasons.append("the checker did not answer every feature")
        reasons += [f"contradicts: {f}" for f in contradicted]
        reasons += [f"shows a known mistake: {m}" for m in mistakes]
        if not tile["cut"]["ok"]:
            reasons.append("it did not cut cleanly: " + "; ".join(tile["cut"]["flags"]))
        if cell.get("disagreement"):
            reasons.append("the sources disagree: " + cell["disagreement"])
        tile["feature_check"] = {
            "model": check["model"], "date": today(), "verdicts": verdicts,
            "mistakes_shown": mistakes, "comment": str(answer.get("comment", "")).strip(),
            "sources": cell.get("sources", []), "passed": not reasons, "reasons": reasons,
        }
        only_disagreement = reasons and all(r.startswith("the sources disagree") for r in reasons)
        if not reasons and tile["review"] == "waiting for the owner":
            tile.update(thing_id=tile["expected_thing"], review="approved", review_note=RULE,
                        reviewed_on=today())
            passed.append(name)
        elif reasons:
            for_owner.append((tile_id, name, reasons, only_disagreement))
        unclear = verdicts.count("unclear")
        print(f"  {tile_id} {name}: {'PASS' if not reasons else 'FOR THE OWNER'}"
              f"  ({verdicts.count('yes')} yes, {unclear} unclear, {verdicts.count('no')} no)"
              f"  {tile['feature_check']['comment']}")
    sheet["feature_check_cost_usd"] = round(spent, 5)
    write_json(RECORDS, records)
    print(f"\nPassed and approved under the owner's rule: {', '.join(passed) or 'none'}")
    for tile_id, name, reasons, only_disagreement in for_owner:
        kind = "sources disagree" if only_disagreement else "FAILED"
        print(f"For the owner ({kind}) - {tile_id} {name}:")
        for reason in reasons:
            print(f"    - {reason}")
    print(f"The check itself cost ${spent:.4f}.")


if __name__ == "__main__":
    main()
