"""Ask a vision model what each tile shows, before any tile is linked to a thing.

The image model may swap cells, repeat a subject or draw the wrong one. For every tile
of a sheet this asks, without saying which cell it came from, which of the sheet's
subjects the picture shows. The answer is recorded beside what the cell was meant to
hold. It links nothing: the owner's review comes next.

    python tools/pictures/check_tiles.py SHEET_ID
"""
import base64
import json
import os
import sys

from piclib import PLAN, RECORDS, ROOT, load_records, read_json, thing_names, today, write_json


def ask(client, model: str, picture: bytes, options: list) -> tuple:
    question = (
        "This picture is one tile from a sorting game for a four-year-old. "
        f"Which ONE of these does it show? {', '.join(options)}. "
        "If it shows none of them clearly, answer \"none\". "
        "Also say, in a few words, anything wrong with it for a small child: cut off, "
        "more than one thing, writing in the picture, hard to recognise. Leave that empty if it is fine. "
        'Reply with JSON only: {"shows": "...", "problems": "..."}'
    )
    reply = client.chat.completions.create(
        model=model,
        response_format={"type": "json_object"},
        messages=[{"role": "user", "content": [
            {"type": "text", "text": question},
            {"type": "image_url",
             "image_url": {"url": "data:image/webp;base64," + base64.b64encode(picture).decode()}},
        ]}],
    )
    return json.loads(reply.choices[0].message.content), reply.usage


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check_tiles.py SHEET_ID")
    sheet_id = sys.argv[1]
    records = load_records()
    tiles = {k: t for k, t in records["tiles"].items() if t["sheet_id"] == sheet_id}
    if not tiles:
        raise SystemExit(f"No tiles for '{sheet_id}'. Cut the sheet first.")
    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is not set in the environment.")
    from openai import OpenAI

    check = read_json(PLAN)["vision_check"]
    model, spent = check["model"], 0.0
    names = thing_names()
    wanted = records["sheets"][sheet_id]["cells"]
    by_name = {names[thing].lower(): thing for thing in wanted}
    client = OpenAI()

    for tile_id, tile in tiles.items():
        # the game's version is checked, since that is what the child will see
        answer, usage = ask(client, model, (ROOT / tile["app_file"]).read_bytes(),
                            [names[t] for t in wanted])
        if usage is not None:
            spent += (usage.prompt_tokens * check["usd_per_million_input_tokens"]
                      + usage.completion_tokens * check["usd_per_million_output_tokens"]) / 1_000_000
        said = str(answer.get("shows", "")).strip()
        shows = by_name.get(said.lower())
        tile["vision"] = {
            "model": model,
            "date": today(),
            "says": said,
            "shows": shows,
            "matches_cell": shows == tile["expected_thing"],
            "problems": str(answer.get("problems", "")).strip(),
        }
        mark = "matches" if shows == tile["expected_thing"] else "DIFFERS"
        print(f"  {tile_id}: meant {names[tile['expected_thing']]}, looks like {said or '?'}  "
              f"[{mark}]  {tile['vision']['problems']}")
    records["sheets"][sheet_id]["vision_check_cost_usd"] = round(spent, 5)
    write_json(RECORDS, records)
    print(f"The check itself cost ${spent:.5f}.")

    seen = [t["vision"]["shows"] for t in tiles.values()]
    if seen != [t["expected_thing"] for t in tiles.values()]:
        if sorted(s or "" for s in seen) == sorted(wanted):
            print("Every subject is there, but in different cells: the model swapped them. "
                  "Each tile will be linked by what it shows, once the owner approves.")
        else:
            print("Some subjects are missing, repeated or unclear. See the lines marked DIFFERS.")
    print(f"Next: the owner's review - python tools/pictures/review.py list {sheet_id}")


if __name__ == "__main__":
    main()
