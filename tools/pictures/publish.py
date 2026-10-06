"""Put the approved tiles into the game.

Copies the game's version (the small WebP) of every approved tile to
Assets/pictures/<thing id>.webp, which is where the game looks. Only approved tiles go
in; a file there whose tile is no longer approved is removed, so the folder always
matches the owner's review. Masters and original sheets stay where they are.

    python tools/pictures/publish.py
"""
import shutil

from piclib import RECORDS, ROOT, load_records, relative, thing_names, write_json

GAME = ROOT / "Assets/pictures"


def main():
    records = load_records()
    names = thing_names()
    chosen = {}
    for tile_id, tile in records["tiles"].items():
        tile.pop("published_file", None)
        if tile["review"] != "approved":
            continue
        thing = tile["thing_id"]
        if thing in chosen:
            raise SystemExit(f"Two approved tiles for {names.get(thing, thing)}: {chosen[thing]} and "
                             f"{tile_id}. Reject or set aside one of them. Nothing was changed.")
        chosen[thing] = tile_id

    GAME.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for thing, tile_id in chosen.items():
        target = GAME / f"{thing}.webp"
        shutil.copyfile(ROOT / records["tiles"][tile_id]["app_file"], target)
        records["tiles"][tile_id]["published_file"] = relative(target)
        wanted.add(target.name)
    removed = [p.name for p in GAME.glob("*.webp") if p.name not in wanted]
    for name in removed:
        (GAME / name).unlink()
    write_json(RECORDS, records)
    print(f"{len(chosen)} approved tiles are in the game ({relative(GAME)}).")
    if removed:
        print(f"Removed, because their tiles are no longer approved: {', '.join(removed)}")


if __name__ == "__main__":
    main()
