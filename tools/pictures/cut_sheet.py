"""Cut a sheet into tiles along its white gaps, and check each tile.

It never cuts on fixed thirds. It looks for the bands of white that run right across the
sheet between the cells and cuts down the middle of them. If there is no clear band
where one should be, something crosses from one cell into the next, and it stops.

Each tile is trimmed to its picture, centred on a white square with a margin, and checked:
  - its cell is roughly square (the grid came out even);
  - the picture touches neither the edge of the sheet nor the edge of its cell;
  - nothing reaches the edge of the finished tile;
  - the picture is not empty or tiny.
A tile that fails a check is still saved and recorded, with the reason, never dropped.

Tiles are named by sheet and cell, not by thing: the model may have swapped cells, so a
tile is linked to a thing only after the vision check and the owner's review.

    python tools/pictures/cut_sheet.py SHEET_ID
"""
import sys

import numpy as np
from PIL import Image

from piclib import PLAN, RECORDS, ROOT, TILES, load_records, read_json, relative, thing_names, today, write_json

INK_TOLERANCE = 24      # how far from the background colour a pixel must be to count as picture
BLANK_LINE = 0.002      # a row or column with less ink than this share is white
MIN_GAP = 0.01          # a gap must be at least this share of the sheet wide
SQUARE_RANGE = (0.8, 1.25)
SMALL_PICTURE = 0.35    # picture's longer side, as a share of its cell
MARGIN = 0.08           # white margin on each side of the finished tile
TILE_SIZE = 512


class CutError(Exception):
    pass


def ink_mask(image: Image.Image) -> np.ndarray:
    """True wherever the sheet shows picture rather than background."""
    pixels = np.asarray(image.convert("RGB")).astype(np.int16)
    corners = np.concatenate([pixels[:8, :8], pixels[:8, -8:], pixels[-8:, :8], pixels[-8:, -8:]])
    background = np.median(corners.reshape(-1, 3), axis=0)
    return np.abs(pixels - background).max(axis=2) > INK_TOLERANCE


def find_gaps(mask: np.ndarray, axis: int, n: int) -> list:
    """The n-1 white bands that separate n rows (axis 0) or columns (axis 1)."""
    lines = mask.mean(axis=1 - axis) <= BLANK_LINE   # one flag per row / column
    length = len(lines)
    runs, start = [], None
    for i, blank in enumerate(list(lines) + [False]):
        if blank and start is None:
            start = i
        elif not blank and start is not None:
            runs.append((start, i))
            start = None
    inner = [r for r in runs if r[0] > 0 and r[1] < length and r[1] - r[0] >= MIN_GAP * length]
    what = "rows" if axis == 0 else "columns"
    gaps = []
    for k in range(1, n):
        expected, reach = k * length / n, 0.35 * length / n
        near = [r for r in inner if abs((r[0] + r[1]) / 2 - expected) <= reach]
        if not near:
            raise CutError(f"no clear white gap between {what} {k} and {k + 1}: "
                           "something crosses from one cell into the next")
        gaps.append(max(near, key=lambda r: r[1] - r[0]))
    return gaps


def cell_boxes(mask: np.ndarray, n: int) -> list:
    """(left, top, right, bottom) of each cell, reading order, cut mid-way through the gaps."""
    height, width = mask.shape
    xs = [0] + [(a + b) // 2 for a, b in find_gaps(mask, 1, n)] + [width]
    ys = [0] + [(a + b) // 2 for a, b in find_gaps(mask, 0, n)] + [height]
    return [(xs[c], ys[r], xs[c + 1], ys[r + 1]) for r in range(n) for c in range(n)]


def cut_tile(image: Image.Image, mask: np.ndarray, box: tuple) -> tuple:
    """One finished tile and the result of its checks."""
    left, top, right, bottom = box
    height, width = mask.shape
    shape = (right - left) / (bottom - top)
    checks = {"cell_box": list(box), "cell_shape": round(shape, 2), "flags": []}
    flags = checks["flags"]
    if not SQUARE_RANGE[0] <= shape <= SQUARE_RANGE[1]:
        flags.append("its cell is not square")

    ys, xs = np.nonzero(mask[top:bottom, left:right])
    if len(xs) == 0:
        flags.append("the cell is empty")
        checks["ok"] = False
        return Image.new("RGB", (TILE_SIZE, TILE_SIZE), "white"), checks
    x0, x1, y0, y1 = left + xs.min(), left + xs.max() + 1, top + ys.min(), top + ys.max() + 1
    if x0 <= 1 or y0 <= 1 or x1 >= width - 1 or y1 >= height - 1:
        flags.append("the picture touches the edge of the sheet")
    elif x0 <= left + 1 or y0 <= top + 1 or x1 >= right - 1 or y1 >= bottom - 1:
        flags.append("the picture touches the edge of its cell")
    longer = max(x1 - x0, y1 - y0)
    if longer < SMALL_PICTURE * min(right - left, bottom - top):
        flags.append("the picture is very small")

    # A white square around the picture. Only this cell's pixels are copied in, so a
    # neighbour can never show in a corner.
    side = int(round(longer * (1 + 2 * MARGIN)))
    tile = Image.new("RGB", (side, side), "white")
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    ox, oy = cx - side // 2, cy - side // 2
    sx0, sy0, sx1, sy1 = max(ox, left), max(oy, top), min(ox + side, right), min(oy + side, bottom)
    tile.paste(image.convert("RGB").crop((sx0, sy0, sx1, sy1)), (sx0 - ox, sy0 - oy))
    tile = tile.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)

    ring = ink_mask(tile)
    edge = max(2, TILE_SIZE // 50)
    ring[edge:-edge, edge:-edge] = False
    if ring.any():
        flags.append("something reaches the edge of the finished tile")
    checks["ok"] = not flags
    return tile, checks


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: cut_sheet.py SHEET_ID")
    sheet_id = sys.argv[1]
    records = load_records()
    if sheet_id not in records["sheets"]:
        raise SystemExit(f"No sheet '{sheet_id}'. Known: {', '.join(records['sheets']) or 'none'}")
    sheet = records["sheets"][sheet_id]
    plan = read_json(PLAN)
    names = thing_names()
    draws = {c["thing"]: c["draw"] for c in plan["sheets"][sheet["plan_key"]]["cells"]}

    image = Image.open(ROOT / sheet["file"])
    mask = ink_mask(image)
    try:
        boxes = cell_boxes(mask, sheet["grid"])
    except CutError as problem:
        sheet["cut_error"] = str(problem)
        write_json(RECORDS, records)
        raise SystemExit(f"Could not cut {sheet_id}: {problem}. The sheet is kept; nothing was cut.")
    sheet.pop("cut_error", None)

    TILES.mkdir(parents=True, exist_ok=True)
    count = len(boxes)
    for number, box in enumerate(boxes, 1):
        tile_id = f"{sheet_id}_c{number}"
        tile, checks = cut_tile(image, mask, box)
        path = TILES / f"{tile_id}.png"
        tile.save(path)
        expected = sheet["cells"][number - 1]
        old = records["tiles"].get(tile_id)
        history = (old or {}).get("history", [])
        if old:
            history.append({"date": today(), "event": "cut again", "review_was": old["review"]})
        records["tiles"][tile_id] = {
            "thing_id": None,
            "expected_thing": expected,
            "file": relative(path),
            "sheet_id": sheet_id,
            "cell": number,
            "style_version": sheet["style_version"],
            "prompt": f"{names.get(expected, expected)}: {draws.get(expected, '')}",
            "model": sheet["model"],
            "date": sheet["date"],
            "cost_usd": None if sheet["cost_usd"] is None else round(sheet["cost_usd"] / count, 4),
            "cut": dict(checks, on=today()),
            "vision": None,
            "review": "waiting for the owner",
            "review_note": "",
            "history": history,
        }
        verdict = "ok" if checks["ok"] else "; ".join(checks["flags"])
        print(f"  {tile_id}  ({names.get(expected, expected)})  {verdict}")
    write_json(RECORDS, records)
    print(f"Cut {count} tiles along the white gaps. Next: python tools/pictures/check_tiles.py {sheet_id}")


if __name__ == "__main__":
    main()
