"""Offline test of the picture pipeline. It draws its own made-up sheets with plain
shapes, so it calls no service and costs nothing. Everything it writes goes to a
temporary folder; the real records are not touched.

    python tools/pictures/selftest.py
"""
import hashlib
import pathlib
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

import cut_sheet
import piclib
import review
from cut_sheet import CutError, cut_all

COLOURS = ["red", "green", "blue", "orange", "purple", "brown", "teal", "magenta", "olive"]


def rgb(name):
    return Image.new("RGB", (1, 1), name).getpixel((0, 0))


def sheet(size, edges_x, edges_y, extra=None):
    """A white sheet with one coloured blob per cell. edges_* are the cell boundaries."""
    image = Image.new("RGB", (size, size), "white")
    draw = ImageDraw.Draw(image)
    n = len(edges_x) - 1
    for r in range(n):
        for c in range(n):
            x0, x1, y0, y1 = edges_x[c], edges_x[c + 1], edges_y[r], edges_y[r + 1]
            pad = 0.18 * min(x1 - x0, y1 - y0)
            draw.ellipse((x0 + pad, y0 + pad, x1 - pad, y1 - pad), fill=COLOURS[(r * n + c) % 9])
    if extra:
        extra(draw)
    return image


def centre(tile):
    return tile.getpixel((tile.width // 2, tile.height // 2))


def test_each_picture_becomes_its_own_tile_whatever_the_spacing():
    edges = [0, 340, 610, 900]          # uneven: fixed thirds (300, 600) would slice pictures
    cut = cut_all(sheet(900, edges, edges), 3)
    assert len(cut) == 9
    for number, (tile, checks) in enumerate(cut):
        assert tile.size == (512, 512) and checks["ok"], checks
        assert centre(tile) == rgb(COLOURS[number])
        # the whole blob is there, with white all round it: nothing was sliced
        assert tile.getpixel((4, 4)) == (255, 255, 255) and tile.getpixel((507, 256)) == (255, 255, 255)


def test_pictures_that_overlap_in_height_are_still_separated():
    """The real case: one picture's foot reaches lower than its neighbour's top begins,
    so no straight white band runs between the rows, yet white still separates them."""
    image = Image.new("RGB", (800, 800), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((60, 40, 340, 460), fill="red")        # top-left, long
    draw.ellipse((60, 500, 340, 760), fill="green")     # bottom-left
    draw.ellipse((460, 40, 740, 330), fill="blue")      # top-right, short
    draw.ellipse((460, 370, 740, 760), fill="orange")   # bottom-right starts above red's foot
    cut = cut_all(image, 2)
    assert [centre(tile) for tile, _ in cut] == [rgb(c) for c in ("red", "blue", "green", "orange")]
    assert all(checks["ok"] for _, checks in cut)


def test_two_pictures_that_touch_stop_the_cut():
    edges = [0, 300, 600, 900]
    image = sheet(900, edges, edges, lambda d: d.rectangle((200, 140, 400, 160), fill="black"))
    try:
        cut_all(image, 3)
    except CutError as problem:
        assert "touch" in str(problem), problem
    else:
        raise AssertionError("two joined pictures were not caught")


def test_an_empty_cell_stops_the_cut():
    image = Image.new("RGB", (600, 600), "white")
    draw = ImageDraw.Draw(image)
    for box in ((60, 60, 240, 240), (360, 60, 540, 240), (60, 360, 240, 540)):
        draw.ellipse(box, fill="red")
    try:
        cut_all(image, 2)
    except CutError as problem:
        assert "no picture found in cell 4" in str(problem), problem
    else:
        raise AssertionError("an empty cell was not caught")


def test_picture_touching_the_sheet_edge_is_flagged():
    edges = [0, 300, 600, 900]
    image = sheet(900, edges, edges, lambda d: d.rectangle((0, 100, 80, 200), fill="red"))
    _, checks = cut_all(image, 3)[0]
    assert "the picture touches the edge of the sheet" in checks["flags"] and not checks["ok"], checks


def test_small_and_thin_pictures_are_noted_but_not_blocked():
    image = Image.new("RGB", (600, 600), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((60, 60, 240, 240), fill="red")
    draw.ellipse((430, 130, 470, 170), fill="blue")      # small
    draw.rectangle((140, 330, 170, 570), fill="green")   # tall and thin
    draw.ellipse((360, 360, 540, 540), fill="orange")
    cut = cut_all(image, 2)
    assert "the picture is very small" in cut[1][1]["notes"] and cut[1][1]["ok"]
    assert "the picture is far from square" in cut[2][1]["notes"] and cut[2][1]["ok"]
    assert not cut[0][1]["notes"]


def test_a_neighbour_never_shows_in_a_tile():
    # cell 1 holds a small picture close to cell 2's big one
    image = Image.new("RGB", (600, 300), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((200, 100, 280, 180), fill="red")
    draw.rectangle((300, 20, 580, 280), fill="blue")
    mask = cut_sheet.ink_mask(image)
    owner = np.full(mask.shape, -1)       # which picture each pixel belongs to
    owner[:, :290][mask[:, :290]] = 0
    owner[:, 290:][mask[:, 290:]] = 1
    tile, _ = cut_sheet.cut_tile(image, mask, owner, 0, 2)
    assert centre(tile) == rgb("red")
    assert not [p for p in tile.getdata() if p[2] > 200 and p[0] < 60], "the neighbour leaked in"


def test_loose_bits_join_the_nearest_picture():
    edges = [0, 300, 600, 900]
    # a fallen leaf beside the first picture, nearer to it than to anything else
    image = sheet(900, edges, edges, lambda d: d.ellipse((30, 250, 46, 262), fill="red"))
    tile, checks = cut_all(image, 3)[0]
    box = checks["picture_box"]
    assert box[0] <= 31 and box[3] >= 261, box   # the tile was widened to take the leaf in


def test_records_and_review():
    """The whole paper trail, with a made-up sheet standing in for a drawn one."""
    with tempfile.TemporaryDirectory() as folder:
        root = pathlib.Path(folder)
        for module in (piclib, cut_sheet, review):
            module.ROOT = root
            module.RECORDS = root / "records.json"
        cut_sheet.TILES = root / "tiles"

        plan = piclib.read_json(piclib.PLAN)
        cells = [c["thing"] for c in plan["sheets"]["trial_plants_9"]["cells"]]
        edges = [0, 300, 600, 900]
        original = root / "sheets" / "trial_plants_9_01.png"
        original.parent.mkdir(parents=True)
        sheet(900, edges, edges).save(original)
        fingerprint = hashlib.sha256(original.read_bytes()).hexdigest()
        records = piclib.load_records()
        records["sheets"]["trial_plants_9_01"] = {
            "plan_key": "trial_plants_9", "purpose": "self-test", "file": "sheets/trial_plants_9_01.png",
            "grid": 3, "size": "900x900", "cells": cells, "style_version": "v1",
            "model": "none (made-up sheet)", "quality": "high", "prompt": "made up", "date": piclib.today(),
            "tokens": None, "cost_usd": 0.45}
        piclib.write_json(piclib.RECORDS, records)

        sys.argv = ["cut_sheet.py", "trial_plants_9_01"]
        cut_sheet.main()
        records = piclib.load_records()
        assert len(records["tiles"]) == 9
        tile = records["tiles"]["trial_plants_9_01_c1"]
        for field in ("thing_id", "file", "sheet_id", "cell", "style_version", "prompt", "model",
                      "date", "cost_usd", "review"):
            assert field in tile, field
        assert tile["thing_id"] is None and tile["review"] == "waiting for the owner"
        assert tile["cost_usd"] == 0.05 and (root / tile["file"]).exists()

        # no approval before the vision check
        try:
            review.approve(records, ["trial_plants_9_01_c1"])
        except SystemExit as stop:
            assert "vision check" in str(stop)
        else:
            raise AssertionError("a tile was approved without a vision check")

        # the vision check finds cells 1 and 2 swapped; approval links by what is shown
        for number, thing in enumerate([cells[1], cells[0]] + cells[2:], 1):
            records["tiles"][f"trial_plants_9_01_c{number}"]["vision"] = {
                "model": "made up", "date": piclib.today(), "says": thing, "shows": thing,
                "matches_cell": thing == cells[number - 1], "problems": ""}
        review.approve(records, ["trial_plants_9_01_c1"])
        assert records["tiles"]["trial_plants_9_01_c1"]["thing_id"] == cells[1]

        # a rejected tile is marked, not deleted
        review.reject(records, ["trial_plants_9_01_c3"], "leaves are cut off")
        rejected = records["tiles"]["trial_plants_9_01_c3"]
        assert rejected["review"] == "rejected" and rejected["thing_id"] is None
        assert (root / rejected["file"]).exists()
        piclib.write_json(piclib.RECORDS, records)

        # cutting again never touches the original sheet, and remembers what came before
        cut_sheet.main()
        assert hashlib.sha256(original.read_bytes()).hexdigest() == fingerprint
        again = piclib.load_records()["tiles"]["trial_plants_9_01_c3"]
        assert again["history"][-1]["review_was"] == "rejected"


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing sent, nothing spent.")


if __name__ == "__main__":
    main()
