"""Offline test of the picture pipeline. It draws its own made-up sheets with plain
shapes, so it calls no service and costs nothing. Everything it writes goes to a
temporary folder; the real records are not touched.

    python tools/pictures/selftest.py
"""
import hashlib
import pathlib
import sys
import tempfile

from PIL import Image, ImageDraw

import cut_sheet
import piclib
import review
from cut_sheet import CutError, cell_boxes, cut_tile, ink_mask

COLOURS = ["red", "green", "blue", "orange", "purple", "brown", "teal", "magenta", "olive"]


def sheet(size, edges_x, edges_y, extra=None):
    """A white sheet with one coloured blob per cell. edges_* are the cell boundaries,
    deliberately uneven, so cutting on fixed thirds would slice through pictures."""
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


def colour_at_centre(tile):
    return tile.getpixel((tile.width // 2, tile.height // 2))


def test_cuts_along_the_gaps_not_on_thirds():
    edges = [0, 380, 620, 900]          # thirds would be 300 and 600
    image = sheet(900, edges, edges)
    boxes = cell_boxes(ink_mask(image), 3)
    assert len(boxes) == 9
    cuts = sorted({b[0] for b in boxes} | {b[2] for b in boxes})
    assert abs(cuts[1] - 380) <= 4 and abs(cuts[2] - 620) <= 4, cuts
    assert abs(cuts[1] - 300) > 40, "it cut on thirds"
    for number, box in enumerate(boxes):
        tile, checks = cut_tile(image, ink_mask(image), box)
        assert tile.size == (512, 512)
        assert colour_at_centre(tile) == Image.new("RGB", (1, 1), COLOURS[number]).getpixel((0, 0))
    # an uneven grid makes some cells oblong: 240 wide by 380 tall is flagged, 380 by 380 is not
    flagged = [cut_tile(image, ink_mask(image), b)[1]["flags"] for b in boxes]
    assert "its cell is not square" in flagged[1] and "its cell is not square" not in flagged[0], flagged


def test_clean_even_sheet_passes_every_check():
    edges = [0, 300, 600, 900]
    image = sheet(900, edges, edges)
    for box in cell_boxes(ink_mask(image), 3):
        tile, checks = cut_tile(image, ink_mask(image), box)
        assert checks["ok"], checks


def test_something_crossing_a_gap_stops_the_cut():
    edges = [0, 300, 600, 900]
    image = sheet(900, edges, edges, lambda d: d.rectangle((250, 140, 350, 160), fill="black"))
    try:
        cell_boxes(ink_mask(image), 3)
    except CutError as problem:
        assert "no clear white gap between columns 1 and 2" in str(problem)
    else:
        raise AssertionError("a picture crossing the gap was not caught")


def test_picture_touching_the_sheet_edge_is_flagged():
    edges = [0, 300, 600, 900]
    image = sheet(900, edges, edges, lambda d: d.rectangle((0, 100, 60, 200), fill="black"))
    _, checks = cut_tile(image, ink_mask(image), cell_boxes(ink_mask(image), 3)[0])
    assert "the picture touches the edge of the sheet" in checks["flags"], checks


def test_tiny_picture_and_empty_cell_are_flagged():
    image = Image.new("RGB", (600, 600), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((60, 60, 240, 240), fill="red")       # cell 1: normal
    draw.ellipse((440, 140, 460, 160), fill="blue")    # cell 2: tiny
    draw.ellipse((60, 360, 240, 540), fill="green")    # cell 3: normal; cell 4 left empty
    mask = ink_mask(image)
    boxes = [(0, 0, 300, 300), (300, 0, 600, 300), (0, 300, 300, 600), (300, 300, 600, 600)]
    assert "the picture is very small" in cut_tile(image, mask, boxes[1])[1]["flags"]
    assert "the cell is empty" in cut_tile(image, mask, boxes[3])[1]["flags"]


def test_a_neighbour_never_shows_in_a_tile():
    # cell 1 holds a small off-centre picture; cell 2's big picture sits right beside the gap
    image = Image.new("RGB", (600, 300), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((200, 100, 280, 180), fill="red")
    draw.rectangle((320, 20, 580, 280), fill="blue")
    tile, _ = cut_tile(image, ink_mask(image), (0, 0, 300, 300))
    blues = [p for p in tile.getdata() if p[2] > 200 and p[0] < 60]
    assert not blues, "the neighbour's picture leaked into the tile"


def test_two_by_two():
    edges = [0, 512, 1024]
    assert len(cell_boxes(ink_mask(sheet(1024, edges, edges)), 2)) == 4


def test_records_and_review():
    """The whole paper trail, with a made-up sheet standing in for a drawn one."""
    with tempfile.TemporaryDirectory() as folder:
        root = pathlib.Path(folder)
        for module in (piclib, cut_sheet, review):
            module.ROOT = root
            module.RECORDS = root / "records.json"
        cut_sheet.TILES = root / "tiles"
        piclib.RECORDS = root / "records.json"

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
