"""Fields decided by rules, not by asking the owner (his ruling of 7 Oct 2026).

When a circle has no field to sort it by, DeepSeek proposes up to three, and four tests
decide. A field enters the dictionary only when it passes all four:

  1. four familiar members   every value has at least four things a four-year-old knows:
                             things already in the circle, and new names that pass the
                             familiarity check.
  2. one value each          every thing already in the circle belongs to exactly one
                             value: two checks, worded differently, must both say so and
                             agree. At most one thing in eight may truly fit more than
                             one group; it then lists them and stays off boards sorted by
                             the field, as the dictionary rules. And the groups must have
                             sharp edges: both checks must place at least 85 of every 100
                             names where the proposer did.
  3. one clean solution      sample boards sorted by the field must not also sort cleanly
                             by another field.
  4. not a synonym           it must not ask what an existing field asks in other words,
                             nor split the circle's things the way an existing field does.

A field that fails is recorded with the reason, and is not sent to the owner. The tests
themselves use no model except where a judgement is asked for (tests 1 and 2), and there
two separate calls must agree.
"""
import copy
import re

import reslib
from boards import GROUPS, PER_GROUP, members, second_solution_rate, split

CANDIDATES = 3            # fields asked for in one go
NEW_NAMES = 6             # new things asked for with each value
FAMILIAR_ENOUGH = 0.7
SAME_SPLIT = 0.9          # two fields that agree on this share of the things are one field
# Test 2 was set against the seven fields the owner approved himself (7 Oct 2026): of their
# things, between none and one in nine has no single value by the two checks, and at least
# 89 in 100 are placed as recorded. Sharp fields pass; a field of sizes or colours does not.
ONE_IN = 8                # of the things already in a circle, one in this many may fit more than one group
SHARP_ENOUGH = 0.85       # the share of all names that both checks must place where the proposer did

PROPOSER = "You design sorting questions for a small child's picture game. You answer only with JSON."

PROPOSE_TASK = """A picture game for a four-year-old in India, who cannot read yet. A board shows 16 pictures. The child sorts them into four groups of four, by ONE question.

This part of the game holds: {chain}.
The things in it now: {members}.

Propose {count} different questions that could sort this part into FOUR groups. Best first. A question is good only if ALL of these hold:
- It is a natural four-way split that a four-year-old already knows well. Good ones in this game: vehicles by where they travel (on the road, on rails, on water, in the air); vegetable plants by the part we eat (the fruit, what grows under the ground, the leaves, the seeds or pods).
- Every thing has ONE true answer. Never a question where a thing truly fits two groups. (Refused before: "What do we get from the tree?", because one tree gives fruit, shade and wood.)
- It sorts by what the thing is, does or looks like, not by where someone happens to keep it. (Refused before: "plants in pots".)
- Every thing listed above fits exactly one of your four groups.
- Each group can hold at least five things that such a child knows by sight, counting the ones above.
- A child could tell the answer from a picture, or knows it from daily life.
- It is not one of the questions the game already asks: {existing}.
{earlier}
For each group, put every thing from the list above that belongs in it under "members", spelled exactly as given, and under "new" give {new} more everyday things that belong in it and are not in the list: one or two words each, as a parent names them to a child, no brand names, each looking clearly different in a small picture. Things in this part are named like this: {like}.

Return JSON: {{"fields": [{{"key": "short_snake_case_name", "wording": "The question, as said to the child", "why": "a few words", "values": [{{"key": "snake_case", "label": "The group's name, two to five words", "members": ["..."], "new": ["..."]}}]}}]}}
Each field has exactly four values."""

SORTER = "You answer as a parent sorting picture cards with a four-year-old in India. You answer only with JSON."

SORT_TASK = """A parent and a four-year-old sort picture cards. Every card shows one of: {chain}.
The question: "{wording}"
The piles: {piles}

For each card below, say which ONE pile the parent would put it on. Answer "none" if it fits no pile. Answer "several" if it truly fits more than one pile equally well.

Return JSON: {{"<card>": "<pile key, none or several>"}}

Cards:
{names}"""

CHECKER = "You check a children's sorting game for mistakes. You are strict and literal. You answer only with JSON."

CHECK_TASK = """A sorting game for small children. All the things are: {chain}. They are to be sorted by the question: "{wording}"
The groups: {piles}

For each thing below, list EVERY group it could truthfully be put in. Most things fit exactly one. List two or more only when the thing truly belongs in each of them. List none when it belongs in no group.

Return JSON: {{"<thing>": ["<group key>"]}}

Things:
{names}"""


def norm(text: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", str(text).lower()))


def key_of(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(text).lower()).strip("_")


# ------------------------------------------------------------------ the tests that need no model

def shape_problems(candidate: dict, dictionary: dict) -> list:
    """Four values, each with a key and a short label, and a question."""
    out, values = [], candidate.get("values") or []
    if not norm(candidate.get("wording", "")):
        out.append("it has no question")
    if len(values) != GROUPS:
        out.append(f"it has {len(values)} values, not four")
    keys = [key_of(v.get("key", "")) for v in values if isinstance(v, dict)]
    labels = [norm(v.get("label", "")) for v in values if isinstance(v, dict)]
    if len(set(keys)) != len(values) or "" in keys or len(set(labels)) != len(values) or "" in labels:
        out.append("its values do not each have a key and a label of their own")
    if any(key in ("none", "several", "depends") for key in keys):
        out.append("a value is named none, several or depends")
    return out


def synonym_of(dictionary: dict, things: dict, placed: dict, candidate: dict) -> str:
    """'' when the field is new; else the existing field it repeats, and how.
    `placed` is thing key -> the candidate's value for it, for the things in the circle."""
    wording = norm(candidate["wording"])
    labels = {norm(v["label"]) for v in candidate["values"]}
    for name, definition in dictionary["fields"].items():
        if norm(definition["wording"]) == wording:
            return f"it asks the same question as '{name}': \"{definition['wording']}\""
        shared = labels & {norm(label) for label in definition["values"].values()}
        if len(shared) >= GROUPS - 1:
            return f"its groups are those of '{name}': {', '.join(sorted(shared))}"
    for name in dictionary["fields"]:
        carried = {key: things[key]["fields"][name] for key in placed
                   if not isinstance(things[key]["fields"].get(name), (list, type(None)))}
        if len(carried) < 0.8 * len(placed) or len(set(map(str, carried.values()))) < 2:
            continue      # not carried here, or one value throughout: it cannot be the same split
        if _determines(carried, placed) >= SAME_SPLIT and _determines(placed, carried) >= SAME_SPLIT:
            return f"it splits these things the way '{name}' already does"
    return ""


def _determines(known: dict, other: dict) -> float:
    """The share of things whose `other` value is the usual one for their `known` value."""
    by_value = {}
    for key, value in known.items():
        if key in other:
            by_value.setdefault(str(value), []).append(str(other[key]))
    total = sum(len(v) for v in by_value.values())
    return sum(max(v.count(x) for x in set(v)) for v in by_value.values()) / total if total else 0.0


def one_value_each(names: list, first: dict, second: dict, values: list, labels: dict = None) -> tuple:
    """Two separate sortings of the same things. A thing is placed only when both give it
    the same single value. An answer may name a group by its key or by its label.
    Returns (name -> value, name -> why it is not placed)."""
    placed, unclear = {}, {}
    known = {v: v for v in values}
    known.update({key_of(label): v for v, label in (labels or {}).items()})
    for name in names:
        a = key_of(first.get(name, ""))
        a = known.get(a, a)
        b = second.get(name)
        b = [key_of(x) for x in b] if isinstance(b, list) else [key_of(b)] if isinstance(b, str) else []
        b = list(dict.fromkeys(known[x] for x in b if x in known))
        if a in values and b == [a]:
            placed[name] = a
        elif a == "several" or len(b) > 1:
            unclear[name] = "it fits more than one group" + (f": {' and '.join(b)}" if len(b) > 1 else "")
        elif a == "none" or (a not in values and not b):
            unclear[name] = "it fits no group"
        else:
            unclear[name] = f"the two checks disagree: '{a}' and '{' and '.join(b) or 'none'}'"
    return placed, unclear


def values_named(name: str, first: dict, second: dict, values: list, labels: dict = None) -> list:
    """Every value either check named for a thing: what it lists when it has no single one."""
    known = {v: v for v in values}
    known.update({key_of(label): v for v, label in (labels or {}).items()})
    b = second.get(name)
    b = [key_of(x) for x in b] if isinstance(b, list) else [key_of(b)] if isinstance(b, str) else []
    named = [known.get(key_of(first.get(name, "")))] + [known.get(x) for x in b]
    return list(dict.fromkeys(v for v in named if v))


def boards_clean(dictionary: dict, things: dict, path: list, field: str, definition: dict,
                 placed: dict, new: dict, limit: float) -> str:
    """'' when sample boards sorted by the field have one clean solution often enough.
    `placed`: thing key -> value for things in the game; `new`: new name -> value."""
    trial_dictionary = copy.deepcopy(dictionary)
    trial_dictionary["fields"][field] = definition
    trial = copy.deepcopy(things)
    for key, value in placed.items():
        trial[key]["fields"][field] = value
    for name, value in new.items():
        trial["new:" + key_of(name)] = {"name": name, "fields": {**dict(path), field: value}}
    groups = split(trial, members(trial, path), field)
    if sum(1 for keys in groups.values() if len(keys) >= PER_GROUP) < GROUPS:
        return "fewer than four of its groups can be filled"
    rate = second_solution_rate(trial_dictionary, trial, groups, field)
    return f"{rate:.0%} of sample boards also sort cleanly by another field" if rate > limit else ""


# ------------------------------------------------------------------ the calls

def options(config: dict, most: int) -> dict:
    return {"provider": "deepseek", "model": config["model"], "thinking": config["thinking"], "most_written": most}


def propose(client, config, spend, dictionary: dict, chain: str, names: list, earlier: list, like: list) -> list:
    """Up to three candidate fields from DeepSeek, tidied. `earlier` are fields refused
    for this circle before, each with its reason, so the same one is not offered again."""
    existing = "; ".join(f'"{d["wording"]}"' for d in dictionary["fields"].values())
    before = ("- These were tried for this part before and refused, so propose different ones: "
              + "; ".join(earlier) + ".\n") if earlier else ""
    answer = reslib.ask(client, config, spend, PROPOSER, PROPOSE_TASK.format(
        chain=chain, members=", ".join(names), count=CANDIDATES, new=NEW_NAMES, existing=existing, earlier=before,
        like=", ".join(like[:8]) or "plain everyday names"), options(config, 2600))
    found = []
    for raw in answer.get("fields") or []:
        if not isinstance(raw, dict) or not isinstance(raw.get("values"), list):
            continue
        values = []
        for value in raw["values"]:
            if isinstance(value, dict):
                clean = lambda items: [str(x).strip() for x in items or [] if str(x).strip()]
                values.append({"key": key_of(value.get("key", "")), "label": str(value.get("label", "")).strip(),
                               "members": clean(value.get("members")), "new": clean(value.get("new"))})
        found.append({"key": key_of(raw.get("key", "")), "wording": str(raw.get("wording", "")).strip(),
                      "why": str(raw.get("why", "")).strip(), "values": values})
    return found[:CANDIDATES]


def sort_twice(client, config, spend, chain: str, candidate: dict, names: list) -> tuple:
    """The same things sorted by two calls that share no wording: a parent putting each
    card on one pile, and a checker listing every group a thing could go in."""
    piles = "; ".join(f'{v["key"]} = "{v["label"]}"' + (f' (such as {", ".join(v["such_as"])})' if v.get("such_as") else "")
                      for v in candidate["values"])
    listing = "\n".join(names)
    most = 200 + 25 * len(names)
    first = reslib.ask(client, config, spend, SORTER, SORT_TASK.format(
        chain=chain, wording=candidate["wording"], piles=piles, names=listing), options(config, most))
    second = reslib.ask(client, config, spend, CHECKER, CHECK_TASK.format(
        chain=chain, wording=candidate["wording"], piles=piles, names=listing), options(config, most + 100))
    return first, second


def test(client, config, spend, dictionary: dict, things: dict, taken: set, path: list, chain: str,
         candidate: dict, recognise, limit: float) -> dict:
    """Run one candidate through the four tests. Returns what was found, with `why` empty
    when it passed. `things` is the game's copy; `taken` are names recorded anywhere."""
    result = {"field": candidate["key"], "wording": candidate["wording"], "why": [], "placed": {}, "new": {},
              "values": {v["key"]: v["label"] for v in candidate["values"] if isinstance(v, dict)}}
    result["why"] = shape_problems(candidate, dictionary)
    if result["why"]:
        return result
    keys = members(things, path)
    names = {things[k]["name"]: k for k in keys}
    values = [v["key"] for v in candidate["values"]]
    offered = {}        # new name -> the value the proposer gave it
    for value in candidate["values"]:
        for name in value["new"]:
            name = name[0].upper() + name[1:]
            if key_of(name) not in taken and name not in names and name not in offered:
                offered[name] = value["key"]

    # 2. one value each, for the things already there and for the new names alike
    first, second = sort_twice(client, config, spend, chain, candidate, list(names) + list(offered))
    everything = list(names) + list(offered)
    placed, unclear = one_value_each(everything, first, second, values, result["values"])
    result["placed"] = {names[n]: v for n, v in placed.items() if n in names}
    # a thing already there with no single value: it may list two or more and stay off the
    # board, if only a few do. One that fits no group at all cannot be recorded.
    several, lost = {}, {}
    for name in names:
        if name in unclear:
            named = values_named(name, first, second, values, result["values"])
            if len(named) >= 2:
                several[name] = named
            else:
                lost[name] = unclear[name]
    result["several"] = {names[n]: v for n, v in several.items()}
    if lost:
        result["why"].append("not every thing has a value: " + "; ".join(f"{n} - {why}" for n, why in lost.items()))
        return result
    allowed = len(names) // ONE_IN
    if len(several) > allowed:
        result["why"].append(
            f"not every thing has one value: {len(several)} of the {len(names)} things there fit more than one group, "
            f"and at most {allowed} may (" + "; ".join(f"{n}: {' and '.join(v)}" for n, v in several.items()) + ")")
        return result
    # the proposer's own sorting is a third opinion: where both checks often put a thing in
    # another group than it did, the groups have no sharp edges (a crow: big, or small?)
    said = {name: value["key"] for value in candidate["values"] for name in value["members"]}
    said.update(offered)
    moved = {n: (said[n], placed.get(n)) for n in everything if n in said and placed.get(n) != said[n]}
    result["sharpness"] = round(1 - len(moved) / len(everything), 2)
    if result["sharpness"] < SHARP_ENOUGH:
        shown = "; ".join(f"{n}: '{a}' or '{b or 'no one group'}'" for n, (a, b) in list(moved.items())[:4])
        result["why"].append(f"its groups have no sharp edges: both checks placed only {result['sharpness']:.0%} of the "
                             f"things where the proposer did ({shown})")
        return result

    # 4. not a synonym (before any more is spent)
    same = synonym_of(dictionary, things, result["placed"], candidate)
    if same:
        result["why"].append("it is not a new field: " + same)
        return result

    # 1. four familiar members for each value. A new name counts only if it is a thing of this
    #    circle at all (a toy, not an orange): two checks sort it among the circle's own neighbours.
    new = [{"name": n, "value": v, "familiar": 1.0} for n, v in placed.items() if n in offered]
    if new:
        parent_field, here = path[-1]
        parent = dictionary["fields"][parent_field]
        beside = [t for t in things.values() if all(t["fields"].get(f) == v for f, v in path[:-1])]
        neighbours = {"wording": parent["wording"], "values": [
            {"key": str(v), "label": label, "such_as": [t["name"] for t in beside if t["fields"].get(parent_field) == v][:4]}
            for v, label in parent["values"].items()]}
        above = " > ".join(dictionary["fields"][f]["values"][str(v)] for f, v in path[:-1]) or "things of every kind"
        a, b = sort_twice(client, config, spend, above, neighbours, [o["name"] for o in new])
        belongs, _ = one_value_each([o["name"] for o in new], a, b, [v["key"] for v in neighbours["values"]],
                                    {v["key"]: v["label"] for v in neighbours["values"]})
        result["not_of_this_circle"] = [o["name"] for o in new if belongs.get(o["name"]) != str(here)]
        new = [o for o in new if belongs.get(o["name"]) == str(here)]
    for value in candidate["values"]:
        batch = [o for o in new if o["value"] == value["key"]]
        recognise(client, config, spend, {"chain": f"{chain} > {value['label']}"}, batch)
    known = [o for o in new if o.get("recognised") and o.get("suitable") and o["familiar"] >= FAMILIAR_ENOUGH]
    result["new"] = {o["name"]: {"value": o["value"], "familiar": o["familiar"]} for o in known}
    result["unsuitable"] = [o["name"] for o in new if o.get("suitable") is False]
    counts = {v: sum(1 for x in result["placed"].values() if x == v) + sum(1 for o in known if o["value"] == v)
              for v in values}
    result["counts"] = counts
    short = {v: n for v, n in counts.items() if n < PER_GROUP}
    if short:
        label = result["values"]
        result["why"].append("not every value has four familiar things: "
                             + ", ".join(f"'{label[v]}' has {n}" for v, n in short.items()))
        return result

    # 3. one clean solution
    definition = {"wording": candidate["wording"], "meaning": "everyday", "values": result["values"],
                  "expected_on": dict(path[-1:]), "since": dictionary["version"] + 1}
    clash = boards_clean(dictionary, things, path, candidate["key"], definition, result["placed"],
                         {name: o["value"] for name, o in result["new"].items()}, limit)
    if clash:
        result["why"].append("sample boards fail the one-solution test: " + clash)
    result["definition"] = definition
    return result


def unique_key(dictionary: dict, wanted: str, path: list) -> str:
    """A field name of its own: the proposer's, with the circle's name added if taken."""
    key = wanted or "kind"
    if key in dictionary["fields"]:
        key = f"{key}_of_{path[-1][1]}"
    while key in dictionary["fields"]:
        key += "_2"
    return key
