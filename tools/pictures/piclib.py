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
         "'waiting for the owner', 'approved', 'rejected', 'set aside' (good, but "
         "deliberately not linked). Rejected tiles are kept and marked, so we know what "
         "to draw again.")


def original(path: pathlib.Path) -> pathlib.Path:
    """An original sheet or a full-size master, which live in Git LFS, not in the main
    repository (the owner's ruling of 6 Oct 2026). Only the small game versions are
    ordinary files. Stops with a clear message if the real file has not been fetched."""
    if not path.exists():
        raise SystemExit(f"{relative(path)} is missing. Fetch the originals with: git lfs pull")
    with path.open("rb") as file:
        if file.read(40).startswith(b"version https://git-lfs"):
            raise SystemExit(f"{relative(path)} is only a pointer. Fetch the originals with: git lfs pull")
    return path


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


def sheet_names(sheet: dict) -> dict:
    """thing id -> display name for one planned sheet. A cell may carry its own `name`,
    for something that is not in the game yet."""
    names = thing_names()
    return {cell["thing"]: cell.get("name") or names.get(cell["thing"]) for cell in sheet["cells"]}


def build_prompt(plan: dict, sheet: dict, names: dict) -> str:
    style = plan["style"]
    grid = sheet["grid"]
    layout = style["layout_single"] if grid == 1 else style["layout"].format(grid=grid, count=grid * grid)
    lines = [layout, ""]
    for number, cell in enumerate(sheet["cells"], 1):
        lines.append(f"{number}. {names[cell['thing']]}: {cell['draw']}.")
    if sheet.get("only_for_this_sheet"):
        lines += ["", "For this sheet: " + sheet["only_for_this_sheet"]]
    lines += ["", "Style: " + style["text"]]
    return "\n".join(lines)
