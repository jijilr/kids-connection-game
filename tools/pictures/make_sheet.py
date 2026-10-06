"""Draw one sheet of tiles. This is the only step that costs money.

The original sheet is saved under tools/pictures/sheets/ and is never overwritten: a
second attempt at the same sheet gets the next number (_02, _03 ...). The full prompt,
the model, the date and the real cost (from the tokens the service reports) are recorded.

    python tools/pictures/make_sheet.py SHEET --dry-run    show the prompt; call nothing
    python tools/pictures/make_sheet.py SHEET --yes        draw it
"""
import base64
import os
import sys

from piclib import (PLAN, RECORDS, SHEETS, build_prompt, load_records, read_json, relative,
                    sheet_names, today, write_json)


def cost_usd(usage, prices: dict):
    """The real cost of one image, from the tokens the service says it used."""
    if usage is None:
        return None, None
    as_dict = usage if isinstance(usage, dict) else usage.model_dump()
    output = as_dict.get("output_tokens") or 0
    text_in = (as_dict.get("input_tokens_details") or {}).get("text_tokens",
                                                               as_dict.get("input_tokens") or 0)
    cost = (output * prices["usd_per_million_image_output_tokens"]
            + text_in * prices["usd_per_million_text_input_tokens"]) / 1_000_000
    return round(cost, 4), {"image_output_tokens": output, "text_input_tokens": text_in}


def main():
    plan = read_json(PLAN)
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    keys = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(keys) != 1 or keys[0] not in plan["sheets"] or not flags & {"--dry-run", "--yes"}:
        raise SystemExit("Usage: make_sheet.py SHEET (--dry-run | --yes)\n"
                         f"Sheets in the plan: {', '.join(plan['sheets'])}")
    key = keys[0]
    sheet, style = plan["sheets"][key], plan["style"]
    names = sheet_names(sheet)
    unknown = [thing for thing, name in names.items() if not name]
    if unknown or len(sheet["cells"]) != sheet["grid"] ** 2:
        raise SystemExit(f"The plan for {key} is wrong: unknown things {unknown}, "
                         f"or not {sheet['grid'] ** 2} cells.")
    prompt = build_prompt(plan, sheet, names)
    size = f"{sheet['size']}x{sheet['size']}"

    if "--dry-run" in flags:
        print(f"SHEET {key}: {size}, model {style['model']}, quality {style['quality']}, "
              f"style {style['version']} ({style.get('status', 'no status')})\n")
        print(prompt)
        print("\nNothing was sent and nothing was spent.")
        return

    if style.get("status") != "approved":
        raise SystemExit(f"Not drawing: the style is not approved by the owner.\n  {style.get('status')}")
    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is not set in the environment.")
    from openai import OpenAI

    records = load_records()
    attempt = 1 + sum(1 for s in records["sheets"].values() if s["plan_key"] == key)
    sheet_id = f"{key}_{attempt:02d}"
    path = SHEETS / f"{sheet_id}.png"
    if path.exists():
        raise SystemExit(f"{path.name} already exists; originals are never overwritten.")

    reply = OpenAI().images.generate(model=style["model"], prompt=prompt, size=size,
                                     quality=style["quality"], n=1)
    SHEETS.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64decode(reply.data[0].b64_json))
    cost, tokens = cost_usd(getattr(reply, "usage", None), plan["prices"])

    records["sheets"][sheet_id] = {
        "plan_key": key,
        "purpose": sheet["purpose"],
        "file": relative(path),
        "grid": sheet["grid"],
        "size": size,
        "cells": [c["thing"] for c in sheet["cells"]],
        "names": names,
        "style_version": style["version"],
        "model": style["model"],
        "quality": style["quality"],
        "prompt": prompt,
        "date": today(),
        "tokens": tokens,
        "cost_usd": cost,
    }
    write_json(RECORDS, records)
    print(f"Saved {relative(path)}")
    if cost is None:
        print("Cost: unknown (the service reported no usage). Check the account before drawing another.")
    else:
        rupees = cost * plan["prices"]["inr_per_usd"]
        tiles = sheet["grid"] ** 2
        print(f"Cost: ${cost:.4f}, about Rs {rupees:.0f} for the sheet "
              f"(Rs {rupees / tiles:.1f} a tile)  {tokens}")
        limit = plan["prices"]["stop_if_a_sheet_costs_more_than_usd"]
        if cost > limit:
            print(f"STOP: that is over the owner's limit of ${limit:.2f} a sheet. Draw nothing more "
                  "until he has seen this.")
    print(f"Next: python tools/pictures/cut_sheet.py {sheet_id}")


if __name__ == "__main__":
    main()
