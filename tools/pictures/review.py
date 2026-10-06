"""The owner's verdict on tiles. This is the only place a tile is linked to a thing.

A tile can be approved only after it was cut cleanly and the vision check has said what
it shows. Approving links it to that thing. Rejecting marks it and keeps the file, so we
know what to draw again.

    python tools/pictures/review.py list [SHEET_ID]
    python tools/pictures/review.py approve TILE_ID... [--as THING_ID]
    python tools/pictures/review.py reject TILE_ID... --why "reason"
    python tools/pictures/review.py set-aside TILE_ID... --why "reason"
    python tools/pictures/review.py approve-passed SHEET_ID
    python tools/pictures/review.py todo

"approve-passed" follows the owner's standing rule of 6 Oct 2026: an ordinary tile that
cut cleanly, and that the vision check named correctly, is approved without waiting for
him; he glances at the contact sheet afterwards. It leaves alone prehistoric animals
(they go through check_features.py) and things drawn more than once (choose.py).

"Set aside" is for a good tile that is deliberately not linked to a thing, such as the
tiles of a control sheet. It is kept, like every other tile.
"""
import sys

from piclib import PLAN, RECORDS, load_records, read_json, thing_names, today, write_json

PASSED = ("approved under the owner's standing rule of 2026-10-06: it cut cleanly and the "
          "vision check named it")


def show(records: dict, sheet_id=None):
    names = thing_names()
    for tile_id, tile in records["tiles"].items():
        if sheet_id and tile["sheet_id"] != sheet_id:
            continue
        vision = tile["vision"]
        looks = "not checked yet" if vision is None else (vision["says"] or "?")
        cut = "clean cut" if tile["cut"]["ok"] else "; ".join(tile["cut"]["flags"])
        if tile["cut"].get("notes"):
            cut += f" (note: {'; '.join(tile['cut']['notes'])})"
        linked = f" -> {names.get(tile['thing_id'], tile['thing_id'])}" if tile["thing_id"] else ""
        if tile.get("look_closely"):
            linked += f"  ** LOOK CLOSELY: {tile['look_closely']}"
        print(f"  {tile_id}: meant {names.get(tile['expected_thing'])}; looks like {looks}; "
              f"{cut}; {tile['review']}{linked}"
              + (f" ({tile['review_note']})" if tile["review_note"] else ""))


def approve(records: dict, tile_ids: list, as_thing=None):
    names = thing_names()
    for tile_id in tile_ids:
        tile = records["tiles"][tile_id]
        if not tile["cut"]["ok"]:
            raise SystemExit(f"{tile_id} did not cut cleanly ({'; '.join(tile['cut']['flags'])}). "
                             "Reject it, or cut the sheet again.")
        if tile["vision"] is None:
            raise SystemExit(f"{tile_id} has not had its vision check. Run check_tiles.py first.")
        thing = as_thing or tile["vision"]["shows"]
        if thing not in names:
            raise SystemExit(f"{tile_id}: the vision check could not say what it shows. "
                             "Approve it with --as THING_ID if you can see what it is.")
        tile.update(thing_id=thing, review="approved", review_note="", reviewed_on=today())
        print(f"  {tile_id} approved and linked to {names[thing]}")


def approve_passed(records: dict, sheet_id: str):
    sheet = records["sheets"].get(sheet_id)
    if sheet is None:
        raise SystemExit(f"No sheet '{sheet_id}'.")
    names = dict(thing_names(), **sheet.get("names", {}))
    cells = read_json(PLAN)["sheets"][sheet["plan_key"]]["cells"]
    live = lambda thing: [k for k, t in records["tiles"].items() if t["expected_thing"] == thing
                          and t["review"] in ("approved", "waiting for the owner")]
    for tile_id, tile in records["tiles"].items():
        if tile["sheet_id"] != sheet_id or tile["review"] != "waiting for the owner":
            continue
        thing, why_not = tile["expected_thing"], ""
        if cells[tile["cell"] - 1].get("features"):
            why_not = "a prehistoric animal: it goes through check_features.py"
        elif not tile["cut"]["ok"]:
            why_not = "it did not cut cleanly"
        elif not tile["vision"] or tile["vision"]["shows"] != thing:
            why_not = "the vision check did not name it"
        elif thing not in thing_names():
            why_not = "it is not a thing in the game"
        elif len(live(thing)) > 1:
            why_not = "it was drawn more than once: choose with choose.py"
        if why_not:
            print(f"  {tile_id} ({names.get(thing, thing)}) left for the owner: {why_not}")
            continue
        tile.update(thing_id=thing, review="approved", review_note=PASSED, reviewed_on=today())
        print(f"  {tile_id} approved and linked to {names[thing]}")


def reject(records: dict, tile_ids: list, why: str):
    for tile_id in tile_ids:
        records["tiles"][tile_id].update(thing_id=None, review="rejected", review_note=why,
                                         reviewed_on=today())
        print(f"  {tile_id} rejected ({why}); the file is kept")


def set_aside(records: dict, tile_ids: list, why: str):
    for tile_id in tile_ids:
        records["tiles"][tile_id].update(thing_id=None, review="set aside", review_note=why,
                                         reviewed_on=today())
        print(f"  {tile_id} set aside ({why}); not linked to a thing")


def todo(records: dict):
    """Things a sheet was meant to draw that still have no approved tile, and things the
    owner wants drawn again later."""
    names = thing_names()
    for thing, why in records.get("redo_later", {}).items():
        print(f"  {names.get(thing, thing)}: draw again later - {why}")
    approved = {t["thing_id"] for t in records["tiles"].values() if t["review"] == "approved"}
    wanted = {thing for sheet in records["sheets"].values() for thing in sheet["cells"]}
    for thing in sorted(wanted - approved):
        tried = [k for k, t in records["tiles"].items() if t["expected_thing"] == thing]
        states = ", ".join(f"{k} {records['tiles'][k]['review']}" for k in tried) or "never cut"
        print(f"  {names.get(thing, thing)}: no approved tile yet ({states})")
    if not wanted - approved:
        print("  every thing that was drawn has an approved tile")


def main():
    args = sys.argv[1:]
    records = load_records()
    if not args or args[0] not in ("list", "approve", "approve-passed", "reject", "set-aside", "todo"):
        raise SystemExit(__doc__)
    command, rest = args[0], args[1:]
    option = lambda flag: rest[rest.index(flag) + 1] if flag in rest else None
    tile_ids = [a for i, a in enumerate(rest)
                if not a.startswith("--") and (i == 0 or rest[i - 1] not in ("--as", "--why"))]
    acts = command in ("approve", "reject", "set-aside")
    unknown = [t for t in tile_ids if t not in records["tiles"]] if acts else []
    if unknown:
        raise SystemExit(f"No such tile: {unknown}")

    if command == "list":
        show(records, tile_ids[0] if tile_ids else None)
    elif command == "todo":
        todo(records)
    elif command == "approve-passed":
        if len(rest) != 1:
            raise SystemExit("Usage: review.py approve-passed SHEET_ID")
        approve_passed(records, rest[0])
        write_json(RECORDS, records)
    elif command == "approve":
        approve(records, tile_ids, option("--as"))
        write_json(RECORDS, records)
    else:
        if not option("--why"):
            raise SystemExit("Say why with --why \"...\", so we know what to change next time.")
        (reject if command == "reject" else set_aside)(records, tile_ids, option("--why"))
        write_json(RECORDS, records)


if __name__ == "__main__":
    main()
