"""Shared helpers for the picture pipeline (dev-time only; nothing here runs in the game).

    make_sheet.py   draw one sheet of several tiles (costs money; the original is kept)
    cut_sheet.py    cut a sheet into tiles along its white gaps, and check each tile
    check_tiles.py  ask a vision model what each tile shows, to catch swapped cells
    review.py       the owner's verdict: approve, reject, or list what needs redrawing

Every sheet and every tile has a record in records.json. A tile is linked to a thing only
after the vision check AND the owner's approval. Rejected tiles are marked, never deleted.
"""
import datetime
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/pictures"
PLAN = HERE / "plan.json"
RECORDS = HERE / "records.json"
SHEETS = HERE / "sheets"   # original sheets, kept for ever so a tile can be re-cut
TILES = HERE / "tiles"     # cut tiles, named by sheet and cell (not by thing) until approved
THINGS = ROOT / "Assets/data/things.json"

ABOUT = ("One record per sheet and per tile. A tile's thing_id stays null until a vision "
         "check and the owner's review both agree on what it shows. Review statuses: "
         "'waiting for the owner', 'approved', 'rejected'. Rejected tiles are kept and "
         "marked, so we know what to draw again.")


def read_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_records() -> dict:
    return read_json(RECORDS, {"about": ABOUT, "sheets": {}, "tiles": {}})


def today() -> str:
    return datetime.date.today().isoformat()


def relative(path: pathlib.Path) -> str:
    return path.relative_to(ROOT).as_posix()


def thing_names() -> dict:
    """thing id -> the name a child says."""
    things = read_json(THINGS)["things"]
    return {key: thing.get("shown_as") or thing["name"] for key, thing in things.items()}


def build_prompt(plan: dict, sheet: dict, names: dict) -> str:
    style = plan["style"]
    grid = sheet["grid"]
    lines = [style["layout"].format(grid=grid, count=grid * grid), ""]
    for number, cell in enumerate(sheet["cells"], 1):
        lines.append(f"{number}. {names[cell['thing']]}: {cell['draw']}.")
    lines += ["", "Style: " + style["text"]]
    return "\n".join(lines)
