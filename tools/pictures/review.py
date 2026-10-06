"""The owner's verdict on tiles. This is the only place a tile is linked to a thing.

A tile can be approved only after it was cut cleanly and the vision check has said what
it shows. Approving links it to that thing. Rejecting marks it and keeps the file, so we
know what to draw again.

    python tools/pictures/review.py list [SHEET_ID]
    python tools/pictures/review.py approve TILE_ID... [--as THING_ID]
    python tools/pictures/review.py reject TILE_ID... --why "reason"
    python tools/pictures/review.py todo
"""
import sys

from piclib import RECORDS, load_records, thing_names, today, write_json


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


def reject(records: dict, tile_ids: list, why: str):
    for tile_id in tile_ids:
        records["tiles"][tile_id].update(thing_id=None, review="rejected", review_note=why,
                                         reviewed_on=today())
        print(f"  {tile_id} rejected ({why}); the file is kept")


def todo(records: dict):
    """Things a sheet was meant to draw that still have no approved tile."""
    names = thing_names()
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
    if not args or args[0] not in ("list", "approve", "reject", "todo"):
        raise SystemExit(__doc__)
    command, rest = args[0], args[1:]
    option = lambda flag: rest[rest.index(flag) + 1] if flag in rest else None
    tile_ids = [a for i, a in enumerate(rest)
                if not a.startswith("--") and (i == 0 or rest[i - 1] not in ("--as", "--why"))]
    unknown = [t for t in tile_ids if t not in records["tiles"]] if command in ("approve", "reject") else []
    if unknown:
        raise SystemExit(f"No such tile: {unknown}")

    if command == "list":
        show(records, tile_ids[0] if tile_ids else None)
    elif command == "todo":
        todo(records)
    elif command == "approve":
        approve(records, tile_ids, option("--as"))
        write_json(RECORDS, records)
    else:
        if not option("--why"):
            raise SystemExit("Say why with --why \"...\", so we know what to change next time.")
        reject(records, tile_ids, option("--why"))
        write_json(RECORDS, records)


if __name__ == "__main__":
    main()
