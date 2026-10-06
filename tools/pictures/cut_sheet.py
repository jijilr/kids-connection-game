"""Cut a sheet into tiles along the white between its pictures, and check each tile.

It never cuts on fixed thirds, and it does not need straight gaps. A real sheet is rarely
a tidy grid: one picture's stem may reach lower than its neighbour's leaves begin, so no
straight white band runs between them, yet white still separates them. So it finds each
picture as a patch of ink surrounded by white, and gives every patch to the picture it
belongs to. The grid is used only to say which picture is which cell (reading order),
never to decide where to cut. If two pictures actually touch, there is no white between
them, and it stops.

Each tile is its own picture, centred on a white square with a margin; anything that
belongs to a neighbour is left out. Two files are written for it:
  - a MASTER, at the sheet's full resolution, never resampled and never overwritten
    (cutting again writes a new master beside the old one);
  - an APP version for the game, a compressed WebP made from the master, which can be
    remade at any time.
Then it is checked. These stop a tile being approved:
  - the picture touches the edge of the sheet (it may be cut off);
  - something reaches the edge of the finished tile;
  - the cell is empty.
These are noted for the reviewer but do not block:
  - the picture is far from square, so it sits small in a square tile;
  - the picture is very small for its cell.
A tile that fails a check is still saved and recorded, with the reason, never dropped.

Tiles are named by sheet and cell, not by thing: the model may have swapped cells, so a
tile is linked to a thing only after the vision check and the owner's review.

    python tools/pictures/cut_sheet.py SHEET_ID
"""
import hashlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

from piclib import PLAN, RECORDS, ROOT, TILES, load_records, read_json, relative, thing_names, today, write_json

INK_TOLERANCE = 24      # how far from the background colour a pixel must be to count as picture
SHRINK = 2              # patches are found on a sheet shrunk by this much
MAIN_PATCH = 0.005      # a picture's main patch covers at least this share of its cell
TOO_BIG = 1.5           # a patch this many cells wide or tall is two pictures joined
SQUARE_RANGE = (0.5, 2.0)
SMALL_PICTURE = 0.35    # picture's longer side, as a share of its cell
MARGIN = 0.08           # white margin on each side of the finished tile
STRAY_PIXELS = 12       # this few faint pixels on a tile's rim are a neighbour's halo, not a cut-off picture
APP_SIZE = 384          # the game's version of a tile, in pixels
APP_QUALITY = 85        # WebP quality of the game's version


class CutError(Exception):
    pass


def ink_mask(image: Image.Image) -> np.ndarray:
    """True wherever the sheet shows picture rather than background."""
    pixels = np.asarray(image.convert("RGB")).astype(np.int16)
    corners = np.concatenate([pixels[:8, :8], pixels[:8, -8:], pixels[-8:, :8], pixels[-8:, -8:]])
    background = np.median(corners.reshape(-1, 3), axis=0)
    return np.abs(pixels - background).max(axis=2) > INK_TOLERANCE


def separate(mask: np.ndarray, n: int) -> np.ndarray:
    """For every pixel, the cell (0 .. n*n-1, reading order) whose picture it belongs to,
    or -1 for white. Pictures are told apart by the white between them."""
    height, width = mask.shape
    h, w = height // SHRINK, width // SHRINK
    small = mask[:h * SHRINK, :w * SHRINK].reshape(h, SHRINK, w, SHRINK).any(axis=(1, 3))
    labels, count = ndimage.label(small, structure=np.ones((3, 3)))
    if count == 0:
        return np.full(mask.shape, -1)
    index = np.arange(1, count + 1)
    areas = ndimage.sum(small, labels, index)
    centres = ndimage.center_of_mass(small, labels, index)
    boxes = ndimage.find_objects(labels)

    def cell_at(y, x):
        return min(n - 1, int(y * n / h)) * n + min(n - 1, int(x * n / w))

    # A patch much wider or taller than a cell is two pictures touching.
    for box in boxes:
        tall, wide = box[0].stop - box[0].start, box[1].stop - box[1].start
        if tall > TOO_BIG * h / n or wide > TOO_BIG * w / n:
            first = cell_at(box[0].start, box[1].start) + 1
            last = cell_at(box[0].stop - 1, box[1].stop - 1) + 1
            raise CutError(f"the pictures in cells {first} and {last} touch: "
                           "there is no white between them")

    # Each cell's main patch: the largest one centred in that cell.
    big = MAIN_PATCH * (h / n) * (w / n)
    main = {}
    for i in range(count):
        cell = cell_at(*centres[i])
        if areas[i] >= big and (cell not in main or areas[i] > areas[main[cell]]):
            main[cell] = i
    missing = [cell + 1 for cell in range(n * n) if cell not in main]
    if missing:
        raise CutError(f"no picture found in cell {missing[0]}")

    # Every other patch (a fallen leaf, a ripple, a tuft of grass) joins the nearest main patch.
    owner_of = np.full(count + 1, -1)
    for cell, i in main.items():
        owner_of[i + 1] = cell
    for i in range(count):
        if owner_of[i + 1] != -1:
            continue
        y, x = centres[i]

        def distance(item):
            box = boxes[item[1]]
            dy = max(box[0].start - y, 0, y - box[0].stop)
            dx = max(box[1].start - x, 0, x - box[1].stop)
            return dy * dy + dx * dx

        owner_of[i + 1] = min(main.items(), key=distance)[0]

    owner_small = owner_of[labels]
    owner = np.full(mask.shape, -1)
    grown = np.repeat(np.repeat(owner_small, SHRINK, axis=0), SHRINK, axis=1)
    owner[:grown.shape[0], :grown.shape[1]] = grown
    return owner


def cut_tile(image: Image.Image, mask: np.ndarray, owner: np.ndarray, cell: int, n: int) -> tuple:
    """One finished tile and the result of its checks."""
    height, width = mask.shape
    checks = {"flags": [], "notes": []}
    flags, notes = checks["flags"], checks["notes"]

    ys, xs = np.nonzero(mask & (owner == cell))
    if len(xs) == 0:
        flags.append("the cell is empty")
        checks["ok"] = False
        return Image.new("RGB", (APP_SIZE, APP_SIZE), "white"), checks
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
    checks["picture_box"] = [x0, y0, x1, y1]
    shape = (x1 - x0) / (y1 - y0)
    checks["picture_shape"] = round(shape, 2)
    if x0 <= 1 or y0 <= 1 or x1 >= width - 1 or y1 >= height - 1:
        flags.append("the picture touches the edge of the sheet")
    if not SQUARE_RANGE[0] <= shape <= SQUARE_RANGE[1]:
        notes.append("the picture is far from square")
    longer = max(x1 - x0, y1 - y0)
    if longer < SMALL_PICTURE * min(width, height) / n:
        notes.append("the picture is very small")

    # A white square around the picture, with everything that belongs to a neighbour
    # painted out, so a neighbour can never show in a corner.
    side = int(round(longer * (1 + 2 * MARGIN)))
    ox, oy = (x0 + x1) // 2 - side // 2, (y0 + y1) // 2 - side // 2
    sx0, sy0, sx1, sy1 = max(ox, 0), max(oy, 0), min(ox + side, width), min(oy + side, height)
    patch = np.asarray(image.convert("RGB"))[sy0:sy1, sx0:sx1].copy()
    theirs = owner[sy0:sy1, sx0:sx1]
    others = ndimage.binary_dilation((theirs != -1) & (theirs != cell), iterations=3)
    patch[others & (theirs != cell)] = 255
    tile = Image.new("RGB", (side, side), "white")
    tile.paste(Image.fromarray(patch), (sx0 - ox, sy0 - oy))   # full resolution, not resampled

    ring = ink_mask(tile)
    edge = max(2, side // 50)
    ring[edge:-edge, edge:-edge] = False
    if ring.sum() > STRAY_PIXELS:
        flags.append("something reaches the edge of the finished tile")
    checks["ok"] = not flags
    return tile, checks


def save_master(folder, tile_id: str, tile: Image.Image, old) -> tuple:
    """Write the full-resolution master without ever overwriting one. If this exact
    picture is already saved, that file is reused; otherwise it gets the next number."""
    digest = hashlib.sha256(tile.tobytes()).hexdigest()
    if old and old.get("master_sha256") == digest and (ROOT / old["master_file"]).exists():
        return ROOT / old["master_file"], digest
    folder.mkdir(parents=True, exist_ok=True)
    path, number = folder / f"{tile_id}.png", 1
    while path.exists():
        number += 1
        path = folder / f"{tile_id}_cut{number:02d}.png"
    tile.save(path)
    return path, digest


def save_app_version(folder, tile_id: str, tile: Image.Image):
    """The game's copy: small and compressed. Made from the master; safe to remake."""
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{tile_id}.webp"
    tile.resize((APP_SIZE, APP_SIZE), Image.LANCZOS).save(path, "WEBP", quality=APP_QUALITY)
    return path


def cut_all(image: Image.Image, n: int) -> list:
    """Every tile of a sheet, reading order, as (tile, checks)."""
    mask = ink_mask(image)
    owner = separate(mask, n)
    return [cut_tile(image, mask, owner, cell, n) for cell in range(n * n)]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: cut_sheet.py SHEET_ID")
    sheet_id = sys.argv[1]
    records = load_records()
    if sheet_id not in records["sheets"]:
        raise SystemExit(f"No sheet '{sheet_id}'. Known: {', '.join(records['sheets']) or 'none'}")
    sheet = records["sheets"][sheet_id]
    plan = read_json(PLAN)
    names = dict(thing_names(), **sheet.get("names", {}))
    planned = plan["sheets"][sheet["plan_key"]]["cells"]

    image = Image.open(ROOT / sheet["file"])
    try:
        cut = cut_all(image, sheet["grid"])
    except CutError as problem:
        sheet["cut_error"] = str(problem)
        write_json(RECORDS, records)
        raise SystemExit(f"Could not cut {sheet_id}: {problem}. The sheet is kept; nothing was cut.")
    sheet.pop("cut_error", None)

    count = len(cut)
    for number, (tile, checks) in enumerate(cut, 1):
        tile_id = f"{sheet_id}_c{number}"
        expected = sheet["cells"][number - 1]
        old = records["tiles"].get(tile_id)
        master, digest = save_master(TILES / "masters", tile_id, tile, old)
        app = save_app_version(TILES / "app", tile_id, tile)
        history = (old or {}).get("history", [])
        if old:
            event = {"date": today(), "event": "cut again", "review_was": old["review"]}
            if old.get("master_file") and old["master_file"] != relative(master):
                event["earlier_master"] = old["master_file"]
            history.append(event)
        records["tiles"][tile_id] = {
            "thing_id": None,
            "expected_thing": expected,
            "master_file": relative(master),
            "master_size": list(tile.size),
            "master_sha256": digest,
            "app_file": relative(app),
            "app_size": [APP_SIZE, APP_SIZE],
            "sheet_id": sheet_id,
            "cell": number,
            "style_version": sheet["style_version"],
            "prompt": f"{names.get(expected, expected)}: {planned[number - 1]['draw']}",
            "look_closely": planned[number - 1].get("look_closely", ""),
            "model": sheet["model"],
            "date": sheet["date"],
            "cost_usd": None if sheet["cost_usd"] is None else round(sheet["cost_usd"] / count, 4),
            "cut": dict(checks, on=today()),
            "vision": None,
            "review": "waiting for the owner",
            "review_note": "",
            "history": history,
        }
        if old and old.get("master_sha256") == digest:
            # the very same picture: what was already found out about it still holds
            for kept in ("vision", "review", "review_note", "reviewed_on", "thing_id"):
                if kept in old:
                    records["tiles"][tile_id][kept] = old[kept]
        verdict = "ok" if checks["ok"] else "; ".join(checks["flags"])
        noted = f"  [note: {'; '.join(checks['notes'])}]" if checks["notes"] else ""
        print(f"  {tile_id}  ({names.get(expected, expected)})  {verdict}{noted}")
    write_json(RECORDS, records)
    print(f"Cut {count} tiles along the white between the pictures. "
          f"Next: python tools/pictures/check_tiles.py {sheet_id}")


if __name__ == "__main__":
    main()
