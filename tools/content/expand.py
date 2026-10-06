"""The expansion engine: decides which circle should grow next, the way a chess engine
chooses which line to analyse. The aim is a well-rounded child, not a specialist, so it
will not keep digging into the branch he already loves.

It only PROPOSES. It never drafts things, never touches the dictionary, and never
changes the data. The owner approves; then draft.py / check.py / guard.py do the work.

Its memory is tools/content/expansion_tree.json. Every run rebuilds the tree from the
real data (which decides what is open and what is missing) and carries the decisions
forward from the file (which is the only record of what was tried, held or rejected).

    python tools/content/expand.py
        rebuild the tree and list the top proposals

    python tools/content/expand.py decide CIRCLE --what "..." --why "..."
            [--status approved|rejected|waiting] [--retry-when "..."]
        record a decision on a circle, then rebuild
"""
import argparse
import datetime
import math

from boards import GROUPS, PER_GROUP, members, second_solution_rate, split, sub_kind
from lib import DICTIONARY, ROOT, THINGS, read_json, write_json

TREE = ROOT / "tools/content/expansion_tree.json"
PROPOSALS = ROOT / "tools/content/field_proposals.json"
SETTINGS = ROOT / "Assets/data/settings.json"

# Scoring: each factor runs 0..1, so the total is out of 10.
WEIGHTS = {"nearness": 3, "neglect": 3, "unlocks": 2, "cheapness": 2}
FIELD_COST = 4            # a new field costs as much as four new things
# Balance.
GAP_LIMIT = 1             # levels a branch may be deeper than the shallowest branch
WIDENING_BASE = 0.25      # share of proposals that must widen when branches are level...
WIDENING_PER_LEVEL = 0.25  # ...plus this much for each level of gap between them
AMBIGUITY_LIMIT = 0.5     # above this share of second solutions, a field does not open a circle
TOP = 5


# ------------------------------------------------------------------ the tree

def build_circles(dictionary: dict, things: dict, settings: dict) -> dict:
    """Every circle reachable from an open board, with what each closed one is missing."""
    circles = {}
    fields = dictionary["fields"]

    def add(cid, label, path, parent_field, steps, branch, field=None):
        keys = members(things, path)
        circle = {"label": label, "steps_from_seed": steps, "branch": branch,
                  "members": len(keys), "open": False}
        circles[cid] = circle

        if steps > 0 and len(keys) < PER_GROUP:
            circle["missing"] = {
                "things": PER_GROUP - len(keys),
                "why": "fewer than four familiar things, so it is not yet a group on the board above it"}
            return
        field = field or sub_kind(dictionary, things, keys, path, parent_field)
        if field is None:
            circle["missing"] = {"field": "no field splits it four ways",
                                 "things": max(0, GROUPS * PER_GROUP - len(keys))}
            return

        circle["sorted_by"] = field
        groups = split(things, keys, field)
        size = lambda value: len(groups.get(value, []))
        if sum(1 for value in fields[field]["values"] if size(value) >= PER_GROUP) < GROUPS:
            best_four = sorted(fields[field]["values"], key=lambda v: -size(v))[:GROUPS]
            short = {v: PER_GROUP - size(v) for v in best_four if size(v) < PER_GROUP}
            circle["missing"] = {"field": None, "short": short, "things": sum(short.values())}
            return
        rate = second_solution_rate(dictionary, things, groups, field)
        if rate > AMBIGUITY_LIMIT:
            circle["missing"] = {"field": None, "things": 0,
                                 "one_solution": f"{rate:.0%} of its boards have a second clean solution"}
            return

        circle["open"] = True
        for value, value_label in fields[field]["values"].items():
            child = value if steps == 0 else f"{cid}/{value}"
            add(child, value_label, path + [(field, value)], field, steps + 1, branch or value)

    start = settings["start"]
    add("seed", start["label"], [], None, 0, None, field=start["field"])
    return circles


def branch_stats(circles: dict) -> dict:
    """For each of the seed's branches: how many boards are open in it, and how deep.
    A board the owner has approved counts already, even while it waits for its content:
    it is committed, and the balance rules must see it."""
    stats = {}
    for circle in circles.values():
        if circle["branch"] is None:
            continue
        branch = stats.setdefault(circle["branch"], {"boards_open": 0, "level": 0})
        approved = any(d.get("status") == "approved" for d in circle["decisions"])
        if circle["open"] or approved:
            branch["boards_open"] += 1
            branch["level"] = max(branch["level"], circle["steps_from_seed"])
    return stats


def judge(circles: dict, branches: dict, old: dict, proposals: dict):
    """Score every closed circle and decide its status. Decisions come from the old tree."""
    richest = max(b["boards_open"] for b in branches.values())
    shallowest = min(b["level"] for b in branches.values())
    for cid, circle in circles.items():
        if cid in proposals:
            circle["proposal"] = proposals[cid]
        if circle["open"]:
            circle["status"] = "open"
            continue

        missing = circle["missing"]
        opens_a_board = "why" not in missing
        new_fields = 1 if missing.get("field") else 0
        new_things = missing.get("things", 0)
        if "proposal" in circle:  # an exact count beats the floor estimate
            new_things = sum(max(0, PER_GROUP - len(v["have"]))
                             for v in circle["proposal"]["values"].values())
            missing["things"] = new_things
        branch = branches[circle["branch"]]
        factors = {
            "nearness": 1 / circle["steps_from_seed"],
            "neglect": 1 - branch["boards_open"] / max(1, richest),
            "unlocks": min(1.0, (1 if opens_a_board else 0) / 3),
            "cheapness": 4 / (4 + new_things + FIELD_COST * new_fields),
        }
        circle["factors"] = {name: round(value, 2) for name, value in factors.items()}
        circle["score"] = round(sum(WEIGHTS[name] * value for name, value in factors.items()), 1)
        favoured = richest > 0 and branch["boards_open"] == richest
        circle["move"] = "deepening" if opens_a_board and favoured else "widening"

        statuses = [d["status"] for d in circle["decisions"] if d.get("status")]
        too_deep = opens_a_board and circle["steps_from_seed"] > shallowest + GAP_LIMIT
        circle.pop("held_by", None)
        if statuses and statuses[-1] == "rejected":
            circle["status"] = "rejected"
        elif "approved" in statuses:
            circle["status"] = "approved by the owner"
        elif statuses and statuses[-1] == "waiting":
            # the owner held it: it is not proposed again until what he waits for has come
            last = [d for d in circle["decisions"] if d.get("status")][-1]
            circle["status"] = "held"
            circle["held_by"] = "the owner: " + last["why"] + (f"; until {last['retry_when']}" if last.get("retry_when") else "")
        elif "one_solution" in missing:
            circle["status"] = "held"
            circle["held_by"] = "one clean solution: " + missing["one_solution"]
        elif too_deep:
            circle["status"] = "held"
            circle["held_by"] = (f"depth gap: its branch would be {circle['steps_from_seed']} levels deep "
                                 f"while the shallowest branch is at {shallowest}")
        else:
            circle["status"] = "proposable"


def propose(circles: dict, branches: dict) -> tuple:
    """The top few proposable circles, with enough of them widening to keep the balance."""
    able = sorted((cid for cid, c in circles.items() if c["status"] == "proposable"),
                  key=lambda cid: -circles[cid]["score"])
    gap = max(b["level"] for b in branches.values()) - min(b["level"] for b in branches.values())
    share = min(1.0, WIDENING_BASE + WIDENING_PER_LEVEL * gap)
    widening = [cid for cid in able if circles[cid]["move"] == "widening"]
    chosen = widening[:math.ceil(share * min(TOP, len(able)))]
    chosen += [cid for cid in able if cid not in chosen][:TOP - len(chosen)]
    chosen.sort(key=lambda cid: -circles[cid]["score"])

    # Rhythm: after a deepening is approved, lead with a widening elsewhere.
    approved = [(d["date"], d.get("move", "")) for c in circles.values()
                for d in c["decisions"] if d.get("status") == "approved"]
    if approved and max(approved)[1] == "deepening":
        first_wide = next((cid for cid in chosen if circles[cid]["move"] == "widening"), None)
        if first_wide:
            chosen.remove(first_wide)
            chosen.insert(0, first_wide)
    return chosen, share


# ------------------------------------------------------------------ reporting

def what_is_missing(circle: dict) -> str:
    missing = circle["missing"]
    if "why" in missing:
        return f"{missing['things']} more familiar thing(s) to become a group"
    if "one_solution" in missing:
        return missing["one_solution"]
    parts = []
    if missing.get("field"):
        parts.append("a new field")
    if missing.get("short"):
        parts.append(", ".join(f"{n} more in '{v}'" for v, n in missing["short"].items()))
    elif missing.get("things"):
        parts.append(f"about {missing['things']} familiar things")
    return " and ".join(parts)


def rebuild() -> dict:
    dictionary = read_json(DICTIONARY)
    things = read_json(THINGS)["things"]
    old = (read_json(TREE, {}) or {}).get("circles", {})
    proposals = {k: v for k, v in (read_json(PROPOSALS, {}) or {}).items()
                 if k != "about" and v["status"].startswith("awaiting")}

    circles = build_circles(dictionary, things, read_json(SETTINGS))
    for cid, circle in circles.items():
        circle["decisions"] = old.get(cid, {}).get("decisions", [])
    branches = branch_stats(circles)
    judge(circles, branches, old, proposals)
    chosen, share = propose(circles, branches)

    tree = {
        "about": "The expansion engine's memory. Rebuilt from the data on every run; the "
                 "decisions are carried forward and are the only record of what was tried, "
                 "held, approved or rejected. Edit decisions with `expand.py decide`.",
        "updated": datetime.date.today().isoformat(),
        "dictionary_version": dictionary["version"],
        "things": len(things),
        "rules": {"weights": WEIGHTS, "field_cost": FIELD_COST, "gap_limit": GAP_LIMIT,
                  "widening_share_now": share},
        "branches": branches,
        "proposals": chosen,
        "circles": circles,
    }
    write_json(TREE, tree)
    return tree


def show(tree: dict):
    circles = tree["circles"]
    print(f"{tree['things']} things, dictionary version {tree['dictionary_version']}")
    print("branches:", {circles[b]['label']: f"level {s['level']}, {s['boards_open']} board(s)"
                        for b, s in tree["branches"].items()})
    print(f"\nPROPOSALS (at least {tree['rules']['widening_share_now']:.0%} must widen):")
    for rank, cid in enumerate(tree["proposals"], 1):
        c = circles[cid]
        print(f"  {rank}. {c['label']}  [{c['score']}]  {c['move']}  - needs {what_is_missing(c)}")
    if not tree["proposals"]:
        print("  none")
    print("\nNOT PROPOSED:")
    waiting = [c for c in circles.values() if c["status"] not in ("open", "proposable")]
    for c in sorted(waiting, key=lambda c: -c["score"]):
        reason = c.get("held_by") or (c["decisions"][-1]["why"] if c["decisions"] else "")
        print(f"  {c['label']}  [{c['score']}]  {c['status']}  - needs {what_is_missing(c)}"
              + (f"  ({reason})" if reason else ""))
    print(f"\nTree written to {TREE.name}.")


def main():
    parser = argparse.ArgumentParser(description="The expansion engine. It only proposes.")
    sub = parser.add_subparsers(dest="command")
    decide = sub.add_parser("decide", help="record a decision on a circle")
    decide.add_argument("circle")
    decide.add_argument("--what", required=True)
    decide.add_argument("--why", required=True)
    decide.add_argument("--status", choices=["approved", "rejected", "waiting"])
    decide.add_argument("--retry-when")
    args = parser.parse_args()

    tree = rebuild()
    if args.command == "decide":
        if args.circle not in tree["circles"]:
            raise SystemExit(f"No circle '{args.circle}'. Known: {', '.join(tree['circles'])}")
        decision = {"date": datetime.date.today().isoformat(), "what": args.what, "why": args.why}
        if args.status:
            decision["status"] = args.status
        if args.status == "approved":  # remembered for the rhythm rule once the circle is open
            decision["move"] = tree["circles"][args.circle].get("move", "")
        if args.retry_when:
            decision["retry_when"] = args.retry_when
        tree["circles"][args.circle]["decisions"].append(decision)
        write_json(TREE, tree)
        tree = rebuild()
    show(tree)


if __name__ == "__main__":
    main()
