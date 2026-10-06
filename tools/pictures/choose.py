"""When a thing was drawn more than once, ask the vision model which tile is better.

The ordinary check only says what a tile shows, so two good tiles of one thing tie.
This shows the model all the waiting tiles of one thing, side by side as the game will
show them, and asks which one a small child would recognise most easily. The answer
and its reason are recorded on every candidate.

    python tools/pictures/choose.py THING_ID...            say which is better
    python tools/pictures/choose.py THING_ID... --apply    and approve it, setting the others aside

--apply follows the owner's ruling of 6 Oct 2026: "for second tries, take the one the
check rates better." Nothing is deleted; the tiles not chosen are set aside.
"""
import base64
import json
import os
import sys

from piclib import PLAN, RECORDS, ROOT, load_records, read_json, thing_names, today, write_json


def ask(client, model: str, name: str, pictures: list, hint: str) -> tuple:
    question = (
        f"These {len(pictures)} pictures, in order, are candidate tiles for the same thing, "
        f"\"{name}\", in a sorting game for a four-year-old. Which ONE shows it most clearly and "
        "most typically, so that a small child would recognise it at a glance? "
        + (f"Keep in mind: {hint}. " if hint else "")
        + 'Reply with JSON only: {"best": 1, "why": "one short sentence"}'
    )
    content = [{"type": "text", "text": question}]
    content += [{"type": "image_url",
                 "image_url": {"url": "data:image/webp;base64," + base64.b64encode(p).decode()}}
                for p in pictures]
    reply = client.chat.completions.create(
        model=model, response_format={"type": "json_object"},
        messages=[{"role": "user", "content": content}],
    )
    return json.loads(reply.choices[0].message.content), reply.usage


def main():
    things = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    if not things:
        raise SystemExit(__doc__)
    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is not set in the environment.")
    from openai import OpenAI

    records, names = load_records(), thing_names()
    check = read_json(PLAN)["vision_check"]
    client, spent = OpenAI(), 0.0
    for thing in things:
        tiles = {k: t for k, t in records["tiles"].items()
                 if t["expected_thing"] == thing and t["review"] == "waiting for the owner"
                 and t["cut"]["ok"] and t["vision"] and t["vision"]["shows"] == thing}
        if len(tiles) < 2:
            print(f"  {names.get(thing, thing)}: fewer than two waiting tiles that passed the check; nothing to choose")
            continue
        ids = list(tiles)
        hint = "; ".join(dict.fromkeys(t["look_closely"] for t in tiles.values() if t.get("look_closely")))
        answer, usage = ask(client, check["model"], names.get(thing, thing),
                            [(ROOT / t["app_file"]).read_bytes() for t in tiles.values()], hint)
        cost = 0.0
        if usage is not None:
            cost = (usage.prompt_tokens * check["usd_per_million_input_tokens"]
                    + usage.completion_tokens * check["usd_per_million_output_tokens"]) / 1_000_000
        spent += cost
        best = answer.get("best")
        if not isinstance(best, int) or not 1 <= best <= len(ids):
            print(f"  {names.get(thing, thing)}: the model did not choose ({answer}); left for the owner")
            continue
        chosen, why = ids[best - 1], str(answer.get("why", "")).strip()
        for tile_id, tile in tiles.items():
            tile["comparison"] = {"model": check["model"], "date": today(), "among": ids,
                                  "chosen": tile_id == chosen, "why": why, "cost_usd": round(cost, 5)}
            if not apply:
                continue
            if tile_id == chosen:
                tile.update(thing_id=thing, review="approved", reviewed_on=today(),
                            review_note=f"chosen over {', '.join(i for i in ids if i != chosen)} by the "
                                        f"check, under the owner's ruling of 2026-10-06: {why}")
            else:
                tile.update(thing_id=None, review="set aside", reviewed_on=today(),
                            review_note=f"a second try; the check rated {chosen} better: {why}")
        print(f"  {names.get(thing, thing)}: {chosen} is better than "
              f"{', '.join(i for i in ids if i != chosen)}. {why}"
              + ("  [approved; the rest set aside]" if apply else ""))
    write_json(RECORDS, records)
    print(f"The comparisons cost ${spent:.5f}.")


if __name__ == "__main__":
    main()
