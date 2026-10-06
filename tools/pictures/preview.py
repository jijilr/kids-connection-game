"""Make review pictures: one contact sheet per drawn sheet, with each tile's name and state.

Each tile is shown as the game will show it (the small version), with its name under it.
A coloured bar marks its state: green approved, grey waiting for the owner, amber set
aside, red rejected or failed a check. The pictures go in tools/pictures/preview/.

    python tools/pictures/preview.py SHEET_ID [SHEET_ID ...]
    python tools/pictures/preview.py --for-owner     the prehistoric tiles the stricter check left for the owner
"""
import sys

from PIL import Image, ImageDraw, ImageFont

from piclib import HERE, ROOT, load_records, thing_names

SIZE, GAP, LABEL = 300, 14, 46
BACK = (120, 120, 130)
STATE = {"approved": (40, 150, 80), "waiting for the owner": (150, 150, 150),
         "set aside": (220, 160, 40), "rejected": (200, 50, 50)}


def font(size):
    try:
        return ImageFont.truetype("arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def contact(records: dict, sheet_id: str) -> Image.Image:
    sheet = records["sheets"][sheet_id]
    names = dict(thing_names(), **sheet.get("names", {}))
    n = sheet["grid"]
    cell = SIZE + LABEL
    image = Image.new("RGB", (n * SIZE + (n + 1) * GAP, n * cell + (n + 1) * GAP), BACK)
    draw = ImageDraw.Draw(image)
    for number in range(1, n * n + 1):
        tile = records["tiles"].get(f"{sheet_id}_c{number}")
        if tile is None:
            continue
        x = GAP + ((number - 1) % n) * (SIZE + GAP)
        y = GAP + ((number - 1) // n) * (cell + GAP)
        with Image.open(ROOT / tile["app_file"]) as picture:
            image.paste(picture.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), (x, y))
        failed = tile.get("feature_check") and not tile["feature_check"]["passed"]
        colour = STATE["rejected"] if failed and tile["review"] != "approved" else STATE[tile["review"]]
        draw.rectangle((x, y + SIZE, x + SIZE, y + SIZE + LABEL), fill=(255, 255, 255))
        draw.rectangle((x, y + SIZE, x + SIZE, y + SIZE + 6), fill=colour)
        name = names.get(tile["expected_thing"], tile["expected_thing"])
        seen = tile["vision"]["says"] if tile.get("vision") else ""
        if seen and seen.lower() != name.lower():
            name += f"  (looks like {seen})"
        draw.text((x + 8, y + SIZE + 14), f"{number}. {name}", fill=(30, 30, 30), font=font(18))
    return image


def for_owner(records: dict) -> Image.Image:
    """Every prehistoric tile the stricter check left for the owner, on one picture.
    Blue bar: every feature is right, but the sources disagree about the animal.
    Red bar: the check found something wrong."""
    names = thing_names()
    waiting = []
    for tile_id, tile in records["tiles"].items():
        check = tile.get("feature_check")
        if check and not check["passed"] and tile["review"] == "waiting for the owner":
            only_sources = all(r.startswith("the sources disagree") for r in check["reasons"])
            waiting.append((not only_sources, tile_id, tile))
    waiting.sort(key=lambda w: (w[0], w[1]))
    columns = 5
    rows = -(-len(waiting) // columns)
    cell = SIZE + LABEL + 22
    image = Image.new("RGB", (columns * SIZE + (columns + 1) * GAP, rows * cell + (rows + 1) * GAP), BACK)
    draw = ImageDraw.Draw(image)
    for index, (failed, tile_id, tile) in enumerate(waiting):
        x = GAP + (index % columns) * (SIZE + GAP)
        y = GAP + (index // columns) * (cell + GAP)
        with Image.open(ROOT / tile["app_file"]) as picture:
            image.paste(picture.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), (x, y))
        draw.rectangle((x, y + SIZE, x + SIZE, y + cell), fill=(255, 255, 255))
        draw.rectangle((x, y + SIZE, x + SIZE, y + SIZE + 6), fill=STATE["rejected"] if failed else (50, 110, 200))
        sheet = records["sheets"][tile["sheet_id"]]
        name = dict(names, **sheet.get("names", {})).get(tile["expected_thing"], tile["expected_thing"])
        draw.text((x + 8, y + SIZE + 14), f"{index + 1}. {name}", fill=(30, 30, 30), font=font(18))
        draw.text((x + 8, y + SIZE + 40), tile_id, fill=(110, 110, 110), font=font(14))
    return image


def main():
    records = load_records()
    (HERE / "preview").mkdir(exist_ok=True)
    if sys.argv[1:] == ["--for-owner"]:
        path = HERE / "preview" / "prehistoric_for_owner.png"
        for_owner(records).save(path)
        print(f"  {path.relative_to(ROOT).as_posix()}")
        return
    wanted = sys.argv[1:] or list(records["sheets"])
    for sheet_id in wanted:
        if sheet_id not in records["sheets"]:
            raise SystemExit(f"No sheet '{sheet_id}'.")
        path = HERE / "preview" / f"{sheet_id}_review.png"
        contact(records, sheet_id).save(path)
        print(f"  {path.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
