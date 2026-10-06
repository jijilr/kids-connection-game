"""The stricter check for prehistoric animals: does the tile show what the sources say?

The owner cannot review every prehistoric animal himself. So each one carries, in
plan.json, what was written from museum and encyclopedia descriptions (with the
sources): the few traits that tell it from its look-alikes (`must_show`), the mistakes
to avoid (`not_this`), and a longer list of features. This asks a stronger vision model
to compare the full-resolution master against all three.

By the owner's ruling of 6 Oct 2026, a tile FAILS only when
  - it is not the animal intended, or
  - a trait that tells it from its look-alikes is not clearly shown, or
  - one of the listed mistakes appears, or
  - it did not cut cleanly.
The other features are compared too, and any the picture contradicts are REPORTED on
the tile's record, but they do not fail it: many are too fine to see in the game.

A passing tile is approved under the owner's standing rule. A tile that fails, or whose
sources disagree about how the animal looks, is left for the owner, with the reasons.

The vision model does not always judge a fine point the same way twice. So, by the
owner's ruling of 6 Oct 2026:
  - a tile that is already approved (or set aside, or rejected) is never checked again;
  - a BORDERLINE failure, where the tile is the right animal and fails on one point
    only, is checked a second time, and the tile fails only if both runs fail.

    python tools/pictures/check_features.py SHEET_ID
"""
import base64
import json
import os
import sys

from piclib import PLAN, RECORDS, ROOT, load_records, original, read_json, today, write_json

RULE = "approved under the owner's standing rule of 2026-10-06: it passed the feature check against the cited sources"
CHECK_RULE = ("v3: fails only on must_show and listed mistakes; other features are reported; "
              "a one-point failure is checked twice and fails only if both runs fail")


def ask(client, model: str, picture: bytes, name: str, cell: dict) -> tuple:
    lines = [
        f"This picture is meant to be a scientifically accurate life reconstruction of {name}, "
        "for a children's game. Compare it with the three lists below, which were written from "
        "museum and encyclopedia sources. Judge only what you can see.",
        "",
        "A. What tells it from its look-alikes. Each of these should be clearly shown:",
    ]
    lines += [f"A{i}. {trait}" for i, trait in enumerate(cell["must_show"], 1)]
    lines += ["", "B. Mistakes it must NOT show:"]
    lines += [f"B{i}. {mistake}" for i, mistake in enumerate(cell.get("not_this", []), 1)]
    lines += ["", "C. Other features, in finer detail:"]
    lines += [f"C{i}. {feature}" for i, feature in enumerate(cell["features"], 1)]
    lines += [
        "",
        "For every A item and every C item answer \"yes\" (clearly shown), \"no\" (the picture "
        "contradicts it) or \"unclear\" (cannot be judged from this view).",
        "For B, give the numbers of the listed mistakes the picture really shows; an empty list if none. "
        "Do not add mistakes that are not on list B.",
        "Reply with JSON only: {\"is_this_animal\": true, \"must_show\": [\"yes\", ...], "
        "\"mistakes_shown\": [2], \"features\": [\"yes\", \"no\", ...], \"comment\": \"one sentence\"}",
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


def judge(cell: dict, answer: dict, cut_ok: bool, cut_flags: list) -> tuple:
    """(reasons it fails, features reported but not failing, the raw verdicts)."""
    shown = [str(v).lower() for v in answer.get("must_show", [])]
    verdicts = [str(v).lower() for v in answer.get("features", [])]
    listed = cell.get("not_this", [])
    numbers = [n for n in answer.get("mistakes_shown", []) if isinstance(n, int) and 1 <= n <= len(listed)]
    reasons = []
    if answer.get("is_this_animal") is not True:
        reasons.append("the checker does not think it is this animal")
    if len(shown) != len(cell["must_show"]) or len(verdicts) != len(cell["features"]):
        reasons.append("the checker did not answer every item")
    reasons += [f"does not show what tells it apart: {trait}"
                for trait, v in zip(cell["must_show"], shown) if v == "no"]
    reasons += [f"what tells it apart cannot be seen: {trait}"
                for trait, v in zip(cell["must_show"], shown) if v not in ("yes", "no")]
    reasons += [f"shows a listed mistake: {listed[n - 1]}" for n in numbers]
    if not cut_ok:
        reasons.append("it did not cut cleanly: " + "; ".join(cut_flags))
    reported = [f for f, v in zip(cell["features"], verdicts) if v == "no"]
    return reasons, reported, {"must_show": shown, "features": verdicts, "mistakes_shown": numbers}


def borderline(reasons: list) -> bool:
    """One point only, and not a doubt about which animal it is or about the cut."""
    return len(reasons) == 1 and reasons[0].startswith(
        ("does not show what tells it apart", "what tells it apart cannot be seen", "shows a listed mistake"))


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
    passed, for_owner, noted = [], [], []
    for tile_id, tile in records["tiles"].items():
        if tile["sheet_id"] != sheet_id:
            continue
        cell = cells[tile["cell"] - 1]
        if not cell.get("features"):
            continue  # not a prehistoric animal: the ordinary check and the owner's review apply
        if not cell.get("must_show"):
            raise SystemExit(f"{cell.get('name') or cell['thing']} has no `must_show`. Write what tells it "
                             "from its look-alikes in research/curated.json, then run apply_research.py.")
        name = sheet["names"][tile["expected_thing"]]
        if tile["review"] != "waiting for the owner":
            print(f"  {tile_id} {name}: not checked again ({tile['review']})")
            continue
        picture = original(ROOT / tile["master_file"]).read_bytes()

        def once():
            nonlocal spent
            answer, usage = ask(client, check["model"], picture, name, cell)
            if usage is not None:
                spent += (usage.prompt_tokens * check["usd_per_million_input_tokens"]
                          + usage.completion_tokens * check["usd_per_million_output_tokens"]) / 1_000_000
            return answer, judge(cell, answer, tile["cut"]["ok"], tile["cut"]["flags"])

        answer, (reasons, reported, verdicts) = once()
        runs = [{"passed": not reasons, "reasons": reasons}]
        if borderline(reasons):
            again, (reasons2, reported2, verdicts2) = once()
            runs.append({"passed": not reasons2, "reasons": reasons2})
            if not reasons2:   # failed once and passed once: it passes
                answer, reasons, reported, verdicts = again, reasons2, reported2, verdicts2
            else:
                reasons = list(dict.fromkeys(reasons + reasons2))
        disagreement = cell.get("disagreement", "")
        if tile.get("feature_check"):
            tile.setdefault("earlier_feature_checks", []).append(tile["feature_check"])
        tile["feature_check"] = {
            "model": check["model"], "date": today(), "rule": CHECK_RULE, **verdicts,
            "comment": str(answer.get("comment", "")).strip(), "sources": cell.get("sources", []),
            "passed": not reasons, "reasons": reasons, "reported": reported,
            "sources_disagree": disagreement, "runs": runs,
        }
        if not reasons and not disagreement and tile["review"] == "waiting for the owner":
            tile.update(thing_id=tile["expected_thing"], review="approved", review_note=RULE,
                        reviewed_on=today())
        if reasons or disagreement:
            for_owner.append((tile_id, name, reasons, disagreement))
        else:
            passed.append(name)
        if reported:
            noted.append((tile_id, name, reported))
        state = "FAILS" if reasons else ("SOURCES DISAGREE" if disagreement else "PASS")
        if len(runs) == 2:
            state += " (borderline: checked twice, " + ("failed both" if reasons else "passed the second time") + ")"
        print(f"  {tile_id} {name}: {state}  (tells apart: {verdicts['must_show'].count('yes')} of "
              f"{len(cell['must_show'])}; listed mistakes: {len(verdicts['mistakes_shown'])}; "
              f"finer features contradicted: {len(reported)})  {tile['feature_check']['comment']}")
    sheet["feature_check_cost_usd"] = round(sheet.get("feature_check_cost_usd", 0) + spent, 5)
    write_json(RECORDS, records)
    print(f"\nPassed: {', '.join(passed) or 'none'}")
    for tile_id, name, reasons, disagreement in for_owner:
        print(f"For the owner ({'FAILED' if reasons else 'sources disagree'}) - {tile_id} {name}:")
        for reason in reasons:
            print(f"    - {reason}")
        if disagreement:
            print(f"    - the sources disagree: {disagreement}")
    for tile_id, name, reported in noted:
        print(f"Reported, not failing - {tile_id} {name}:")
        for feature in reported:
            print(f"    - contradicts: {feature}")
    print(f"The check itself cost ${spent:.4f}.")


if __name__ == "__main__":
    main()
