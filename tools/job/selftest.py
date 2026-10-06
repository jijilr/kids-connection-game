"""Checks the job's planning, its rules for fields, who hears of what, and its hard cap.
Offline: nothing is sent, spent or changed. Where a model would be asked, a stand-in answers.

    python tools/job/selftest.py
"""
import copy
import json
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import prepare_next as job          # noqa: E402
from prepare_next import cat, field_rules       # noqa: E402
import expand                       # noqa: E402


def with_changes(change) -> dict:
    """A copy of the catalogue with something changed, worked out again. The real one is not touched."""
    catalogue = copy.deepcopy(cat.load())
    change(catalogue["things"])
    cat.work_out(catalogue)
    return catalogue


def keep_only(things: dict, field: str, value: str, count: int, status: str):
    """Leave `count` things of one group in the game, and give the rest another status."""
    group = [k for k, e in things.items() if e["status"] == cat.IN_GAME and e["fields"].get(field) == value]
    for key in group[count:]:
        things[key]["status"] = status


def small_world() -> tuple:
    """A dictionary and sixteen-odd things made up for the tests: animals, some of them birds."""
    dictionary = {"version": 1, "fields": {
        "kind_of_thing": {"wording": "What kind of thing is it?", "meaning": "everyday", "expected_on": "everything",
                          "values": {"animal": "Animals", "plant": "Plants", "made": "Made things", "nature": "Nature"}},
        "kind_of_animal": {"wording": "What kind of animal is it?", "meaning": "everyday",
                           "expected_on": {"kind_of_thing": "animal"},
                           "values": {"bird": "Birds", "fish": "Fish", "insect": "Insects", "mammal": "Mammals"}},
    }}
    birds = ["Crow", "Parrot", "Duck", "Hen", "Owl", "Eagle", "Swan", "Peacock"]
    things = {cat.slug(n): {"name": n, "fields": {"kind_of_thing": "animal", "kind_of_animal": "bird"}} for n in birds}
    return dictionary, things, [("kind_of_thing", "animal"), ("kind_of_animal", "bird")]


# ------------------------------------------------------------------ the plan

def test_circles_are_planned_by_the_engines_rules_and_nobody_approves_them():
    tree = expand.rebuild(write=False)["circles"]
    plan = job.plan(cat.load())
    planned = [e["circle"] for e in plan["circles"]]
    # only circles the engine calls ready, and in its order: the best score first
    assert planned and all(tree[cid]["status"] in expand.READY for cid in planned)
    scores = [tree[cid]["score"] for cid in planned]
    assert scores == sorted(scores, reverse=True)
    # what a rule or the owner holds back is not planned, and the plan says why
    for cid, circle in tree.items():
        if circle["status"] in ("held", "rejected"):
            assert cid not in planned
            assert any(line.startswith(circle["label"] + ":") for line in plan["held_back"])
    # with two flyers ready but held back on purpose, choosing between them is the owner's to do, not the job's
    held = with_changes(lambda things: keep_only(things, "kind_of_dinosaur", "flyer", 3, cat.NOT_YET))
    blocked = job.plan(held, rehearse="animal/dinosaur")
    assert blocked["asks"] == []
    assert any("Flyers" in line and "deliberately not in the game yet" in line for line in blocked["blocked"])


def test_with_saved_progress_only_one_step_ahead_of_the_child_is_planned():
    everywhere = {e["circle"] for e in job.plan(cat.load())["circles"]}
    at_the_seed = {e["circle"] for e in job.plan(cat.load(), played={"seed"})["circles"]}
    in_animals = {e["circle"] for e in job.plan(cat.load(), played={"seed", "animal"})["circles"]}
    assert at_the_seed <= in_animals <= everywhere
    assert all("/" not in cid for cid in at_the_seed)                  # the seed's own groups, nothing deeper
    assert all(cid.rsplit("/", 1)[0] in ("animal",) or "/" not in cid for cid in in_animals)
    # the file a grown-up saves from the game is read as the boards he has opened
    with tempfile.TemporaryDirectory() as folder:
        saved = pathlib.Path(folder) / "progress.json"
        saved.write_text(json.dumps({"version": 1, "boards": {"seed": {"opened": 3, "solved": 2},
                                                              "animal": {"opened": 1, "solved": 0},
                                                              "plant": {"opened": 0, "solved": 0}}}), encoding="utf-8")
        assert job.read_progress(saved) == {"seed", "animal"}
        assert job.read_progress(pathlib.Path(folder) / "none.json") is None


def test_a_rehearsal_plans_the_circle_named_and_nothing_else():
    one_building = with_changes(lambda things: keep_only(things, "kind_of_made_thing", "building", 1, cat.TAKEN_OUT))
    plan = job.plan(one_building, rehearse="made_by_people/building")
    assert len(plan["asks"]) == 1 and plan["circles"] == []
    ask = plan["asks"][0]
    assert ask["fixed"] == {"kind_of_thing": "made_by_people", "kind_of_made_thing": "building"}
    assert ask["need"] == 3 and ask["chain"] == "Things people make > Buildings"
    # a rehearsal never adds a field
    no_field = job.plan(cat.load(), rehearse="animal/mammal")
    assert no_field["asks"] == [] and any("A rehearsal does not add one" in line for line in no_field["blocked"])


def test_a_thing_in_the_game_without_a_picture_is_planned_for_drawing():
    bare = with_changes(lambda things: things["cup"]["picture"].update(game_file=None))
    # a real run draws it whatever its circle; a rehearsal only inside the circle named
    drawn_for = lambda plan: [name for a in plan["asks"] for name in a.get("pictures_for", [])]
    assert "Cup" in drawn_for(job.plan(bare))
    assert "Cup" in drawn_for(job.plan(bare, rehearse="made_by_people"))
    assert "Cup" not in drawn_for(job.plan(bare, rehearse="plant"))


# ------------------------------------------------------------------ a field is decided by four tests

def stand_in(sorting: dict, checking: dict = None, not_birds: tuple = ()):
    """In place of the sorting calls: the parent's answer, and the checker's. Asked what
    kind of animal each new name is, it says a bird, except for those in `not_birds`."""
    def ask(client, config, spend, system, user, options=None):
        if "What kind of animal is it?" in user:
            kind = {name: "fish" if name in not_birds else "bird" for name in sorting}
            return kind if system == field_rules.SORTER else {name: [value] for name, value in kind.items()}
        if system == field_rules.SORTER:
            return dict(sorting)
        return {**{name: [value] for name, value in sorting.items()}, **(checking or {})}
    return ask


def know_all(client, config, spend, ask, offers):
    for o in offers:
        o.update(recognised=True, suitable=True, familiar=0.9)


def candidate() -> dict:
    """Birds by where we see them: a field that should pass on the made-up world."""
    return {"key": "where_we_see_it", "wording": "Where do we see it?", "values": [
        {"key": "sky", "label": "High in the sky", "members": ["Eagle", "Crow"], "new": ["Kite", "Vulture", "Hawk"]},
        {"key": "water", "label": "On the water", "members": ["Duck", "Swan"], "new": ["Goose", "Pelican", "Flamingo"]},
        {"key": "yard", "label": "In the yard", "members": ["Hen", "Peacock"], "new": ["Rooster", "Turkey", "Pigeon"]},
        {"key": "trees", "label": "In the trees", "members": ["Parrot", "Owl"], "new": ["Woodpecker", "Mynah", "Sparrow"]}]}


def run_test(sorting_changes: dict = None, checking: dict = None, recognise=know_all, change=None,
             not_birds: tuple = ()) -> dict:
    dictionary, things, path = small_world()
    field = candidate()
    if change:
        change(dictionary, things, field)
    sorting = {name: v["key"] for v in field["values"] for name in v["members"] + v["new"]}
    sorting.update(sorting_changes or {})
    real, field_rules.reslib.ask = field_rules.reslib.ask, stand_in(sorting, checking, not_birds)
    try:
        return field_rules.test(None, {"model": "x", "thinking": "off"}, None, dictionary, things, set(things), path,
                                "Animals > Birds", field, recognise, 0.5)
    finally:
        field_rules.reslib.ask = real


def test_a_field_that_passes_all_four_tests_is_accepted():
    result = run_test()
    assert result["why"] == [], result["why"]
    assert result["counts"] == {"sky": 5, "water": 5, "yard": 5, "trees": 5}
    assert result["placed"]["eagle"] == "sky" and len(result["placed"]) == 8      # every thing already there has its value
    assert result["definition"]["expected_on"] == {"kind_of_animal": "bird"}
    assert set(result["new"]) >= {"Kite", "Goose", "Rooster", "Woodpecker"}


def test_a_value_without_four_familiar_things_fails():
    def few_know(client, config, spend, ask, offers):
        for o in offers:       # nobody knows the water birds that were suggested
            o.update(recognised=o["value"] != "water", suitable=True, familiar=0.9)
    result = run_test(recognise=few_know)
    assert len(result["why"]) == 1 and "'On the water' has 2" in result["why"][0]


def test_a_suggested_name_that_is_not_a_thing_of_the_circle_does_not_count():
    # the water birds that were suggested turn out not to be birds at all: the value is left with two
    result = run_test(not_birds=("Goose", "Pelican", "Flamingo"))
    assert "'On the water' has 2" in result["why"][0]
    assert result["not_of_this_circle"] == ["Goose", "Pelican", "Flamingo"]


def test_groups_with_no_sharp_edges_fail():
    def crow_moved(dictionary, things, field):         # the proposer says the yard; both checks say the sky
        field["values"][0]["members"].remove("Crow")
        field["values"][2]["members"].append("Crow")
    # one thing in twenty placed otherwise than the proposer said: the checks' value stands, and the field passes
    one = run_test(sorting_changes={"Crow": "sky"}, change=crow_moved)
    assert one["why"] == [] and one["placed"]["crow"] == "sky" and one["sharpness"] == 0.95
    # four in twenty: these are not groups a child could tell apart
    many = run_test(sorting_changes={"Crow": "sky", "Kite": "trees", "Goose": "yard", "Rooster": "sky"}, change=crow_moved)
    assert "its groups have no sharp edges" in many["why"][0] and "only 80%" in many["why"][0]


def test_a_few_things_may_fit_two_groups_and_then_stay_off_the_board():
    # one bird in eight fits two groups: allowed. It lists both, is not counted in either, and the field passes
    one = run_test(checking={"Duck": ["water", "yard"]})
    assert one["why"] == [], one["why"]
    assert one["several"] == {"duck": ["water", "yard"]} and "duck" not in one["placed"]
    assert one["counts"]["water"] == 4                          # Swan and three new ones, without the duck
    # two in eight: too many
    two = run_test(checking={"Duck": ["water", "yard"], "Hen": ["yard", "trees"]})
    assert "2 of the 8 things there fit more than one group, and at most 1 may" in two["why"][0]
    # a thing that fits no group cannot be recorded at all
    none = run_test(sorting_changes={"Owl": "none"}, checking={"Owl": []})
    assert "not every thing has a value: Owl - it fits no group" in none["why"][0]
    # the two checks each give one value, but not the same one: it has no single value
    names = ["Crow"]
    placed, unclear = field_rules.one_value_each(names, {"Crow": "sky"}, {"Crow": ["trees"]}, ["sky", "trees"])
    assert placed == {} and "the two checks disagree" in unclear["Crow"]
    assert field_rules.values_named("Crow", {"Crow": "sky"}, {"Crow": ["trees"]}, ["sky", "trees"]) == ["sky", "trees"]
    placed, unclear = field_rules.one_value_each(names, {"Crow": "sky"}, {"Crow": ["sky"]}, ["sky", "trees"])
    assert placed == {"Crow": "sky"} and unclear == {}
    # a check may name a group by its label instead of its key
    placed, _ = field_rules.one_value_each(names, {"Crow": "High in the sky"}, {"Crow": ["sky"]}, ["sky", "trees"],
                                           {"sky": "High in the sky", "trees": "In the trees"})
    assert placed == {"Crow": "sky"}


def test_a_field_that_repeats_an_existing_one_fails():
    def same_question(dictionary, things, field):
        field["wording"] = "What kind of animal is it"         # the same words, but for a question mark
    assert "it asks the same question as 'kind_of_animal'" in run_test(change=same_question)["why"][0]

    def same_groups(dictionary, things, field):
        for value, label in zip(field["values"], ("Birds", "Fish", "Insects", "Other animals")):
            value["label"] = label
    assert "its groups are those of 'kind_of_animal'" in run_test(change=same_groups)["why"][0]

    def same_split(dictionary, things, field):                 # an existing field already splits the birds this way
        dictionary["fields"]["home"] = {"wording": "Where is its home?", "meaning": "everyday",
                                        "expected_on": {"kind_of_animal": "bird"},
                                        "values": {"a": "Up above", "b": "Wet places", "c": "Near people", "d": "Woods"}}
        for name, value in {"Eagle": "a", "Crow": "a", "Duck": "b", "Swan": "b", "Hen": "c", "Peacock": "c",
                            "Parrot": "d", "Owl": "d"}.items():
            things[cat.slug(name)]["fields"]["home"] = value
    assert "it splits these things the way 'home' already does" in run_test(change=same_split)["why"][0]


def test_a_field_whose_boards_sort_another_way_as_well_fails():
    dictionary, things, path = small_world()
    # every bird also carries a size, and the sizes fall exactly with the new groups in the trial
    dictionary["fields"]["size"] = {"wording": "How big is it?", "meaning": "everyday", "expected_on": "everything",
                                    "values": {"s": "Small", "m": "Middling", "l": "Large", "xl": "Very large"}}
    birds = sorted(things)
    for i, key in enumerate(birds):
        things[key]["fields"]["size"] = ("s", "m", "l", "xl")[i // 2]
    more = {f"Bird {i}": ("s", "m", "l", "xl")[i // 2] for i in range(8)}
    for name, size in more.items():
        things[cat.slug(name)] = {"name": name, "fields": {"kind_of_thing": "animal", "kind_of_animal": "bird", "size": size}}
    placed = {key: {"s": "sky", "m": "water", "l": "yard", "xl": "trees"}[t["fields"]["size"]] for key, t in things.items()}
    definition = {"wording": "Where do we see it?", "meaning": "everyday", "expected_on": {"kind_of_animal": "bird"},
                  "values": {"sky": "High in the sky", "water": "On the water", "yard": "In the yard", "trees": "In the trees"}}
    assert "also sort cleanly by another field" in field_rules.boards_clean(
        dictionary, things, path, "where_we_see_it", definition, placed, {}, 0.5)
    # and the same split is caught as a synonym before that
    assert "the way 'size' already does" in field_rules.synonym_of(
        dictionary, things, placed, {"wording": "Where do we see it?", "values": [{"label": l} for l in definition["values"].values()]})
    # when the sizes no longer fall four by four, there is one clean solution
    for i, key in enumerate(sorted(things)):
        things[key]["fields"]["size"] = "s" if i < 10 else "m"
    assert field_rules.boards_clean(dictionary, things, path, "where_we_see_it", definition, placed, {}, 0.5) == ""


def test_a_malformed_field_is_refused_before_anything_is_asked():
    dictionary, _, _ = small_world()
    three = candidate()
    three["values"].pop()
    assert "it has 3 values, not four" in field_rules.shape_problems(three, dictionary)
    assert field_rules.shape_problems(candidate(), dictionary) == []
    assert field_rules.unique_key(dictionary, "kind_of_animal", [("kind_of_animal", "bird")]) == "kind_of_animal_of_bird"


# ------------------------------------------------------------------ who hears of what

def test_the_owner_hears_only_of_the_unsuitable_and_the_unsettled():
    thing = lambda **more: {"name": "X", "passed": False, "why": ["a reason"], **more}
    who = lambda t, rehearsal=False: job.held_as(t, "2026-10-07-01", rehearsal)[0]
    assert who(thing(for_owner=True)) == cat.WAITING                       # unsuitable, or two checks disagree
    assert who(thing(not_recognised=True)) == cat.RULES                    # a four-year-old would not know it
    assert who(thing()) == cat.RULES                                       # its facts could not be grounded
    assert who(thing(passed=True, why=[])) == cat.RULES                    # no picture of it passed
    assert who(thing(not_needed=True)) == ""                               # a sound thing of another group
    assert who(thing(passed=True, tile="t1", why=[])) == ""                # going into the game
    assert who(thing(passed=True, tile="t1", why=[]), rehearsal=True) == cat.WAITING     # a rehearsal holds it for him
    # the rules' own queue is kept apart from his
    view = cat.queue_view({"things": {"a": {"name": "A", "status": cat.RULES, "status_why": ["unfamiliar"]},
                                      "b": {"name": "B", "status": cat.WAITING, "status_why": ["uncertain"]}}})
    assert [e["name"] for e in view["for_the_owner"]] == ["B"]
    assert [e["name"] for e in view["held_by_the_rules"]] == ["A"]


def test_the_digest_says_what_was_done_and_how_to_take_it_back():
    budget = job.Budget(cap_inr=200, rate=100)
    budget.add("drawing", 0.5)
    run = {"id": "2026-10-07-01", "rehearse": None, "stopped": "", "sheets": ["s1"], "opened": ["Water"],
           "plan": {"circles": [{"label": "Water", "done": True}, {"label": "Birds"}], "blocked": [], "played": None},
           "fields_added": [{"label": "Water", "wording": "Where is the water?", "filled": 4, "field": "where",
                             "values": {"a": "In the sky", "b": "On the ground", "c": "In the house", "d": "Under the ground"}}],
           "fields_held": [{"label": "Rocks and soil", "tried": [{"wording": "How hard is it?", "why": ["'Soft' has 2"]}]}],
           "things": [{"name": "Tap", "passed": True, "tile": "t1", "why": []},
                      {"name": "Geyser", "passed": False, "why": ["the check doubts a four-year-old would recognise it"],
                       "held_as": cat.RULES},
                      {"name": "Well", "passed": False, "why": ["uncertain: two checks could not settle it"],
                       "held_as": cat.WAITING}]}
    text = "\n".join(job.digest(run, budget))
    assert "Circles opened: Water." in text
    assert 'Fields added: "Where is the water?" for Water' in text and "filled in on 4 things" in text
    assert "Things added: 1: Tap." in text and "Cost: Rs 50.0 of a hard cap of Rs 200" in text
    assert "Rocks and soil: no field passed the tests" in text and "Geyser (the check doubts" in text
    assert "For you: \n  - Well: uncertain" in text.replace("For you: \n", "For you: \n")
    assert "Left for a later run, in this order: Birds." in text
    assert text.endswith("To take this run back: python tools/prepare_next.py --undo 2026-10-07-01")


# ------------------------------------------------------------------ the money

def test_the_cap_is_hard():
    budget = job.Budget(cap_inr=20, rate=100)          # twenty rupees is 0.20 dollars
    budget.need(0.15, "a sheet")                       # fits
    budget.add("drawing", 0.15)
    try:
        budget.need(0.06, "a second sheet")            # 0.15 + 0.06 would pass 0.20
        refused = False
    except job.Stop as stop:
        refused = "only Rs 5 of the cap is left" in str(stop)
    assert refused
    budget.need(0.05, "a small check")                 # exactly what is left still fits
    assert abs(budget.used - 0.15) < 1e-9 and "Rs 15.0 of a hard cap of Rs 20" in budget.line()


def test_a_run_takes_only_the_circles_its_cap_can_cover():
    circle = lambda things, field=True: {"expect_things": things, "needs_field": field}
    plan = lambda *circles: {"asks": [], "circles": list(circles)}
    assert job.expected_cost(plan(), 96, 200) == (0.0, 0)
    one, fit_one = job.expected_cost(plan(circle(16)), 96, 200)
    many, fit_many = job.expected_cost(plan(*[circle(16)] * 8), 96, 200)
    assert 0 < one < many <= 200 * job.SHARE_OF_CAP and fit_one == 1 and 1 < fit_many < 8
    assert job.expected_cost(plan(*[circle(16)] * 8), 96, 40)[1] < fit_many      # a smaller cap covers fewer


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing sent, nothing spent, nothing changed.")


if __name__ == "__main__":
    main()
