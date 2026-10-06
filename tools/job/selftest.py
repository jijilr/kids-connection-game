"""Checks the job's planning and its hard cap, offline. Nothing is sent, spent or changed.

    python tools/job/selftest.py
"""
import copy
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import prepare_next as job          # noqa: E402
from prepare_next import cat        # noqa: E402


def test_only_what_the_owner_approved_is_planned():
    plan = job.plan(cat.load())
    assert plan["asks"] == []                      # nothing approved is waiting for things or pictures
    # Dinosaurs is approved and one Flyer short, but the two candidates are the owner's to choose between
    assert any("Flyers" in line and "deliberately not in the game yet" in line for line in plan["blocked"])


def test_a_rehearsal_plans_the_circle_named_and_nothing_else():
    plan = job.plan(cat.load(), rehearse="made_by_people/building")
    assert len(plan["asks"]) == 1
    ask = plan["asks"][0]
    assert ask["fixed"] == {"kind_of_thing": "made_by_people", "kind_of_made_thing": "building"}
    assert ask["need"] == 3 and ask["chain"] == "Things people make > Buildings"


def test_a_circle_with_no_field_to_sort_it_is_left_to_the_owner():
    plan = job.plan(cat.load(), rehearse="animal/mammal")
    assert plan["asks"] == [] and any("needs a field" in line for line in plan["blocked"])


def test_a_thing_in_the_game_without_a_picture_is_planned_for_drawing():
    catalogue = copy.deepcopy(cat.load())
    catalogue["things"]["cup"]["picture"]["game_file"] = None
    cat.work_out(catalogue)
    plan = job.plan(catalogue, rehearse="made_by_people")
    assert [a["pictures_for"] for a in plan["asks"] if a.get("pictures_for")] == [["Cup"]]
    assert job.plan(cat.load(), rehearse="made_by_people")["asks"] == []      # and not when every thing has one


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


def test_the_expected_cost_grows_with_the_work():
    one = [{"need": 1}]
    many = [{"need": 6}]
    assert job.expected_cost([], 96)[1] == 0
    assert 0 < job.expected_cost(one, 96)[0] < job.expected_cost(many, 96)[0]
    assert all(likely <= most for likely, most in (job.expected_cost(one, 96), job.expected_cost(many, 96)))


def main():
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print("  passed:", test.__name__[5:].replace("_", " "))
    print(f"ALL OK - {len(tests)} checks, nothing sent, nothing spent, nothing changed.")


if __name__ == "__main__":
    main()
