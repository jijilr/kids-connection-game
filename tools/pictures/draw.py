"""Draw several planned sheets one after another: draw, cut, vision check.

It stops at once if a sheet costs more than the owner's limit, or if the service
refuses a request, so a problem never repeats down the list. A sheet that cannot be
cut is kept and reported, and the run moves on to the next one.

    python tools/pictures/draw.py SHEET [SHEET ...]
"""
import subprocess
import sys

from piclib import HERE, PLAN, load_records, read_json


def run(script: str, *args) -> int:
    return subprocess.run([sys.executable, str(HERE / script), *args]).returncode


def main():
    keys = sys.argv[1:]
    plan = read_json(PLAN)
    unknown = [k for k in keys if k not in plan["sheets"]]
    if not keys or unknown:
        raise SystemExit(f"Usage: draw.py SHEET [SHEET ...]   unknown: {unknown}")
    limit = plan["prices"]["stop_if_a_sheet_costs_more_than_usd"]
    rate = plan["prices"]["inr_per_usd"]

    spent = 0.0
    for key in keys:
        print(f"\n===== {key} =====", flush=True)
        before = set(load_records()["sheets"])
        if run("make_sheet.py", key, "--yes") != 0:
            print(f"STOPPED at {key}: the sheet could not be drawn. Nothing after it was attempted.")
            break
        records = load_records()
        sheet_id = (set(records["sheets"]) - before).pop()
        cost = records["sheets"][sheet_id]["cost_usd"]
        spent += cost or 0
        if cost is None or cost > limit:
            print(f"STOPPED after {sheet_id}: its cost is unknown or over the limit of ${limit:.2f}.")
            break
        if run("cut_sheet.py", sheet_id) != 0:
            print(f"{sheet_id} could not be cut; it is kept. Moving on.", flush=True)
            continue
        run("check_tiles.py", sheet_id)
    print(f"\nSheets in this run cost ${spent:.2f}, about Rs {spent * rate:.0f}.")


if __name__ == "__main__":
    main()
