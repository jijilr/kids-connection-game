"""The end of a branch (the owner's ruling of the evening of 24 Nov 2026).

"for some... you can't go deeper... consider we are on virus... then we reach covid
virus, then we reach say delta varient or omega varient. i think there is no more below
that... therefor that is the end of that brach."

Going deeper means sorting the things of a group into four kinds of four, which needs
sixteen things. A line can stop for three reasons, and they are not the same:

  a true end          the world holds too few such things to sort them further
  no question found   there are enough, but no question sorts them cleanly yet
  the audience's bar  there are enough, but too few that this audience knows

Only the first is an end, and it is decided by counting, not by opinion: the model lists
every such thing that has an article of its own, a second strict call keeps only true
members, and a script checks that each article exists and counts each article once.
Kinds, sorts, breeds, varieties and named examples all count, because a deeper set may
be made of any of them. With what the game already holds, fewer than sixteen: the group
is the end of its branch, and the count and the names are the reason.

Tried on 24 Nov 2026 (Rs 0.2): the planets that go round the Sun are an end (8). The
oceans and the continents were not, until the second call was added: the first call
padded them with seas and with continents of the past.

An end is written on the question that the group is an answer to, in the dictionary:
    "ends": {"<value>": {"on": "...", "why": "...", "run": "..."}}
The game reads it: an end is never a line to follow, and the web shows a leaf on it.
Nothing is deleted when an end is taken back: the mark moves to "ends_taken_back".

    python tools/job/ends.py                      the ends there are, and why
    python tools/job/ends.py reopen CIRCLE --why "..."      take an end back
"""
import datetime
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
for folder in ("tools/research", "tools/content", "tools/catalogue"):
    if str(ROOT / folder) not in sys.path:
        sys.path.insert(0, str(ROOT / folder))
import reslib                                   # noqa: E402
from boards import GROUPS, PER_GROUP            # noqa: E402

DICTIONARY = ROOT / "Assets/data/dictionary.json"
ENOUGH = GROUPS * PER_GROUP     # sixteen: four kinds of four
MOST = 30                       # names asked for; more than enough to reach sixteen

COUNTER = "You list the things of one kind that an encyclopedia has articles about. You answer only with JSON."

COUNT_TASK = """A sorting game holds this group of things: {chain}.
The game has these of them now: {members}.

List the other things that belong to this group and have an encyclopedia article of their own. Kinds, sorts, breeds, varieties and well-known named examples all count, as long as each is a different thing with its own article. Do not list another name for a thing already given, and do not list a part of one.

Give at most {most}, the best known first. If the world holds only a few, give only those. Never pad the list: a short true list is the right answer.

Return JSON: {{"things": ["..."]}}"""


STRICT = "You check a list against a group's name. You are strict and literal. You answer only with JSON."

MEMBER_TASK = """A group in a sorting game is named: {chain}.

For each name below, answer true only if it IS one member of the last group named, as a careful teacher would say. Answer false if it is a different kind of thing, however close (a sea is not an ocean); if it is the group itself or a wider thing; if it is a part of a member; if it is not a thing of today when the group is of today; or if it is only a word for a class of such things.

Return JSON: {{"<name>": true or false}}

Names:
{names}"""


def norm(name: str) -> str:
    return " ".join(str(name).lower().split())


def count_the_world(client, config, spend, chain: str, names: list, with_articles) -> dict:
    """How many things of this group the world holds: what the game has, and whatever
    else has an article of its own. Three keys, and the last is a script's:
      1. the model lists what else belongs to the group;
      2. a second, strict call keeps only true members (the first pads a short list with
         near things: seas among the oceans);
      3. `with_articles(names)` gives back, for each name whose article exists, the
         article's own title. Two names filed under one article are one thing, and so is
         a name filed under an article the game already has by that name."""
    judge = {"provider": "deepseek", "model": config["model"], "thinking": config["thinking"]}
    answer = reslib.ask(client, config, spend, COUNTER,
                        COUNT_TASK.format(chain=chain, members=", ".join(names) or "none yet", most=MOST),
                        dict(judge, most_written=600))
    have, offered = {norm(n) for n in names}, []
    for item in answer.get("things") or []:
        name = str(item).strip()
        if name and norm(name) not in have and norm(name) not in {norm(o) for o in offered}:
            offered.append(name)
    offered = offered[:MOST]
    said = reslib.ask(client, config, spend, STRICT, MEMBER_TASK.format(chain=chain, names="\n".join(offered)),
                      dict(judge, most_written=500)) if offered else {}
    members = [n for n in offered if said.get(n) is True]
    titles = dict(with_articles(members)) if members else {}
    real, seen = [], set(have)
    for name in members:
        title = norm(titles.get(name, ""))
        if title and title not in seen:
            seen.add(title)
            real.append(name)
    return {"in_the_game": list(names), "with_an_article": real,
            "not_members": [n for n in offered if n not in members],
            "no_article": [n for n in members if n not in titles],
            "one_article_twice": [n for n in members if n in titles and n not in real],
            "count": len(names) + len(real)}


def is_end(world: dict) -> bool:
    return world["count"] < ENOUGH


def why(world: dict) -> str:
    known = world["in_the_game"] + world["with_an_article"]
    return (f"the world holds only {world['count']} such things with an article of their own "
            f"({', '.join(known) or 'none'}); sorting them further needs {ENOUGH}")


def mark(dictionary: dict, field: str, value: str, reason: str, run_id: str) -> dict:
    """Write the end on its question. Returns the dictionary, changed in place."""
    dictionary["fields"][field].setdefault("ends", {})[str(value)] = {
        "on": datetime.date.today().isoformat(), "why": reason, "run": run_id}
    return dictionary


def step_of(circles: dict, cid: str):
    """The (field, value) a circle is an answer to, or None for the first place."""
    if cid == "seed" or cid not in circles:
        return None
    parent = cid.rsplit("/", 1)[0] if "/" in cid else "seed"
    field = circles.get(parent, {}).get("sorted_by")
    return (field, cid.rsplit("/", 1)[-1]) if field else None


def end_of(dictionary: dict, circles: dict, cid: str):
    """Why the circle is the end of its branch, or None."""
    step = step_of(circles, cid)
    if step is None:
        return None
    marked = dictionary["fields"].get(step[0], {}).get("ends", {}).get(step[1])
    return (marked.get("why") if isinstance(marked, dict) else str(marked)) if marked else None


def end_circles(dictionary: dict, circles: dict) -> dict:
    """Every circle that is the end of its branch: circle id -> why."""
    return {cid: reason for cid in circles for reason in [end_of(dictionary, circles, cid)] if reason}


def reopen(dictionary: dict, field: str, value: str, reason: str) -> bool:
    """Take an end back. The mark is kept, under "ends_taken_back". True if there was one."""
    ends = dictionary["fields"][field].get("ends", {})
    if str(value) not in ends:
        return False
    was = ends.pop(str(value))
    if not ends:
        dictionary["fields"][field].pop("ends")
    dictionary["fields"][field].setdefault("ends_taken_back", []).append(
        dict(was, value=str(value), taken_back_on=datetime.date.today().isoformat(), taken_back_why=reason))
    return True


def main():
    import expand
    args = sys.argv[1:]
    dictionary = reslib.read_json(DICTIONARY)
    circles = expand.build_circles(dictionary, reslib.read_json(ROOT / "Assets/data/things.json")["things"],
                                   reslib.read_json(ROOT / "Assets/data/settings.json"))
    if args[:1] == ["reopen"]:
        cid = args[1]
        step = step_of(circles, cid)
        reason = args[args.index("--why") + 1] if "--why" in args else ""
        if not reason:
            raise SystemExit('Say why: reopen CIRCLE --why "..."')
        if step is None or not reopen(dictionary, step[0], step[1], reason):
            raise SystemExit(f"'{cid}' is not marked as the end of a branch.")
        reslib.write_json(DICTIONARY, dictionary)
        expand.rebuild()
        print(f"{circles[cid]['label']} is no longer the end of its branch. The mark is kept under ends_taken_back.")
        return
    found = end_circles(dictionary, circles)
    if not found:
        print("No branch has been found to end yet.")
    for cid, reason in found.items():
        print(f"{circles[cid]['label']} ({cid}): {reason}")


if __name__ == "__main__":
    main()
