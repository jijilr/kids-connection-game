"""Checks the helper's choices and its guard on files. Nothing is served, made or spent.

    python tools/live/selftest.py
"""
import datetime
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import helper


def test_his_best_lines_are_kept_ready_best_first():
    opens = {"animal": True, "animal/mammal": True, "animal/mammal/pet": False, "animal/fish": False,
             "plant": True, "made_by_people": True, "nature_not_alive": True}
    # the owner's walk-through: the best line is not there yet, lesser lines are; it is made at once
    lines = ["animal/mammal/pet", "made_by_people", "nature_not_alive", "plant"]
    assert helper.next_to_make(lines, opens, {}, buffer=3) == "animal/mammal/pet"
    # once his best three are ready nothing more is made: the buffer is three sets, not the whole list
    assert helper.next_to_make(["made_by_people", "nature_not_alive", "plant", "animal/fish"], opens, {}, buffer=3) is None
    assert helper.next_to_make(["made_by_people", "nature_not_alive", "plant", "animal/fish"], opens, {}, buffer=4) == "animal/fish"
    # best first, when two of them are missing
    assert helper.next_to_make(["animal/fish", "animal/mammal/pet", "plant"], opens, {}, buffer=3) == "animal/fish"
    # a set that could not be made, or that is no circle at all, does not take a place in the buffer
    assert helper.next_to_make(["animal/mammal/pet", "plant", "animal", "animal/fish"], opens,
                               {"animal/mammal/pet": "no field"}, buffer=3) == "animal/fish"
    assert helper.next_to_make(["nonsense", "plant", "animal", "animal/fish"], opens, {}, buffer=3) == "animal/fish"
    assert helper.next_to_make([], opens, {}, buffer=3) is None
    assert helper.lines_of({"lines": ["a", 3, "b"]}) == ["a", "b"] and helper.lines_of({}) == [] and helper.lines_of(None) == []


def test_the_days_money_is_counted_by_the_day():
    today = datetime.date(2026, 11, 24)
    ledger = [{"date": "2026-11-23", "spent_inr": 150.0}, {"date": "2026-11-24", "spent_inr": 62.5},
              {"date": "2026-11-24", "spent_inr": 30.0}]
    assert helper.spent_today(ledger, today) == 92.5
    assert helper.spent_today([], today) == 0


def test_only_files_inside_the_folder_are_served():
    with tempfile.TemporaryDirectory() as folder:
        base = pathlib.Path(folder) / "web"
        base.mkdir()
        (base / "index.html").write_text("x", encoding="utf-8")
        (pathlib.Path(folder) / "secret.txt").write_text("x", encoding="utf-8")
        assert helper.inside(base, "index.html") is not None
        assert helper.inside(base, "../secret.txt") is None
        assert helper.inside(base, "missing.html") is None
        assert helper.inside(base, "") is None


def test_the_state_names_what_the_game_needs():
    state = helper.Helper(making=False).state()
    assert state["version"].isdigit() and state["day_cap_inr"] == 200 and state["making"] is None
    assert "Assets/pictures/cow.webp" in state["files"]
    assert any(name.startswith("Assets/audio/names/") for name in state["files"])


def test_what_can_open_and_what_can_never_be_made_is_read_from_the_map():
    places = {"animal": {"state": "ready"}, "animal/wild_land": {"state": "ready"},
              "animal/wild_water": {"state": "can be made", "why": "2 more things"},
              "animal/bird/pet": {"state": "held", "why": "the rules: too few"},
              "nature_not_alive/sky/planet": {"state": "end", "why": "the world holds only 8"},
              "animal/in_between": {"state": "a group only", "why": "no question"}}
    opens, never = helper.can_open_now(places), helper.cannot_be_made(places)
    assert opens["animal/wild_land"] is True, "a place that exists only where circles cross is known now"
    assert opens["animal/wild_water"] is False and "animal/wild_water" not in never, "it can be made: it is wanted"
    assert never == {"animal/bird/pet": "held: the rules: too few",
                     "nature_not_alive/sky/planet": "end: the world holds only 8",
                     "animal/in_between": "a group only: no question"}
    lines = ["nature_not_alive/sky/planet", "animal/bird/pet", "animal/wild_land", "animal/wild_water", "animal"]
    assert helper.next_to_make(lines, opens, never, buffer=3) == "animal/wild_water", \
        "the end and the held place take no room in the buffer; the first of his best three that is not ready is made"
    # and the real map answers for the real places
    real = helper.places_now()
    assert helper.can_open_now(real)["seed"] is True and len(real) > 50


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing served, nothing made, nothing spent.")


if __name__ == "__main__":
    main()
