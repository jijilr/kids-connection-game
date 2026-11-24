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
    held = [k for k, e in catalogue["things"].items() if e["status"] != cat.IN_GAME]
    assert held and not set(held) & set(game)      # recorded, and not in the game's copy


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
        others = {k: e["status"] for k, e in cat.load()["things"].items() if e.get("held_from")}
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
        # what the other scripts hold is untouched
        assert others and all(after["things"][k]["status"] == status for k, status in others.items())
    in_a_copy(test)


def test_which_circles_can_open_is_worked_out_not_set():
    catalogue = cat.load()
    circles = catalogue["worked_out"]["circles"]
    assert circles["seed"]["can_open_now"] and circles["animal"]["can_open_now"]

    # hold two flyers back: Dinosaurs closes by itself, says what it needs, and names what would fill it
    short = copy.deepcopy(catalogue)
    flyers = [k for k, e in short["things"].items()
              if e["status"] == cat.IN_GAME and e["fields"].get("kind_of_dinosaur") == "flyer"]
    for key in flyers[3:]:
        short["things"][key]["status"] = cat.NOT_YET
    cat.work_out(short)
    dinosaurs = short["worked_out"]["circles"]["animal/dinosaur"]
    assert not dinosaurs["can_open_now"] and any("Flyers" in need for need in dinosaurs["needs"])
    # (other dinosaurs may be waiting too, for other groups: only the flyers are looked at here)
    assert {t["name"] for t in dinosaurs["could_be_filled_by"] if t.get("group") == "flyer"} >= {
        short["things"][k]["name"] for k in flyers[3:]}
    assert short["things"][flyers[3]]["worked_out"]["would_join"][-1] == "animal/dinosaur"

    # take the pictures away from a group: the circle closes by itself and says what it needs
    bare = copy.deepcopy(catalogue)
    for entry in bare["things"].values():
        if entry["status"] == cat.IN_GAME and entry["fields"].get("kind_of_plant") == "flower":
            entry["picture"]["game_file"] = None
    cat.work_out(bare)
    plants = bare["worked_out"]["circles"]["plant"]
    assert not plants["can_open_now"] and any("pictures for" in need and "Flowers" in need for need in plants["needs"])
    assert json.dumps(catalogue["worked_out"]) != json.dumps(bare["worked_out"])


# ------------------------------------------------------------------ the map of every place

def test_the_map_on_disk_is_the_map_the_builder_makes_now():
    """Nobody edits Assets/data/places.json, and it is never left behind the data."""
    import places
    on_disk = json.loads(places.PLACES.read_text(encoding="utf-8"))
    fresh = places.build()
    same = lambda m: {k: v for k, v in m.items() if k != "built_on"}
    assert same(on_disk) == same(fresh), "the map is stale: run python tools/catalogue/places.py"
    tree = json.loads(places.TREE.read_text(encoding="utf-8"))["circles"]
    missing = [cid for cid in tree if cid not in fresh["places"]]
    assert missing == [], f"places the job knows that are not on the map: {missing}"
    assert fresh["places"]["seed"]["lies_in"] == {} and fresh["places"]["seed"]["state"] == "ready"
    assert sum(fresh["places_by_state"].values()) == len(fresh["places"])


def test_the_map_names_a_place_by_its_circles_and_asks_a_question_where_it_has_its_home():
    """A small made-up game: kind "a" answers two questions, "sort" and "home"; the things of
    sort s3 do not answer "home" at all, as no dinosaur answers "pet, farm or wild"."""
    import places
    things = {}
    for s in range(4):
        for h in range(4):
            for i in range(4):
                fields = {"kind": "a", "sort": f"s{s}"}
                if s != 3:
                    fields["home"] = f"h{h}"
                things[f"a_{s}{h}{i}"] = {"name": f"a {s} {h} {i}", "fields": fields}
    for k in "bcd":
        for i in range(6):
            things[f"{k}_{i}"] = {"name": f"{k} {i}", "fields": {"kind": k}}
    things["odd"] = {"name": "Odd", "fields": {"kind": ["a", "b"]}}
    dictionary = {"version": 1, "ends": {"b": {"why": "only six such things"}}, "fields": {
        "kind": {"wording": "What kind?", "values": {k: k.upper() for k in "abcd"}},
        "sort": {"wording": "Which sort?", "values": {f"s{i}": f"S{i}" for i in range(4)}},
        "home": {"wording": "Where is its home?", "values": {f"h{i}": f"H{i}" for i in range(4)}},
        "home_again": {"wording": "Where is its home?", "merged_into": "home", "sorts_boards": False,
                       "values": {f"h{i}": f"H{i}" for i in range(4)}}}}
    settings = {"start": {"field": "kind", "label": "Everything"}, "boards_need_pictures": False}
    the_map = places.build(dictionary, things, settings, styles=[], tree={}, words={})["places"]
    asks = lambda name: [a["question"] for a in the_map[name]["asks"]]
    assert asks("seed") == ["kind"], "every thing that answers the others is an a: their home is lower down"
    assert asks("a") == ["sort", "home"], "not every a answers home, but no smaller place holds all that do"
    assert the_map["a"]["asks"][1]["asked_because"] == "its home is here"
    assert asks("a/s0") == ["home"] and asks("a/s3") == [], "nothing of sort s3 answers it"
    # a place is named by its circles in the dictionary's order, whichever road leads to it
    assert the_map["a"]["asks"][1]["kinds"]["h0"]["place"] == "a/h0"
    assert the_map["a/s0"]["asks"][0]["kinds"]["h0"]["place"] == "a/s0/h0"
    assert set(the_map["a/s0/h0"]["lies_in"]) == {"a/s0", "a/h0"}, "it lies in both circles"
    assert the_map["a/s0/h0"]["reached_from"] == ["a/s0"],         "only three sorts answer in h0, so no set there asks for the sort: one road leads here, though two circles hold it"
    assert the_map["a/s0/h0"]["circles"] == [["kind", "a"], ["sort", "s0"], ["home", "h0"]]
    assert "home_again" not in str(the_map["a"]["asks"]), "a merged field is the same question: not seen twice"
    # states: an end is an end whatever else is true of it; a group with no set and no record is a group only
    assert the_map["b"]["state"] == "end" and the_map["b"]["why"] == "only six such things"
    assert the_map["a"]["state"] == "ready" and the_map["a/s0/h0"]["state"] == "a group only" and the_map["a/s0/h0"]["why"]
    # a thing with no single answer is in between: counted, and a place of its own only because it has a thing
    assert the_map["seed"]["asks"][0]["in_between"] == 1 and the_map["in_between"]["things"] == 1
    assert "a/in_between" not in the_map, "an empty overlap is no place"
    # a place that cannot make a set says what it would take: the circle h0 holds three sorts, and a set needs four
    h0 = the_map["a/h0"]
    assert h0["asks"] == [] and h0["state"] == "can be made" and "4 more thing(s)" in h0["why"]
    assert h0["could_ask"] == [{"question": "sort", "wording": "Which sort?", "fill": {"s3": 4}, "more_things_needed": 4}]
    # what the job decided about such a place is kept in the catalogue, and the map carries it
    tried = {"a/h0": {"decisions": [{"date": "2026-11-24", "what": "a run could not fill it", "why": "too few",
                                     "status": "held by the rules", "things_then": h0["things"]}]}}
    held = places.build(dictionary, things, settings, styles=[], tree={}, words={}, decided=tried)["places"]["a/h0"]
    assert held["state"] == "held" and held["why"] == "the rules: too few" and len(held["history"]) == 1
    tried["a/h0"]["decisions"][0]["things_then"] -= 1       # its things have changed since: it may be tried again
    again = places.build(dictionary, things, settings, styles=[], tree={}, words={}, decided=tried)["places"]["a/h0"]
    assert again["state"] == "can be made"


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing real was changed.")


if __name__ == "__main__":
    main()
