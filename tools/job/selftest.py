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
import prepare_next as job          # noqa: E402  (it puts the other tool folders on the path)
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
    # only circles the engine calls ready; ONE for each board, and that one the best of its board
    assert all(tree[cid]["status"] in expand.READY for cid in planned)
    parent = lambda cid: cid.rsplit("/", 1)[0] if "/" in cid else "seed"
    assert len({parent(cid) for cid in planned}) == len(planned)
    for cid in planned:
        beside = [c for c in tree if parent(c) == parent(cid) and tree[c]["status"] in expand.READY]
        assert tree[cid]["score"] == max(tree[c]["score"] for c in beside)
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


def test_an_order_is_one_group_for_each_board_and_the_stuck_boards_come_first():
    circle = lambda open_, score=0.0: {"open": open_, "score": score, "move": "widening",
                                       "status": "open" if open_ else "proposable"}
    tree = {"seed": circle(True), "a": circle(True), "b": circle(True), "c": circle(True),
            "a/x": circle(False, 3.0), "a/y": circle(False, 2.0),          # nothing inside a is open: he would be stuck
            "b/x": circle(False, 5.0), "b/z": circle(True),                # b has somewhere deeper to go
            "c/x": circle(False, 1.0), "c/held": dict(circle(False, 9.0), status="held")}
    first, waiting = job.orders(tree)
    assert first == ["a/x", "c/x", "b/x"]              # one for each board; stuck boards first, then by the balance
    assert waiting == ["a/y"]                          # the second group of a board waits its turn
    assert "c/held" not in first + waiting             # what a rule or the owner holds is never ordered
    # a board the child really solved with nowhere to go is served before all the others
    assert job.orders(tree, asked={"b"})[0][0] == "b/x"
    # with saved progress, only the boards he has opened are served
    assert job.orders(tree, played={"seed", "c"})[0] == ["c/x"]
    # the game writes its orders into the saved progress file, and the job reads them
    with tempfile.TemporaryDirectory() as folder:
        saved = pathlib.Path(folder) / "progress.json"
        saved.write_text(json.dumps({"version": 1, "boards": {"seed": {"opened": 2}},
                                     "orders": {"made_by_people/vehicle": {"solved": 1}}}), encoding="utf-8")
        assert job.read_orders(saved) == {"made_by_people/vehicle"}
        assert job.read_orders(pathlib.Path(folder) / "none.json") == set()


def test_four_orders_in_five_go_where_he_has_shown_mastery():
    """The owner's ruling of 23 Nov 2026: deeper where he has shown mastery, four in five."""
    assert job.four_in_five(list("SSSSSSSS"), list("ooo"), 0.8) == list("SSSSoSSSSoo")
    assert job.four_in_five(list("SS"), list("oooo"), 0.8) == list("SSoooo")     # one list runs out: the other goes on
    assert job.four_in_five([], list("oo"), 0.8) == list("oo")
    circle = lambda open_, score=0.0, **more: dict({"open": open_, "score": score, "move": "widening",
                                                    "status": "open" if open_ else "proposable"}, **more)
    tree = {"seed": circle(True), "a": circle(True), "b": circle(True), "c": circle(True), "d": circle(True),
            "e": circle(True), "f": circle(True),
            "a/x": circle(False, 1.0), "b/x": circle(False, 2.0), "c/x": circle(False, 3.0),
            "d/x": circle(False, 4.0), "e/x": circle(False, 5.0), "f/x": circle(False, 6.0),
            "a/y": circle(False, 0.5, status="held", held_by="depth gap: its branch would be 2 levels deep"),
            "b/y": circle(False, 0.5, status="held", held_by="the owner: not yet")}
    plain, _ = job.orders(tree)
    assert plain == ["f/x", "e/x", "d/x", "c/x", "b/x", "a/x"]        # without mastery: as before, by the balance
    first, _ = job.orders(tree, mastered={"a", "b", "c", "d", "e"}, share=0.8)
    strong = lambda cid: cid.split("/")[0] in {"a", "b", "c", "d", "e"}
    assert [strong(c) for c in first[:5]] == [True, True, True, True, False]
    assert "f/x" == first[4]                                           # the one in five: what he has not mastered
    # inside what he has mastered the depth gap does not hold a circle back; the owner's own hold still does
    first, waiting = job.orders(tree, mastered={"a"})
    assert "a/y" in first + waiting and "b/y" not in first + waiting
    # with saved progress, the boards inside what he has mastered are served too: the game sends him there
    assert job.orders(tree, played={"seed", "c"}, mastered={"e"})[0] == ["e/x", "c/x"]
    # a circle whose own group he has mastered goes first on its board
    first, waiting = job.orders(dict(tree, **{"a/z": circle(False, 0.1)}), mastered={"a/z"})
    assert first[0] == "a/z" and "a/x" in waiting
    # the game keeps the lines to follow in the saved progress; the job reads them
    with tempfile.TemporaryDirectory() as folder:
        saved = pathlib.Path(folder) / "progress.json"
        saved.write_text(json.dumps({"version": 3, "boards": {"seed": {"opened": 3}},
                                     "groups": {"animal": {"found": 3, "clean": 3}, "plant": {"found": 2, "clean": 0}},
                                     "lines": ["animal/mammal", "animal"]}), encoding="utf-8")
        assert job.read_mastery(saved) == {"animal", "animal/mammal"}
        old = pathlib.Path(folder) / "old.json"
        old.write_text(json.dumps({"version": 1, "boards": {"seed": {"opened": 1}}}), encoding="utf-8")
        assert job.read_mastery(old) == set()                           # saved before the game kept lines
        assert job.read_mastery(pathlib.Path(folder) / "none.json") == set()
    assert job.deeper_share() == 0.8                                    # the same number the game uses


def test_make_board_gives_sixteen_things_in_four_groups_with_one_solution_or_nothing():
    from boards import make_board, second_solution
    catalogue = cat.load()
    dictionary, things = cat.read_json(cat.DICTIONARY), cat.game_copy(catalogue)["things"]
    raw = job.build_circles(dictionary, things, cat.read_json(cat.SETTINGS))
    made = 0
    for cid, circle in raw.items():
        path = cat.circle_path(raw, cid)
        board = make_board(dictionary, things, path, circle.get("sorted_by"))
        if not circle["open"]:
            if not circle.get("sorted_by"):
                assert make_board(dictionary, things, path) is None        # no field: no board, never a shallower one
            continue
        made += 1
        assert len(board["tiles"]) == 16 and len(set(board["tiles"])) == 16 and len(board["groups"]) == 4
        assert all(len(group) == 4 for group in board["groups"].values())
        assert all(things[k]["fields"][board["field"]] == value for value, group in board["groups"].items() for k in group)
        assert second_solution(dictionary, things, board["tiles"], board["field"]) is None
        again = make_board(dictionary, things, path, circle.get("sorted_by"), avoid=set(board["tiles"]))
        groups = job.split(things, job.members(things, path), board["field"])
        only_one = sum(len(g) for g in groups.values() if len(g) >= 4) == 16     # four groups of exactly four
        assert only_one or set(again["tiles"]) != set(board["tiles"])       # a fresh board is not the same sixteen
    assert made >= 9


def test_a_rehearsal_plans_the_circle_named_and_nothing_else():
    one_building = with_changes(lambda things: keep_only(things, "kind_of_made_thing", "building", 1, cat.TAKEN_OUT))
    plan = job.plan(one_building, rehearse="made_by_people/building")
    assert len(plan["asks"]) == 1 and plan["circles"] == []
    ask = plan["asks"][0]
    assert ask["fixed"] == {"kind_of_thing": "made_by_people", "kind_of_made_thing": "building"}
    assert ask["need"] == 3 and ask["chain"] == "Things people make > Buildings"
    # a rehearsal never adds a field (tried on whichever circle lacks one today)
    for cid in [e["circle"] for e in job.plan(cat.load())["circles"] if e["needs_field"]][:1]:
        no_field = job.plan(cat.load(), rehearse=cid)
        assert no_field["asks"] == [] and any("A rehearsal does not add one" in line for line in no_field["blocked"])


def test_a_thing_in_the_game_without_a_picture_is_planned_for_drawing():
    bare = with_changes(lambda things: things["cup"]["picture"].update(game_file=None))
    # a real run draws it whatever its circle; a rehearsal only inside the circle named
    drawn_for = lambda plan: [name for a in plan["asks"] for name in a.get("pictures_for", [])]
    assert "Cup" in drawn_for(job.plan(bare))
    assert "Cup" in drawn_for(job.plan(bare, rehearse="made_by_people"))
    assert "Cup" not in drawn_for(job.plan(bare, rehearse="plant"))


# ------------------------------------------------------------------ every thing drawn from its sources

def test_no_kind_of_thing_is_named_in_the_job():
    """The owner's ruling of 24 Nov 2026: no hard-coding. The job treats every circle alike,
    so no field or value of the dictionary may appear in its code as a special case."""
    import ast

    def code_lines(path) -> list:
        """The lines that run: no descriptions, no comments."""
        text = pathlib.Path(path).read_text(encoding="utf-8")
        described = set()
        for node in ast.walk(ast.parse(text)):
            body = getattr(node, "body", None)
            if (isinstance(node, (ast.Module, ast.FunctionDef, ast.ClassDef)) and body and isinstance(body[0], ast.Expr)
                    and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str)):
                described.update(range(body[0].lineno, body[0].end_lineno + 1))
        return [line.split("  #")[0] for n, line in enumerate(text.splitlines(), 1)
                if n not in described and not line.lstrip().startswith("#")]

    code = code_lines(job.__file__) + code_lines(job.looks.__file__)
    for word in ("kind_of_dinosaur", "dinosaur", "prehistoric", '"extinct"', "kind_of_animal", "kind_of_plant"):
        lines = [line for line in code if word in line]
        assert not lines, f"the job names '{word}': {lines[0].strip()}"
    # and no circle is held back by what it is: nothing in the plan says a kind cannot be prepared
    assert not [line for line in job.plan(cat.load())["blocked"] if "prehistoric" in line]


def test_a_look_keeps_only_what_a_page_says_word_for_word_and_a_picture_can_show():
    looks = job.looks
    page = ("The kingfisher has a large head, a long, sharp, pointed bill and short legs. "
            "Its back is bright blue. It eats small fish that it catches in rivers.")
    sources = [{"id": "wikipedia_en", "title": "Kingfisher", "text": page}]
    def ask(client, config, spend, system, user, options=None):
        if system == looks.READER:
            return {"features": [
                {"claim": "It has a long, sharp bill.", "quote": "a long, sharp, pointed bill", "source": "wikipedia_en"},
                {"claim": "Its back is bright blue.", "quote": "Its back is bright blue.", "source": "wikipedia_en"},
                {"claim": "It has a red crest.", "quote": "It has a red crest", "source": "wikipedia_en"},    # no such sentence
                {"claim": "It eats fish.", "quote": "It eats small fish that it catches in rivers.", "source": "wikipedia_en"}],
                "not_this": [], "debated": []}
        return {"items": [{"id": "f1", "supported": True, "visible": True},
                          {"id": "f2", "supported": True, "visible": True},
                          {"id": "f3", "supported": True, "visible": False}]}       # what it eats does not show
    real, looks.ask = looks.ask, ask
    try:
        record = looks.read_look(None, cat.read_json(looks.CONFIG), None, "Kingfisher", "Birds", sources)
    finally:
        looks.ask = real
    assert [i["claim"] for i in record["features"]] == ["It has a long, sharp bill.", "Its back is bright blue."]
    assert [i["claim"] for i in record["dropped"]["quote_not_in_the_page"]] == ["It has a red crest."]
    assert record["dropped"]["second_reading"][0]["why"] == "a picture could not show it"


def test_what_tells_a_thing_apart_is_chosen_from_its_own_list_against_its_group():
    looks, asked = job.looks, []
    records = [{"name": "Kingfisher", "features": [{"claim": "a long, sharp bill"}, {"claim": "a bright blue back"},
                                                   {"claim": "smooth scaly legs"}, {"claim": "it often has a white throat"}]},
               {"name": "Owl", "features": [{"claim": "a round flat face"}, {"claim": "big forward-facing eyes"},
                                            {"claim": "soft feathers"}]},
               {"name": "Cup", "features": []}]
    def ask(client, config, spend, system, user, options=None):
        asked.append(user)
        return {"Kingfisher": {"shape": ["f1", "f9", "f3", "f4"], "covering": [], "why": "the bill"},   # f9 is not on its list
                "Owl": {"shape": ["f1", "f2"], "covering": ["f3"], "why": "the face"}}
    real, looks.ask = looks.ask, ask
    try:
        chosen = looks.tell_apart(None, cat.read_json(looks.CONFIG), None, "Birds", records, ["Crow", "Owl"])
    finally:
        looks.ask = real
    assert chosen["Kingfisher"]["must_show"] == ["a long, sharp bill"]          # an id not on its list, plain scales, and "often", are dropped
    assert chosen["Owl"]["must_show"] == ["a round flat face", "big forward-facing eyes", "soft feathers"]
    assert chosen["Cup"]["must_show"] == []                                     # its pages say nothing of its look: drawn as before
    assert "already in the game: Crow." in asked[0] and "Cup" not in asked[0]


def test_the_painter_line_and_the_cell_are_drawn_from_the_look():
    said = []
    def ask(client, config, spend, system, user, options=None):
        said.append(user)
        return {"draw": "a kingfisher with a long sharp bill and a bright blue back"}
    real, job.reslib.ask = job.reslib.ask, ask
    try:
        look = {"must_show": ["a long, sharp bill"], "not_this": ["a short, hooked bill"],
                "features": ["a long, sharp bill", "a bright blue back"], "sources": ["https://en.wikipedia.org/wiki/Kingfisher"]}
        line = job.describe(None, cat.read_json(job.reslib.CONFIG), None, {"chain": "Animals > Birds"}, "Kingfisher", look)
        job.describe(None, cat.read_json(job.reslib.CONFIG), None, {"chain": "Things people make"}, "Cup", {"must_show": []})
    finally:
        job.reslib.ask = real
    assert "- a long, sharp bill" in said[0] and "- a short, hooked bill" in said[0] and "Return JSON" in said[0]
    assert "checked sentence by sentence" not in said[1]                       # nothing from its sources: drawn as before
    assert line.startswith("a kingfisher")
    cell = job.cell_for({"name": "Kingfisher", "draw": line, "look": look})
    assert cell["must_show"] == ["a long, sharp bill"] and cell["features"] and cell["not_this"]
    assert "must_show" not in job.cell_for({"name": "Cup", "draw": "a cup", "look": {"must_show": []}})


def test_a_group_is_looked_up_once_and_kept():
    looks, calls = job.looks, []
    def read_look(client, config, spend, name, group, sources):
        calls.append(name)
        return {"name": name, "group": group, "features": [{"claim": f"{name} shape"}], "not_this": [], "debated": [],
                "dropped": {}, "sources": []}
    def tell_apart(client, config, spend, group, records, others=()):
        calls.append(("apart", tuple(r["name"] for r in records), tuple(others)))
        return {r["name"]: {"must_show": [r["features"][0]["claim"]], "covering": [], "why": "w"} for r in records}
    saved = (looks.LOOKS, looks.read_look, looks.tell_apart, looks.whole_pages)
    with tempfile.TemporaryDirectory() as folder:
        looks.LOOKS, looks.read_look, looks.tell_apart = pathlib.Path(folder), read_look, tell_apart
        looks.whole_pages = lambda name, config: []
        try:
            first = looks.look_up(None, {"judges": {"use": "x"}}, None, ["Pteranodon", "Quetzalcoatlus"], "Flyers", ["Dimorphodon"])
            again = looks.look_up(None, {"judges": {"use": "x"}}, None, ["Pteranodon", "Quetzalcoatlus"], "Flyers")
        finally:
            looks.LOOKS, looks.read_look, looks.tell_apart, looks.whole_pages = saved
    assert first["Pteranodon"]["must_show"] == ["Pteranodon shape"] == again["Pteranodon"]["must_show"]
    assert ("apart", ("Pteranodon", "Quetzalcoatlus"), ("Dimorphodon", "Pteranodon", "Quetzalcoatlus")) in calls
    assert calls.count("Pteranodon") == 1                                       # the second time it is read from what was kept


def test_the_clever_kid_check_counts_only_a_real_second_way_to_sort_the_sixteen():
    """The owner's example: T. rex among four dinosaurs and Tiger among four modern animals is fine,
    but a set that could also be sorted by eating habits must not be allowed."""
    intended = {"Dinosaurs": ["T. rex", "Triceratops", "Stegosaurus", "Velociraptor"],
                "Wild animals": ["Tiger", "Deer", "Wolf", "Zebra"],
                "Farm animals": ["Cow", "Goat", "Hen", "Pig"],
                "Pets": ["Dog", "Cat", "Rabbit", "Parrot"]}
    by_food = {"idea": "what it eats", "groups": {
        "meat": ["T. rex", "Velociraptor", "Tiger", "Wolf"], "grass": ["Triceratops", "Stegosaurus", "Deer", "Zebra"],
        "grain and scraps": ["Cow", "Goat", "Hen", "Pig"], "food from people": ["Dog", "Cat", "Rabbit", "Parrot"]}}
    assert job.other_ways({"other_ways": [by_food]}, intended) == ["what it eats"]
    assert job.other_ways({"other_ways": []}, intended) == []
    assert job.other_ways({}, intended) == []
    same_again = {"idea": "kinds", "groups": {k.lower(): v for k, v in intended.items()}}
    three_groups = {"idea": "x", "groups": dict(list(by_food["groups"].items())[:3])}
    five_in_one = {"idea": "x", "groups": dict(by_food["groups"], meat=["T. rex", "Velociraptor", "Tiger", "Wolf", "Dog"])}
    a_name_missing = {"idea": "x", "groups": dict(by_food["groups"], meat=["T. rex", "Velociraptor", "Tiger", "Lion"])}
    for loose in (same_again, three_groups, five_in_one, a_name_missing):
        assert job.other_ways({"other_ways": [loose]}, intended) == [], loose["idea"]
    # on the game's own data: the samples are sets a child would meet, and the answer is counted
    dictionary, things = cat.read_json(cat.DICTIONARY), cat.game_copy(cat.load())["things"]
    asked = []
    def ask(client, config, spend, system, user, options=None):
        asked.append(user)
        return {"other_ways": []} if len(asked) > 1 else {"other_ways": [{"idea": "nonsense", "groups": {"a": ["x"]}}]}
    real, job.reslib.ask = job.reslib.ask, ask
    try:
        seen = job.clever_kid(None, cat.read_json(job.reslib.CONFIG), None, dictionary, things, [("kind_of_thing", "animal")], None)
    finally:
        job.reslib.ask = real
    assert seen == {"sets_looked_at": 3, "with_another_way": 0, "ideas": []}
    assert "What kind of animal is it?" in asked[0] and asked[0].count("\n- ") == 4


def test_a_group_left_short_by_a_failed_picture_is_tried_once_more_in_the_same_run():
    """The owner's word of 24 Nov 2026: a set that ends one thing short because a picture failed
    gets one more try on its own. The run's code is read here, since a run cannot be staged offline."""
    code = pathlib.Path(job.__file__).read_text(encoding="utf-8")
    after = code[code.index("    draw_all()\n    # A group left short only because a picture failed"):code.index("def open_circles()")]
    assert "suggest(client, config, spend, cat.load(), ask, tried)" in after      # more names for that group
    assert "ground_each(" in after and after.rstrip().endswith("draw_all()")     # their facts, then their pictures
    assert 'ask.get("topped_up")' in after and 'ask["topped_up"] = True' in after  # once, not for ever
    assert 'not t.get("not_drawn")' in after                                      # only what was drawn and failed


# ------------------------------------------------------------------ a field is decided by four tests

def stand_in(sorting: dict, checking: dict = None, not_birds: tuple = (), more: dict = None):
    """In place of the sorting calls: the parent's answer, and the checker's. Asked what
    kind of animal each new name is, it says a bird, except for those in `not_birds`."""
    def ask(client, config, spend, system, user, options=None):
        if "Some of its groups need more things" in user:
            return dict(more or {})
        if "What kind of animal is it?" in user:
            kind = {name: "fish" if name in not_birds else "bird" for name in sorting}
            return kind if system == field_rules.SORTER else {name: [value] for name, value in kind.items()}
        if system == field_rules.SORTER:
            return dict(sorting)
        return {**{name: [value] for name, value in sorting.items()}, **(checking or {})}
    return ask


def know_all(client, config, spend, ask, offers):
    for o in offers:
        o.update(recognised=True, suitable=True, familiar=0.9, own_thing=True)


def candidate() -> dict:
    """Birds by where we see them: a field that should pass on the made-up world."""
    return {"key": "where_we_see_it", "wording": "Where do we see it?", "values": [
        {"key": "sky", "label": "High in the sky", "members": ["Eagle", "Crow"], "new": ["Kite", "Vulture", "Hawk"]},
        {"key": "water", "label": "On the water", "members": ["Duck", "Swan"], "new": ["Goose", "Pelican", "Flamingo"]},
        {"key": "yard", "label": "In the yard", "members": ["Hen", "Peacock"], "new": ["Rooster", "Turkey", "Pigeon"]},
        {"key": "trees", "label": "In the trees", "members": ["Parrot", "Owl"], "new": ["Woodpecker", "Mynah", "Sparrow"]}]}


def run_test(sorting_changes: dict = None, checking: dict = None, recognise=know_all, change=None,
             not_birds: tuple = (), more: dict = None) -> dict:
    dictionary, things, path = small_world()
    field = candidate()
    if change:
        change(dictionary, things, field)
    sorting = {name: v["key"] for v in field["values"] for name in v["members"] + v["new"]}
    sorting.update(sorting_changes or {})
    sorting.update({name: value for value, names in (more or {}).items() for name in names})
    real, field_rules.reslib.ask = field_rules.reslib.ask, stand_in(sorting, checking, not_birds, more)
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


def test_a_suggested_name_that_is_only_another_name_for_a_thing_there_does_not_count():
    def renamings(client, config, spend, ask, offers):
        assert "Duck" in ask["beside"]                 # the check is told what is already there
        for o in offers:       # the water birds suggested are a duck again: a wet duck, a big duck, a white duck
            o.update(recognised=True, suitable=True, familiar=0.9, own_thing=o["value"] != "water")
    result = run_test(recognise=renamings)
    assert "'On the water' has 2" in result["why"][0]
    assert result["not_things_of_their_own"] == ["Goose", "Pelican", "Flamingo"]
    # and when such a name is offered for a group, it is dropped, not held and not sent to anyone
    offer = {"name": "Wet duck", "familiar": 0.9, "recognised": True, "suitable": True, "own_thing": False}
    dropped = job.ground_thing(None, {}, None, {"fields": {}}, {"fixed": {"kind_of_thing": "animal"}}, offer, "run")
    assert dropped["not_needed"] and not dropped["passed"]
    assert job.held_as(dropped, "run", rehearsal=False) == ("", [])


def test_a_group_that_is_short_is_asked_for_more_names_once():
    def no_water_names(dictionary, things, field):      # the chooser offered no new water bird
        field["values"][1]["new"] = []
    short = run_test(change=no_water_names)
    assert "'On the water' has 2" in short["why"][0]    # asked again, and nothing came
    more = run_test(change=no_water_names, more={"water": ["Goose", "Pelican"]})
    assert more["why"] == [] and more["counts"]["water"] == 4 and more["topped_up"] == ["Goose", "Pelican"]
    # the names that come back are vetted like any other: these are not birds at all
    wrong = run_test(change=no_water_names, more={"water": ["Goose", "Pelican"]}, not_birds=("Goose", "Pelican"))
    assert "'On the water' has 2" in wrong["why"][0] and wrong["not_of_this_circle"] == ["Goose", "Pelican"]


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
    # and of all the names sorted, no more than one in eight may be without a single group
    names = run_test(checking={"Kite": ["sky", "trees"], "Goose": ["water", "yard"], "Rooster": ["yard", "sky"]})
    assert "3 of the 20 names sorted have no single group, and at most one in 8 may" in names["why"][0]
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
    assert "it has 3 values, and a board needs four" in field_rules.shape_problems(three, dictionary)
    assert field_rules.shape_problems(candidate(), dictionary) == []
    assert field_rules.unique_key(dictionary, "kind_of_animal", [("kind_of_animal", "bird")]) == "kind_of_animal_of_bird"


# ------------------------------------------------------------------ the field library

def test_the_model_chooses_from_the_library_and_cannot_invent():
    library = field_rules.load_library()
    ids = [q["id"] for q in library["questions"]]
    assert len(ids) == len(set(ids)) and all(len(q["values"]) >= 4 and q["wording"] and q["from"] for q in library["questions"])
    # a question is offered to the circles it is meant for, and to those inside them
    offered = lambda cid: {q["id"] for q in field_rules.library_for(library, cid)}
    assert {"where_it_lives", "how_it_moves", "pet_farm_or_wild"} <= offered("animal/mammal")
    assert "pet_farm_or_wild" not in offered("animal/fish")
    assert "what_the_water_does" in offered("nature_not_alive/water")
    assert "what_the_water_does" not in offered("made_by_people/vehicle/water")     # boats are not water
    assert "what_it_is_made_of" in offered("made_by_people/household/furniture")
    # what the model sends back is held to the library: an invented question is dropped, and
    # the wording and the groups are the library's own whatever the model writes
    questions = field_rules.library_for(library, "animal/bird")
    answer = {"chosen": [
        {"question": "what_song_it_sings", "groups": [{"key": "sweet", "members": ["Parrot"], "new": []}]},
        {"question": "how_it_moves", "groups": [{"key": "flies", "label": "Zooms", "members": ["Crow"], "new": ["Kite"]},
                                                {"key": "invented_group", "members": ["Hen"], "new": []}]},
        {"question": "how_it_moves", "groups": []}]}
    real, field_rules.reslib.ask = field_rules.reslib.ask, lambda *a, **k: answer
    try:
        chosen = field_rules.choose(None, {"model": "x", "thinking": "off"}, None, questions, "Animals > Birds", ["Crow", "Hen"], [], [])
    finally:
        field_rules.reslib.ask = real
    assert [c["library"] for c in chosen] == ["how_it_moves"]
    assert chosen[0]["wording"] == "How does it mostly move?"
    assert [v["key"] for v in chosen[0]["values"]] == ["walks", "flies", "swims", "crawls", "hops"]
    flies = chosen[0]["values"][1]
    assert flies["label"] == "Flies" and flies["members"] == ["Crow"] and flies["new"] == ["Kite"]
    assert all(v["members"] == [] for v in chosen[0]["values"] if v["key"] != "flies")


def test_a_field_may_have_more_than_four_values_and_needs_four_of_them_full():
    def a_fifth_value(dictionary, things, field):       # a fifth group that nothing here belongs to yet
        field["values"].append({"key": "ice", "label": "On the ice", "members": [], "new": []})
    five = run_test(change=a_fifth_value)
    assert five["why"] == [] and five["counts"]["ice"] == 0
    assert five["full_values"] == ["sky", "water", "yard", "trees"] and len(five["definition"]["values"]) == 5

    def nobody_knows_the_water_birds(client, config, spend, ask, offers):
        for o in offers:
            o.update(recognised=o["value"] != "water", suitable=True, familiar=0.9, own_thing=True)
    three = run_test(change=a_fifth_value, recognise=nobody_knows_the_water_birds)
    assert "only 3 of its values have four familiar things, and a board needs four" in three["why"][0]


def test_a_question_that_says_mostly_is_answered_by_what_is_mostly_true():
    seen = []
    def remember(client, config, spend, system, user, options=None):
        seen.append(user)
        return {}
    real, field_rules.reslib.ask = field_rules.reslib.ask, remember
    try:
        piles = [{"key": "a", "label": "A"}]
        field_rules.sort_twice(None, {"model": "x", "thinking": "off"}, None, "Animals", {"wording": "Where does it spend most of its life?", "values": piles}, ["Crow"])
        field_rules.sort_twice(None, {"model": "x", "thinking": "off"}, None, "Animals", {"wording": "How many legs does it have?", "values": piles}, ["Crow"])
    finally:
        field_rules.reslib.ask = real
    assert all("what is true of the thing most of the time" in prompt for prompt in seen[:2])
    assert not any("most of the time" in prompt for prompt in seen[2:])


def test_the_same_library_question_may_serve_two_circles():
    dictionary, things, _ = small_world()
    dictionary["fields"]["how_it_moves"] = {"wording": "How does it mostly move?", "library": "how_it_moves", "meaning": "everyday",
                                            "expected_on": {"kind_of_animal": "mammal"},
                                            "values": {"walks": "Walks or runs", "flies": "Flies", "swims": "Swims", "crawls": "Crawls or slithers"}}
    again = {"wording": "How does it mostly move?", "library": "how_it_moves",
             "values": [{"label": l} for l in ("Walks or runs", "Flies", "Swims", "Crawls or slithers")]}
    assert field_rules.synonym_of(dictionary, things, {}, again) == ""
    assert "it asks the same question" in field_rules.synonym_of(dictionary, things, {}, dict(again, library=None))
    assert field_rules.unique_key(dictionary, "how_it_moves", [("kind_of_animal", "bird")]) == "how_it_moves_of_bird"


# ------------------------------------------------------------------ who hears of what

def test_the_owner_hears_only_of_the_unsuitable_and_the_unsettled():
    thing = lambda **more: {"name": "X", "passed": False, "why": ["a reason"], **more}
    who = lambda t, rehearsal=False: job.held_as(t, "2026-10-07-01", rehearsal)[0]
    assert who(thing(for_owner=True)) == cat.WAITING                       # unfit for a young child
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
                             "source": "the library", "full_values": ["a", "b", "c", "d"],
                             "off_the_board": ["sea"],
                             "values": {"a": "In the sky", "b": "On the ground", "c": "In the house", "d": "Under the ground"}}],
           "fields_held": [{"label": "Rocks and soil", "tried": [{"wording": "How hard is it?", "why": ["'Soft' has 2"]}]}],
           "things": [{"name": "Tap", "passed": True, "tile": "t1", "why": []},
                      {"name": "Geyser", "passed": False, "why": ["the check doubts a four-year-old would recognise it"],
                       "held_as": cat.RULES},
                      {"name": "Well", "passed": False, "why": ["uncertain: two checks could not settle it"],
                       "held_as": cat.RULES},
                      {"name": "Whirlpool", "passed": False, "why": ["the check says it is not suitable for a young child"],
                       "held_as": cat.WAITING}]}
    text = "\n".join(job.digest(run, budget))
    assert "Circles opened: Water." in text
    assert 'Fields added: "Where is the water?" for Water, from the library' in text and "filled in on 4 things" in text
    assert "Things added: 1: Tap." in text and "Cost: Rs 50.0 of a hard cap of Rs 200" in text
    assert "Rocks and soil: no field passed the tests" in text and "Geyser (the check doubts" in text
    assert "For you: \n  - Whirlpool: the check says it is not suitable" in text
    assert 'sea has no one group for "Where is the water?" by two checks, so it stays off that board' in text
    assert "Well (uncertain: two checks could not settle it)" in text          # held by the rules, not asked of him
    assert "Left for a later run, in this order: Birds." in text
    assert text.endswith("To take this run back: python tools/prepare_next.py --undo 2026-10-07-01")


def test_a_thing_taken_out_on_purpose_does_not_come_back_by_itself():
    catalogue = cat.load()
    for entry in [e for e in catalogue["things"].values() if e["status"] in (cat.TAKEN_OUT, cat.EXCLUDED)][:3]:
        offer = {"name": entry["name"], "familiar": 0.9, "recognised": True, "suitable": True}
        back = job.ground_thing(None, {}, None, {"fields": {}}, {"fixed": dict(entry.get("fields") or {})}, offer, "run")
        assert back["not_needed"] and not back["passed"] and "on purpose" in back["why"][0]
        assert job.held_as(back, "run", rehearsal=False) == ("", [])        # and it is not held again either
    # nor is it offered from the names that came with a field
    proposals = cat.read_json(job.PROPOSALS)
    for cid, proposal in proposals.items():
        if cid != "about" and str(proposal.get("status", "")).startswith("approved"):
            for value in proposal.get("values", {}):
                ask = {"circle": cid, "fixed": {"x": value}}
                offered = {cat.slug(o["name"]) for o in job.approved_examples(catalogue, ask)}
                assert not any(catalogue["things"].get(k, {}).get("status") in (cat.TAKEN_OUT, cat.EXCLUDED) for k in offered)


def test_a_thing_settled_before_a_later_field_was_added_is_stamped_against_the_newest_dictionary():
    # a run may add several fields; things settled early carry an older stamp until they go in
    dictionary = cat.read_json(cat.DICTIONARY)
    saved = {}
    real = (cat.game_store, cat.put_game_store, job.tool, cat.changing)
    cat.game_store = lambda: {"things": {}, "dictionary_version": dictionary["version"]}
    cat.put_game_store = lambda store, by: saved.update(store["things"])
    job.tool = lambda *args: ""

    class nothing:                       # stands in for the catalogue's save
        def __init__(self, by): pass
        def __enter__(self): return {"things": {}}
        def __exit__(self, *a): return False
    cat.changing = nothing
    real_sync = (cat.sync_sources, cat.sync_voice)
    cat.sync_sources = cat.sync_voice = lambda catalogue: None
    real_run, job.subprocess.run = job.subprocess.run, lambda *a, **k: type("done", (), {"stdout": "", "returncode": 0})()
    try:
        early = {"name": "Kettle", "passed": True, "tile": "t1", "why": [],
                 "thing": {"name": "Kettle", "familiar": 0.9, "reviewed": dictionary["version"] - 1, "source": "job", "drafted_in": "run",
                           "fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "household", "kind_of_house_thing": "eating"}}}
        # one that a later field does apply to, and which lacks it, is not put in with a false stamp
        lacking = {"name": "Raft", "passed": True, "tile": "t2", "why": [],
                   "thing": {"name": "Raft", "familiar": 0.9, "reviewed": dictionary["version"] - 1, "source": "job", "drafted_in": "run",
                             "fields": {"kind_of_thing": "made_by_people", "kind_of_made_thing": "vehicle"}}}
        job.put_in_the_game({"id": "run", "things": [early, lacking]})
    finally:
        cat.game_store, cat.put_game_store, job.tool, cat.changing = real
        cat.sync_sources, cat.sync_voice = real_sync
        job.subprocess.run = real_run
    assert saved["kettle"]["reviewed"] == dictionary["version"]
    assert "raft" not in saved and not lacking["passed"] and "where_it_travels" in lacking["why"][0]


# ------------------------------------------------------------------ clues and explanations

def test_a_clue_never_names_a_thing_of_its_group_and_a_ladder_has_three():
    import group_words as gw
    group = {"label": "The leaves", "question": "Which part of the plant do we eat?"}
    names = ["Spinach plant", "Cabbage plant", "Coriander plant", "Fenugreek plant", "Mustard plant"]
    banned = gw.banned_words(group, names)
    assert {"spinach", "cabbage", "coriander"} <= banned
    assert "plant" not in banned and "leaves" not in banned          # the idea's own words are not names
    good = ["Think about the green part of a plant.", "It grows above the ground.", "We cook the soft leaves."]
    assert gw.clue_problems(good, banned) == []
    assert "names a thing of the group: spinach" in gw.clue_problems(good[:2] + ["Think of spinach."], banned)[0]
    assert "names a thing of the group: cabbages" in gw.clue_problems(good[:2] + ["Like cabbages."], banned)[0]
    assert "a ladder needs 3" in gw.clue_problems(good[:2], banned)[0]


def test_the_words_of_a_group_are_kept_only_when_the_checks_agree():
    import group_words as gw
    group = {"field": "part_we_eat", "value": "leaves", "label": "The leaves",
             "question": "Which part of the plant do we eat?", "members": ["Spinach plant", "Cabbage plant"]}
    page = "Spinach is a green, leafy vegetable. It is eaten cooked or raw."
    written = {"clues": ["Think about the green part.", "It grows above the ground.", "We cook the soft green part."],
               "explanation": {"together": "We eat the leaves of these plants.", "fact": "Spinach is a green leafy plant.",
                               "quote": "Spinach is a green, leafy vegetable.", "source": "spinach_plant:wikipedia_simple"}}
    agreed = {"clues": [{"true": True, "names": False, "simple": True, "only_here": True}] * 3, "ladder": True,
              "supported": True, "explains": True, "for_a_child": True}

    def run(writer, checker):
        real = (gw.reslib.ask, gw.sources_for)
        gw.reslib.ask = lambda client, config, spend, system, user, options=None: dict(writer if system == gw.WRITER else checker)
        gw.sources_for = lambda names: ("<source>", {"spinach_plant:wikipedia_simple": page}, {})
        try:
            return gw.write_one(None, {"model": "x", "thinking": "off"}, None, group, "Vegetable plants", ["The fruit"],
                                ["Spinach plant", "Cabbage plant"])
        finally:
            gw.reslib.ask, gw.sources_for = real

    kept = run(written, agreed)
    assert "held" not in kept and len(kept["clues"]) == 3
    assert kept["explanation"]["text"] == "We eat the leaves of these plants. Spinach is a green leafy plant."
    # a fact whose sentence is not in the saved page is not kept; the clues still are
    invented = dict(written, explanation=dict(written["explanation"], quote="Spinach makes you fly."))
    partly = run(invented, agreed)
    assert partly["explanation"] is None and len(partly["clues"]) == 3
    assert "not in the saved page" in partly["held"][0]
    # a later clue that would fit a thing of another group as well is not kept (the owner was caught
    # on 24 Nov 2026 by two groups whose clues said nearly the same); the first clue may be gentle
    broad = lambda which: dict(agreed, clues=[dict(agreed["clues"][0], only_here=i not in which) for i in range(3)])
    refused = run(written, broad({1}))
    assert refused["clues"] == [] and "fit a thing of another group" in refused["held"][0]
    assert len(run(written, broad({0}))["clues"]) == 3
    # a clue the second reading calls untrue is not kept
    doubted = dict(agreed, clues=[{"true": False, "names": False, "simple": True}] * 3)
    assert run(written, doubted)["clues"] == []
    # an explanation of four sentences is refused
    long = dict(written, explanation=dict(written["explanation"], together="We eat the leaves. They are green. They are soft."))
    assert "two or three" in run(long, agreed)["held"][0]


def test_words_are_looked_at_again_when_a_groups_things_change():
    """The owner's question of 24 Nov 2026: are clues made in a solid way for what is added later?
    A group's words carry a mark of the things they were written for; when its own things or a
    neighbour's change, the clues are checked against the things as they now stand."""
    import group_words as gw
    fruit = ["The fruit (Tomato plant, Brinjal plant)"]
    mark = gw.written_for(["Pea plant", "Bean plant"], fruit)
    assert mark == gw.written_for(["Bean plant", "Pea plant"], fruit)                       # the order does not matter
    assert mark != gw.written_for(["Pea plant", "Bean plant", "Cowpea plant"], fruit)       # a new thing of its own
    assert mark != gw.written_for(["Pea plant", "Bean plant"], ["The fruit (Tomato plant, Brinjal plant, Ladies finger plant)"])
    group = {"field": "part_we_eat", "value": "seeds_or_pods", "label": "The seeds",
             "question": "Which part of the plant do we eat?", "members": ["Pea plant", "Bean plant"]}
    clues = ["Think about the little hard parts.", "We take these out and cook them.", "We keep them dry in jars."]
    good = {"true": True, "names": False, "simple": True, "only_here": True}

    def fit(marks, these=clues):
        real, gw.reslib.ask = gw.reslib.ask, lambda *a, **k: {"clues": marks}
        try:
            return gw.still_fit(None, {"model": "x", "thinking": "off"}, None, group, "Vegetable plants", fruit,
                                ["Pea plant", "Bean plant", "Cowpea plant"], these)
        finally:
            gw.reslib.ask = real
    assert fit([good] * 3) == []
    assert "clue 2 would fit a thing of another group" in fit([good, dict(good, only_here=False), good])[0]
    assert fit([dict(good, only_here=False), good, good]) == []                             # the first clue may be gentle
    assert "not true of every thing" in fit([good, good, dict(good, true=False)])[0]        # a new thing it is not true of
    assert "names a thing of the group: cowpea" in fit([good] * 3, ["Think of the cowpea.", clues[1], clues[2]])[0]


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


# ------------------------------------------------------------------ the end of a branch

def test_a_branch_ends_where_the_world_holds_too_few_and_a_script_does_the_counting():
    """The owner, 24 Nov 2026: "there is no more below that... therefor that is the end of that brach"."""
    import ends
    asked = []
    def ask(client, config, spend, system, user, options=None):
        asked.append(user)
        if "Names:" in user:        # the second, strict call: Pangaea is no continent of today
            return {"Europe": True, "Africa": True, "Atlantis": True, "Oceania": True, "Australia": True, "Pangaea": False}
        return {"things": ["Europe", "Asia", "Africa", "Atlantis", "asia", "Oceania", "Australia", "Pangaea"]}
    articles = {"Europe": "Europe", "Africa": "Africa", "Oceania": "Oceania", "Australia": "Oceania"}
    real, ends.reslib.ask = ends.reslib.ask, ask
    try:
        world = ends.count_the_world(None, {"model": "m", "thinking": "t"}, None, "Places on land > Continents",
                                     ["Asia", "Antarctica"], lambda names: {n: articles[n] for n in names if n in articles})
    finally:
        ends.reslib.ask = real
    assert world["with_an_article"] == ["Europe", "Africa", "Oceania"], "what the game has is not counted twice"
    assert world["not_members"] == ["Pangaea"], "a second, strict call keeps only true members"
    assert world["no_article"] == ["Atlantis"], "the model's word is not enough: the article must exist"
    assert world["one_article_twice"] == ["Australia"], "two names filed under one article are one thing"
    assert world["count"] == 5 and ends.is_end(world)
    assert "only 5" in ends.why(world) and "Antarctica" in ends.why(world)
    assert "Never pad" in asked[0] and "breeds" in asked[0]
    assert not ends.is_end({"count": 16}), "sixteen can be sorted four by four: not an end"

    # the mark is on the question; the engine then never prepares the circle
    dictionary = copy.deepcopy(cat.read_json(cat.DICTIONARY))
    circles = expand.build_circles(dictionary, cat.game_copy(cat.load())["things"], cat.read_json(cat.SETTINGS))
    closed = next(cid for cid, c in circles.items() if not c["open"] and cid != "seed")
    ends.mark(dictionary, closed, ends.why(world), "a-test")
    assert ends.end_circles(dictionary, circles) == {closed: ends.why(world)}
    assert expand.ends_in(dictionary, circles) == {closed: ends.why(world)}
    for circle in circles.values():
        circle["decisions"] = []
    expand.judge(circles, expand.branch_stats(circles), {}, {}, expand.ends_in(dictionary, circles))
    assert circles[closed]["status"] == "end" and circles[closed]["held_by"].startswith("the end of this branch")
    assert closed not in expand.in_order(circles)
    # taken back: the mark is kept, and nothing is deleted
    assert ends.reopen(dictionary, closed, "a sixth was found")
    assert "ends" not in dictionary
    assert dictionary["ends_taken_back"][0]["taken_back_why"] == "a sixth was found"
    assert dictionary["ends_taken_back"][0]["place"] == closed
    assert not ends.reopen(dictionary, closed, "again")


# ------------------------------------------------------------------ widening a place, and "in between"

ANIMALS = {"wording": "What kind of animal is it?",
           "values": {"mammal": "Mammals", "bird": "Birds", "fish": "Fish", "insect": "Insects"}}
SUCH_AS = {"mammal": ["Cow", "Dog"], "bird": ["Crow", "Owl"], "fish": ["Shark"], "insect": ["Ant", "Bee"]}


def sortings(place: dict, also: dict = None):
    """Stands in for the two sortings: both put each name where `place` says; a name in
    `also` is listed by the second, strict one under a further pile as well."""
    def sort_twice(client, config, spend, chain, candidate, names):
        piles = {v["key"] for v in candidate["values"]}
        at = lambda n: place.get(n) if place.get(n) in piles else "none"
        return ({n: at(n) for n in names},
                {n: [x for x in [at(n), (also or {}).get(n)] if x in piles] for n in names})
    return sort_twice


def test_a_new_kind_must_stand_beside_the_kinds_there_not_inside_one_and_take_nothing_from_them():
    """The owner, 24 Nov 2026: a node may have more than four kinds. Tried for real the same evening:
    spiders and crabs are kinds the animals lacked; "Clothing" at the first place is not, for clothes
    are things people make; "In space" for vehicles is not, for the rocket was already "In the air"."""
    import widen
    spiders = {"key": "arachnid", "label": "Spiders and their kin", "why": "eight legs",
               "new": ["Spider", "Scorpion", "Tick", "Mite", "Tarantula"]}
    there = ["Cow", "Crow", "Shark", "Ant"]
    home = {"Cow": "mammal", "Crow": "bird", "Shark": "fish", "Ant": "insect"}
    run = lambda place, also=None: with_sortings(widen, sortings(place, also), lambda: widen.test_kind(
        None, {}, None, "Animals", ANIMALS, SUCH_AS, spiders, there))
    passed = run({**home, **{n: "arachnid" for n in spiders["new"]}})
    assert passed["why"] == [] and passed["names"] == spiders["new"]
    # only three of its things are put in it by both checks: no group
    thin = run({**home, "Spider": "arachnid", "Scorpion": "arachnid", "Tick": "arachnid", "Mite": "insect", "Tarantula": "insect"})
    assert "only 3 of its 5" in thin["why"][0]
    # the strict check would also put an animal that is already there in it: it swallows what is there
    greedy = run({**home, **{n: "arachnid" for n in spiders["new"]}}, also={"Ant": "arachnid"})
    assert "Ant, already here, would belong to it" in greedy["why"][0]
    # sorted over the old kinds alone, its things all have a place: it lies inside one of them
    def inside(client, config, spend, chain, candidate, names):
        piles = {v["key"] for v in candidate["values"]}
        where = (lambda n: "arachnid" if n in spiders["new"] else home[n]) if "arachnid" in piles else (lambda n: "insect")
        return {n: where(n) for n in names}, {n: [where(n)] for n in names}
    nested = with_sortings(widen, inside, lambda: widen.test_kind(None, {}, None, "Animals", ANIMALS, SUCH_AS, spiders, there))
    assert "it lies inside a kind that is there" in nested["why"][0] and "'Insects'" in nested["why"][0]

    # what the model offers is cleaned before anything is tested: no catch-all, no kind under a name already there
    offered = {"kinds": [{"key": "others", "label": "Other animals", "new": ["x"]},
                         {"key": "birdies", "label": "birds", "new": ["x"]},
                         {"key": "Arachnid", "label": "Spiders and their kin", "why": "eight legs", "new": ["Spider", "Spider", "Tick"]},
                         "nonsense"]}
    real, widen.reslib.ask = widen.reslib.ask, lambda *a, **k: offered
    try:
        kinds = widen.propose_kinds(None, {"model": "m", "thinking": "t"}, None, "Animals", ANIMALS, SUCH_AS)
    finally:
        widen.reslib.ask = real
    assert [(k["key"], k["new"]) for k in kinds] == [("arachnid", ["Spider", "Tick"])]


def with_sortings(module, stand_in, work):
    real, module.field_rules.sort_twice = module.field_rules.sort_twice, stand_in
    try:
        return work()
    finally:
        module.field_rules.sort_twice = real


def test_a_thing_is_in_between_only_when_its_sources_say_so_and_two_checks_give_it_no_one_place():
    """The owner, 24 Nov 2026: "Virus, Pluto... things resist binary classification." The world
    not agreeing is a fact and goes in; our not finding out is not. Tried for real the same evening:
    of fifteen things the model offered at the first place, only the virus passed."""
    import widen
    alive = {"wording": "What kind of thing is it?",
             "values": {"animal": "Animals", "plant": "Plants", "not_alive": "Things that are not alive"}}
    page = ("A virus is a tiny agent that multiplies only inside living cells. Scientific opinions differ on whether "
            "viruses are a form of life or structures that interact with living things. Corals are animals of the sea. "
            "Coral was once thought to be a plant, which is now settled. Rain is water that falls from clouds in the sky. "
            "Rain is liquid water in the form of droplets.")
    sources = [{"id": "wikipedia_en", "text": page}]
    def read(answer, definition=alive):
        real, widen.reslib.ask = widen.reslib.ask, lambda *a, **k: answer
        try:
            return widen.read_between(None, {"model": "m", "thinking": "t"}, None, "It", definition, sources, "<source/>")
        finally:
            widen.reslib.ask = real
    disputed = read({"answers": {}, "today": True,
                     "disputed": "Scientific opinions differ on whether viruses are a form of life or "
                                 "structures that interact with living things."})
    assert disputed["value"] == "depends" and "disputed" in disputed["sentences"]
    # a dispute of the past, settled now, does not make a thing in between today
    settled = read({"answers": {"animal": "Corals are animals of the sea."}, "today": False,
                    "disputed": "Coral was once thought to be a plant, which is now settled."})
    assert settled["value"] is None and "one answer, 'Animals'" in settled["why"]
    # a sentence that is not in the saved text proves nothing, however true it sounds
    invented = read({"answers": {}, "disputed": "Biologists have argued for a century about whether a virus is alive."})
    assert invented["value"] is None and "no sentence" in invented["why"]
    # two answers, each with its own sentence: it lists both
    sky = {"wording": "What kind of thing in nature is it?", "values": {"sky": "Things in the sky", "water": "Water", "land": "Land"}}
    both = read({"answers": {"sky": "Rain is water that falls from clouds in the sky.",
                             "water": "Rain is liquid water in the form of droplets.", "land": "It lands on land, I am sure of it."},
                 "disputed": ""}, sky)
    assert both["value"] == ["sky", "water"] and "land" not in both["sentences"]
    # one answer and no dispute: it has a place, and is not in between
    one = read({"answers": {"animal": "Corals are animals of the sea."}, "disputed": ""})
    assert one["value"] is None and "one answer, 'Animals'" in one["why"]
    note = widen.note_for(alive, disputed)
    assert "Scientific opinions differ" in note and note.startswith("It has no single answer here")

    # the second key: two sortings that both give it one and the same place mean it has a place after all
    placed = with_sortings(widen, sortings({"Coral": "animal"}),
                           lambda: widen.one_place(None, {}, None, "Everything", alive, {}, "Coral"))
    assert placed == "animal"
    torn = with_sortings(widen, sortings({"Virus": "not_alive"}, also={"Virus": "animal"}),
                         lambda: widen.one_place(None, {}, None, "Everything", alive, {}, "Virus"))
    assert torn is None
    # names offered: only kinds the question has are kept as sides, and nothing the game already holds
    offers = {"things": [{"name": "virus", "between": ["animal", "nonsense", "not_alive"], "why": "edge of life"},
                         {"name": "Cow", "between": []}, {"name": "Virus", "between": []}, 7]}
    real, widen.reslib.ask = widen.reslib.ask, lambda *a, **k: offers
    try:
        named = widen.propose_between(None, {"model": "m", "thinking": "t"}, None, "Everything", alive, ["Cow"])
    finally:
        widen.reslib.ask = real
    assert named == [{"name": "Virus", "between": ["animal", "not_alive"], "why": "edge of life"}]


def test_a_widening_run_is_planned_for_one_place_that_has_its_question():
    plan = job.plan_widen(cat.load(), "animal")
    assert [e["circle"] for e in plan["circles"]] == ["animal"] and plan["circles"][0]["widen"] is True
    assert plan["asks"] == [] and plan["blocked"] == [] and plan["widen"] == "animal"
    no_question = next(cid for cid, c in cat.load()["worked_out"]["circles"].items() if not c.get("sorted_by"))
    refused = job.plan_widen(cat.load(), no_question)
    assert refused["circles"] == [] and "it has no question yet" in refused["blocked"][0]
    # a thing of a kind added later, or with no single first kind, is drawn as a thing of nature
    assert job.sheet_kind({"fields": {"kind_of_thing": "animal"}}) == "animal"
    assert job.sheet_kind({"fields": {"kind_of_thing": "a_kind_added_later"}}) == "nature_not_alive"
    assert job.sheet_kind({"fields": {"kind_of_thing": ["plant", "animal"]}}) == "plant"
    assert job.sheet_kind({"fields": {"kind_of_thing": "depends"}}) == "nature_not_alive"


# ------------------------------------------------------------------ circles that cross

def crossing_world() -> tuple:
    """Mammals and birds each answer "how does it move?" under a field of their own; fish and
    dinosaurs have never been asked. What a mammal that walks eats hangs from that answer."""
    moves = {"walks": "Walks", "flies": "Flies", "swims": "Swims", "crawls": "Crawls"}
    dictionary = {"version": 1, "fields": {
        "kind_of_thing": {"wording": "What kind of thing is it?", "expected_on": "everything",
                          "values": {"animal": "Animals", "plant": "Plants", "made": "Made things", "nature": "Nature"}},
        "kind_of_animal": {"wording": "What kind of animal is it?", "expected_on": {"kind_of_thing": "animal"},
                           "values": {"mammal": "Mammals", "bird": "Birds", "fish": "Fish", "dinosaur": "Dinosaurs"}},
        "how_it_moves": {"wording": "How does it mostly move?", "library": "how_it_moves",
                         "expected_on": {"kind_of_animal": "mammal"}, "values": dict(moves)},
        "how_it_moves_of_bird": {"wording": "How does it mostly move?", "library": "how_it_moves",
                                 "expected_on": {"kind_of_animal": "bird"}, "values": dict(moves)},
        "what_it_eats": {"wording": "What does it eat?", "expected_on": {"how_it_moves": "walks"},
                         "values": {"plants": "Plants", "meat": "Meat", "both": "Both", "insects": "Insects"}},
    }}
    def animal(kind, **more):
        return {"fields": {"kind_of_thing": "animal", "kind_of_animal": kind, **more}, "familiar": 0.9}
    things = {"cow": animal("mammal", how_it_moves="walks", what_it_eats="plants"), "bat": animal("mammal", how_it_moves="flies"),
              "crow": animal("bird", how_it_moves_of_bird="flies"), "duck": animal("bird", how_it_moves_of_bird="swims"),
              "shark": animal("fish"), "eel": animal("fish"), "t_rex": animal("dinosaur"),
              "mango": {"fields": {"kind_of_thing": "plant"}, "familiar": 0.9}}
    for key, thing in things.items():
        thing["name"] = key.replace("_", " ").capitalize()
    return dictionary, things, [("kind_of_thing", "animal")]


def test_a_question_asked_of_a_wider_circle_takes_over_its_twin_and_sorts_only_what_is_left():
    """The owner, 24 Nov 2026: "we still assume concentric circles paradigm. but knowledge is never
    that." A question belongs to every thing it is true of, not to one place."""
    import cross
    dictionary, things, path = crossing_world()
    todo = cross.plan(dictionary, things, "how_it_moves", path)
    assert todo["keep"] == ["cow", "bat"], "the mammals have answered"
    assert todo["take_over"] == {"crow": ("how_it_moves_of_bird", "flies"), "duck": ("how_it_moves_of_bird", "swims")}, \
        "the birds answered the same question under another field: nothing is asked again"
    assert todo["to_sort"] == ["shark", "eel", "t_rex"] and todo["twins"] == ["how_it_moves_of_bird"]
    assert todo["hangs"] == ["what_it_eats"]
    assert "mango" not in todo["keep"] + todo["to_sort"], "a plant is outside the circle"
    assert cross.same_question(dictionary["fields"]["how_it_moves"], dictionary["fields"]["how_it_moves_of_bird"])
    assert not cross.same_question(dictionary["fields"]["how_it_moves"], dictionary["fields"]["what_it_eats"])

    # the piles are shown with things of every kind that has answered, not of one kind only
    shown = cross.examples(things, {"cow": "walks", "bat": "flies", "crow": "flies", "duck": "swims"}, "kind_of_animal")
    assert shown == {"walks": ["Cow"], "flies": ["Bat", "Crow"], "swims": ["Duck"]}


def test_a_question_has_a_reach_and_a_thing_it_does_not_fit_carries_no_answer():
    """The first real run: both checks placed the fish and the insects, and both refused every
    dinosaur. A dinosaur is not a pet, a farm animal or a wild animal; it is gone."""
    import cross
    dictionary, things, path = crossing_world()
    def sort_twice(client, config, spend, chain, candidate, names):
        where = {"Shark": ("swims", ["swims"]), "Eel": ("swims", ["crawls"]), "T rex": ("none", []),
                 # one check places it and the other does not, among the others; asked alone, both agree
                 "Ray": ("none", ["swims"]) if len(names) > 1 else ("swims", ["swims"])}
        return {n: where[n][0] for n in names}, {n: where[n][1] for n in names}
    real, cross.field_rules.sort_twice = cross.field_rules.sort_twice, sort_twice
    try:
        placed, several, nowhere = cross.sort_them(None, {}, None, "Animals", dictionary["fields"]["how_it_moves"], {},
                                                   ["Shark", "Eel", "T rex", "Ray"])
    finally:
        cross.field_rules.sort_twice = real
    assert placed == {"Shark": "swims", "Ray": "swims"}, "both checks, one group; the ray once it was asked by itself"
    assert several == {"Eel": ["swims", "crawls"]}, "the checks differ: it lists both, and stays off such sets"
    assert nowhere == ["T rex"], "neither can place it: the question is not about it"

    after = cross.rules_after(copy.deepcopy(dictionary), "how_it_moves", path, ["how_it_moves_of_bird"], everywhere=False)["fields"]
    assert after["how_it_moves"]["expected_on"] == {"kind_of_thing": "animal"} and after["how_it_moves"]["where_it_fits"] is True
    assert after["how_it_moves"]["crossed"][0]["was_asked_of"] == {"kind_of_animal": "mammal"}
    assert after["how_it_moves_of_bird"]["merged_into"] == "how_it_moves" and after["how_it_moves_of_bird"]["sorts_boards"] is False
    assert after["what_it_eats"]["expected_on"] == {"kind_of_animal": "mammal", "how_it_moves": "walks"}, \
        "what hung from one of its answers stays where it was: it is not suddenly asked of every animal that walks"
    whole = cross.rules_after(copy.deepcopy(dictionary), "how_it_moves", path, [], everywhere=True)["fields"]
    assert "where_it_fits" not in whole["how_it_moves"]

    # the guard: a thing the question does not fit may lack the answer, and a merged field is asked of nobody
    import guard
    stamped = lambda fields: {"things": {"x": {"name": "X", "fields": fields, "reviewed": 1}}}
    rules = {"version": 1, "fields": after}
    dinosaur = {"kind_of_thing": "animal", "kind_of_animal": "dinosaur"}
    assert guard.problems(rules, stamped(dinosaur)) == []
    assert guard.problems(rules, stamped({"kind_of_thing": "animal", "kind_of_animal": "bird", "how_it_moves": "flies"})) == []
    strict = {"version": 1, "fields": whole}
    assert any("missing 'how_it_moves'" in line for line in guard.problems(strict, stamped(dinosaur)))
    # and to the worker's set rules a merged field is no second way to sort a set
    from boards import second_solution
    sixteen = {f"t{i}": {"fields": {"how_it_moves": list(after["how_it_moves"]["values"])[i // 4],
                                    "how_it_moves_of_bird": list(after["how_it_moves"]["values"])[i // 4]}} for i in range(16)}
    assert second_solution(rules, sixteen, list(sixteen), "how_it_moves") is None
    assert second_solution({"version": 1, "fields": dictionary["fields"]}, sixteen, list(sixteen), "how_it_moves") == "how_it_moves_of_bird"


def test_words_that_are_no_longer_true_of_a_widened_group_are_set_aside_not_kept():
    """A group may grow past what its words were written for: the wild animals in water were whales
    and seals, and "comes up to breathe air" was true; then the fish joined them. No clue is better
    than a false one."""
    import group_words
    asked = {}
    def ask(client, config, spend, system, user, options=None):
        asked["user"] = user
        return {"clues": [{"true": False, "names": False, "simple": True, "only_here": True},
                          {"true": True, "names": False, "simple": True, "only_here": True},
                          {"true": True, "names": False, "simple": True, "only_here": True}], "ladder": True, "explains": False}
    real, group_words.reslib.ask = group_words.reslib.ask, ask
    try:
        wrong = group_words.still_fit(None, {"model": "m", "thinking": "t"}, None,
                                      {"question": "Is it a pet, a farm animal or a wild animal?", "label": "Wild animals in water",
                                       "field": "f", "value": "wild_water"}, "Animals", ["Pets (Dog)"], ["Whale", "Shark"],
                                      ["It comes up to breathe air.", "It swims.", "It lives in water."],
                                      "They all breathe air from above the water.")
    finally:
        group_words.reslib.ask = real
    assert "They all breathe air" in asked["user"], "the explanation is read again as well"
    assert any(w.startswith("clue 1") and "not true" in w for w in wrong)
    assert any(w.startswith("the explanation") and "not true" in w for w in wrong)
    assert [w for w in wrong if "not true" in w] == wrong[-2:] or len([w for w in wrong if "not true" in w]) == 2


# ------------------------------------------------------------------ the map of places

def test_a_place_the_tree_never_knew_is_planned_from_the_map():
    """The owner, 24 Nov 2026: the map is "the nerve system of the whole thing". The job works
    nothing out about such a place for itself: the map says what it could be asked and which
    kinds are short, and each short kind is an ordinary need inside every circle of the place."""
    the_map = {"places": {
        "animal/wild_water": {"name": "Wild animals in water", "state": "can be made", "why": "2 more",
                              "circles": [["kind_of_thing", "animal"], ["pet_farm_or_wild", "wild_water"]],
                              "could_ask": [{"question": "kind_of_animal", "wording": "What kind of animal is it?",
                                             "fill": {"reptile": 2}, "more_things_needed": 2}]},
        "animal/wild_land": {"name": "Wild animals on land", "state": "ready", "why": "", "circles": [], "could_ask": []},
        "animal/bird/pet": {"name": "Pets at home", "state": "held", "why": "the rules: too few", "circles": [], "could_ask": []},
    }}
    plan = job.plan_place(the_map, "animal/wild_water")
    entry = plan["circles"][0]
    assert entry["on_the_map_only"] and entry["circle"] == "animal/wild_water" and not entry["needs_field"]
    ask = entry["asks_from_the_map"][0]
    assert list(ask["fixed"].items()) == [("kind_of_thing", "animal"), ("pet_farm_or_wild", "wild_water"),
                                          ("kind_of_animal", "reptile")], "every circle of the place, and the kind last"
    assert ask["need"] == 2 and ask["circle"] == "animal/wild_water"
    assert ask["chain"] == "Animals > Wild animals in water > Reptiles"
    assert job.plan_place(the_map, "animal/wild_land")["nothing_to_do"] == ["Wild animals on land: it can already open"]
    held = job.plan_place(the_map, "animal/bird/pet")
    assert held["circles"] == [] and held["blocked"] == ["Pets at home: held: the rules: too few"]


# ------------------------------------------------------------------ a kind is made with its clues

def test_a_question_is_proposed_with_the_clues_of_each_of_its_groups():
    """The owner, 24 Nov 2026: "it is a bad habit to have to deal with this" afterwards. Whoever
    proposes a question gives, with each group, the three hints that follow from what makes a
    thing belong there; they go into the dictionary with the group."""
    assert field_rules.ladder_of(["One.", "Two  words.", "Three."]) == ["One.", "Two words.", "Three."]
    assert field_rules.ladder_of(["One.", "Two."]) == [], "a ladder is kept whole or not at all"
    assert field_rules.ladder_of("not a list") == [] and field_rules.ladder_of(None) == []
    assert field_rules.ladder_of(["a " * 30, "b", "c"]) == [], "a clue is one short sentence"
    answer = {"fields": [{"key": "how_it_moves", "wording": "How does it move?", "why": "a real difference", "values": [
        {"key": "flies", "label": "Flies", "members": ["Crow"], "new": ["Kite bird"],
         "clues": ["Think about going up.", "It has wings to hold it in the air.", "It moves through the sky, not on the ground."]},
        {"key": "swims", "label": "Swims", "members": ["Duck"], "new": [], "clues": ["Only one."]}]}]}
    asked = []
    def ask(client, config, spend, system, user, options=None):
        asked.append(user)
        return answer
    real, field_rules.reslib.ask = field_rules.reslib.ask, ask
    try:
        found = field_rules.propose(None, {"model": "m", "thinking": "t"}, None, {"fields": {}}, "Animals > Birds", ["Crow", "Duck"], [], [])
    finally:
        field_rules.reslib.ask = real
    assert "true of EVERY thing that could ever belong" in asked[0], "the model is asked for clues from what defines the group"
    values = {v["key"]: v for v in found[0]["values"]}
    assert values["flies"]["clues"][2] == "It moves through the sky, not on the ground." and values["swims"]["clues"] == []
    # and a kind added to a question comes with its clues as well
    import widen
    offered = {"kinds": [{"key": "arachnid", "label": "Spiders and their kin", "why": "eight legs", "new": ["Spider"],
                          "clues": ["Many legs.", "Count them: eight.", "Eight legs and no wings."]}]}
    real, widen.reslib.ask = widen.reslib.ask, lambda *a, **k: offered
    try:
        kind = widen.propose_kinds(None, {"model": "m", "thinking": "t"}, None, "Animals", ANIMALS, SUCH_AS)[0]
    finally:
        widen.reslib.ask = real
    assert kind["clues"] == ["Many legs.", "Count them: eight.", "Eight legs and no wings."]


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing sent, nothing spent, nothing changed.")


if __name__ == "__main__":
    main()
