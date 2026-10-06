"""Checks the catalogue's own rules, offline. Nothing real is changed: every write goes
to copies in a temporary folder. The dictionary, pictures and tile records are only read.

    python tools/catalogue/selftest.py
"""
import copy
import json
import pathlib
import shutil
import tempfile

import catalogue as cat


def in_a_copy(test):
    """Run a test with the catalogue, the game's copy and the queue copied to a temporary
    folder, so the real three are never touched."""
    real = (cat.CATALOGUE, cat.THINGS, cat.QUEUE, cat.LOCK, cat.HERE)
    with tempfile.TemporaryDirectory() as folder:
        folder = pathlib.Path(folder)
        for name, path in (("catalogue.json", cat.CATALOGUE), ("things.json", cat.THINGS), ("queue.json", cat.QUEUE)):
            shutil.copyfile(path, folder / name)
        cat.CATALOGUE, cat.THINGS, cat.QUEUE = folder / "catalogue.json", folder / "things.json", folder / "queue.json"
        cat.LOCK, cat.HERE = folder / "catalogue.lock", folder
        try:
            test()
        finally:
            cat.CATALOGUE, cat.THINGS, cat.QUEUE, cat.LOCK, cat.HERE = real


def test_the_real_catalogue_is_sound():
    assert cat.problems(cat.load()) == []


def test_the_games_copy_holds_only_things_in_the_game_and_only_what_the_game_needs():
    catalogue = cat.load()
    game = cat.game_copy(catalogue)["things"]
    assert set(game) == {k for k, e in catalogue["things"].items() if e["status"] == cat.IN_GAME}
    assert all(set(thing) <= set(cat.GAME_KEYS) for thing in game.values())
    assert "rhamphorhynchus" in catalogue["things"] and "rhamphorhynchus" not in game


def test_the_guard_catches_what_goes_wrong():
    sound = cat.load()

    def wrong_after(change) -> str:
        broken = copy.deepcopy(sound)
        change(broken["things"])
        return " | ".join(cat.problems(broken, about_to_save=True))

    assert "not an allowed value" in wrong_after(lambda t: t["lion"]["fields"].update(kind_of_animal="fishy"))
    assert "missing 'kind_of_animal'" in wrong_after(lambda t: t["lion"]["fields"].pop("kind_of_animal"))
    assert "fingerprint differs" in wrong_after(lambda t: t["lion"]["picture"].update(game_sha256="0" * 64))
    assert "is not there" in wrong_after(lambda t: t["lion"]["picture"].update(game_file="Assets/pictures/no_such.webp"))
    assert "no entry names it" in wrong_after(lambda t: t["lion"].pop("picture"))
    assert "named by more than one entry" in wrong_after(
        lambda t: t["tiger"]["picture"].update(game_file=t["lion"]["picture"]["game_file"],
                                               game_sha256=t["lion"]["picture"]["game_sha256"]))
    assert "not an approved tile for it" in wrong_after(
        lambda t: t["lion"]["picture"].update(tile=t["tiger"]["picture"]["tile"]))
    assert "is not a status" in wrong_after(lambda t: t["lion"].update(status="somewhere"))


def test_an_edit_to_the_games_copy_is_noticed():
    def test():
        store = cat.read_json(cat.THINGS)
        store["things"]["lion"]["fields"]["kind_of_animal"] = "bird"
        cat.write_json(cat.THINGS, store)
        assert any("someone edited the game's copy" in line for line in cat.problems(cat.load()))
    in_a_copy(test)


def test_a_change_keeps_each_things_place_and_what_it_has():
    def test():
        before = cat.load()
        store = cat.game_store()
        store["things"]["lion"]["familiar"] = 0.5
        moved = {"things": dict(reversed(list(store["things"].items()))),      # a script that reorders
                 "dictionary_version": store["dictionary_version"]}
        cat.put_game_store(moved, by="selftest")
        after = cat.load()
        assert list(after["things"]) == list(before["things"])                 # every thing kept its place
        assert after["things"]["lion"]["familiar"] == 0.5
        assert after["things"]["lion"]["picture"] == before["things"]["lion"]["picture"]
        assert after["things"]["lion"]["sources"] == before["things"]["lion"]["sources"]
        assert cat.read_json(cat.THINGS)["things"]["lion"]["familiar"] == 0.5  # the game's copy followed
        assert cat.problems(after) == []
    in_a_copy(test)


def test_nothing_is_ever_deleted():
    def test():
        store = cat.game_store()
        del store["things"]["lion"]
        try:
            cat.put_game_store(store, by="selftest")
            saved = True
        except SystemExit:
            saved = False      # its published picture would be left with no entry in the game: refused
        after = cat.load()
        assert "lion" in after["things"]
        assert after["things"]["lion"]["status"] in (cat.IN_GAME, cat.TAKEN_OUT)
        assert saved or after["things"]["lion"]["status"] == cat.IN_GAME
    in_a_copy(test)


def test_the_queue_is_a_view_of_what_is_held():
    def test():
        cat.set_queue("check:selftest", [{"name": "Glow-worm", "fields": {"kind_of_thing": "animal"},
                                          "familiar": 0.4, "why": ["the checker doubts a four-year-old would recognise it"]}])
        after = cat.load()
        assert after["things"]["glow_worm"]["status"] == cat.WAITING
        held = cat.read_json(cat.QUEUE)["for_the_owner"]
        assert held[-1] == {"name": "Glow-worm", "fields": {"kind_of_thing": "animal"}, "familiar": 0.4,
                            "why": ["the checker doubts a four-year-old would recognise it"], "from": "check:selftest"}
        assert after["things"]["glow_worm"]["worked_out"]["would_join"] == ["seed", "animal"]
        cat.set_queue("check:selftest", [])                    # the script no longer holds it
        after = cat.load()
        assert after["things"]["glow_worm"]["status"] == cat.TAKEN_OUT and "glow_worm" in after["things"]
        assert all(e["name"] != "Glow-worm" for e in cat.read_json(cat.QUEUE)["for_the_owner"])
        assert after["things"]["salamander"]["status"] == cat.WAITING      # another script's entry is untouched
    in_a_copy(test)


def test_which_circles_can_open_is_worked_out_not_set():
    catalogue = cat.load()
    circles = catalogue["worked_out"]["circles"]
    assert circles["seed"]["can_open_now"] and circles["animal"]["can_open_now"]
    dinosaurs = circles["animal/dinosaur"]
    assert not dinosaurs["can_open_now"] and any("Flyers" in need for need in dinosaurs["needs"])
    assert {t["name"] for t in dinosaurs["could_be_filled_by"]} == {"Rhamphorhynchus", "Dimorphodon"}

    # take the pictures away from a group: the circle closes by itself and says what it needs
    bare = copy.deepcopy(catalogue)
    for entry in bare["things"].values():
        if entry["status"] == cat.IN_GAME and entry["fields"].get("kind_of_plant") == "flower":
            entry["picture"]["game_file"] = None
    cat.work_out(bare)
    plants = bare["worked_out"]["circles"]["plant"]
    assert not plants["can_open_now"] and any("pictures for" in need and "Flowers" in need for need in plants["needs"])
    assert json.dumps(catalogue["worked_out"]) != json.dumps(bare["worked_out"])


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing real was changed.")


if __name__ == "__main__":
    main()
