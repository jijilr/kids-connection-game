"""The map: one record for each place of the game, built by one program.

The owner, 24 Nov 2026: "don't we have some kind of json with meta data of each node?...
that is the nerve system of the whole thing." (DESIGN.md, section 13.)

Until now three programs each worked the places out for themselves, by their own copy of
the rules: the game (lib/services/board_assembler.dart), the job and the helper
(tools/content/expand.py: build_circles). They had drifted apart. The game opened "Wild
animals on land" across all animals; the helper had never heard of it and told the game
to drop it. What was decided about a place lay in three files.

This file is the one builder. It reads the master records (the things in the game, the
dictionary, the settings, the decisions kept in the engine's tree, the words of each
group) and writes Assets/data/places.json: every place, the circles it lies in, the
places one circle wider, the questions asked there with their kinds, its state and the
reason, and its history. Nobody edits that file. It is written again whenever the
catalogue is saved or the engine's tree is rebuilt.

Step 1 (24 Nov 2026): the map was built and checked against the game, place by place.
Step 2 (the same night): the game reads the map and has dropped its own copy of these
rules. They are written once now, here. Step 3 does the same for the helper and the job.

The rules, as the game has them:
  - A place is where circles overlap. It is named by the answers that define it, in the
    dictionary's order, whatever the road that led there.
  - A question is asked at a place when it can fill a set there (four kinds with four
    things each) and either every thing of the place answers it, or the place is the
    question's home: the smallest place that holds every thing that answers it.
  - A thing with no single answer (it lists several, or is marked "depends") is "in
    between" for that question.
  - A kind held back in the settings is left out everywhere.

    python tools/catalogue/places.py              build the map and say what it holds
    python tools/catalogue/places.py show PLACE   one place's record
    python tools/catalogue/places.py for FILE     print the map of a made-up game (for the game's tests)
"""
import datetime
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / "Assets/data"
PLACES = DATA / "places.json"
TREE = ROOT / "tools/content/expansion_tree.json"
CATALOGUE = ROOT / "tools/catalogue/catalogue.json"
IN_BETWEEN = "in_between"
GROUPS, PER_GROUP = 4, 4
DEEPEST = 6


def read_json(path, default=None):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


class World:
    """The game's data, with the rules that say what a place is and what is asked there."""

    def __init__(self, dictionary: dict, things: dict, settings: dict, styles: list):
        self.settings = settings
        self.things = things                                    # id -> {"name", "fields", ...}, in the game's order
        self.styles = styles                                    # the ways a tile can be drawn: each a set of thing ids
        self.held_back = {field: {str(v) for v in values} for field, values in settings.get("hold_back", {}).items()}
        self.fields = {}                                        # the questions the game sees, in the dictionary's order
        for name, definition in dictionary["fields"].items():
            if definition.get("merged_into"):
                continue
            values = dict(definition.get("values", {}))
            sorts = definition.get("sorts_boards", True)
            kinds = list(values)
            if sorts and len(values) >= GROUPS and IN_BETWEEN not in values:
                own = definition.get("in_between")
                values[IN_BETWEEN] = own["label"] if isinstance(own, dict) and own.get("label") else "In between"
            self.fields[name] = {"wording": definition.get("wording", ""), "values": values, "kinds": kinds, "sorts": sorts}
        self.position = {name: i for i, name in enumerate(self.fields)}
        self.start = settings["start"]["field"]
        self._asked = {}

    # -- a thing's answer
    def answer(self, key: str, field: str):
        value = self.things[key]["fields"].get(field)
        if value is None:
            return None
        if value == "depends" or (isinstance(value, list) and len(value) > 1):
            return IN_BETWEEN
        if isinstance(value, list):
            return str(value[0]) if value else None
        return str(value).lower() if isinstance(value, bool) else str(value)

    def held(self, key: str) -> bool:
        return any(self.answer(key, field) in values for field, values in self.held_back.items())

    def inside(self, circles: list) -> list:
        """The things of a place: every thing not held back that gives each of its answers."""
        return [k for k in self.things if not self.held(k) and all(self.answer(k, f) == v for f, v in circles)]

    # -- what a place is
    def canon(self, circles: list) -> list:
        return sorted(circles, key=lambda step: self.position.get(step[0], len(self.position)))

    @staticmethod
    def name_of(circles: list) -> str:
        return "/".join(v for _, v in circles) or "seed"

    # -- what is asked there
    def can_sort(self, circles: list) -> list:
        """Questions that can fill a set at a place: four of their kinds have four things each."""
        pool, out = self.inside(circles), []
        for name, field in self.fields.items():
            if not field["sorts"]:
                continue
            counts = {}
            for key in pool:
                value = self.answer(key, name)
                if value is not None and value != IN_BETWEEN and value in field["values"]:
                    counts[value] = counts.get(value, 0) + 1
            if sum(1 for n in counts.values() if n >= PER_GROUP) >= GROUPS:
                out.append(name)
        return out

    def asked_at(self, circles: list) -> list:
        """The questions asked at a place: (question, why it is asked here), the first being
        the one the place has always had."""
        key = "/".join(f"{f}={v}" for f, v in circles)
        if key in self._asked:
            return self._asked[key]
        taken = {f for f, _ in circles}
        able = [q for q in self.can_sort(circles) if q not in taken]
        pool = self.inside(circles)
        whole = [q for q in able if all(q in self.things[k]["fields"] for k in pool)]
        everything = self.inside([])
        at_home = []
        for q in able:
            if q in whole:
                continue
            answers = [k for k in everything if q in self.things[k]["fields"]]
            if not all(all(self.answer(k, f) == v for f, v in circles) for k in answers):
                continue        # some thing that answers it lies outside this place: its home is higher up
            lower = any(self.answer(answers[0], w) is not None
                        and all(self.answer(k, w) == self.answer(answers[0], w) for k in answers) for w in whole)
            if not lower:       # no one answer to a question about the whole place holds them all
                at_home.append(q)
        asked = [(q, "every thing here answers it") for q in whole] + [(q, "its home is here") for q in at_home]
        if not asked:
            asked = [(q, "the first that can fill a set here") for q in self.can_sort(circles)[:1]]
        if not circles:         # the first set has its own question, first
            asked = [(self.start, "the first set")] + [a for a in asked if a[0] != self.start]
        self._asked[key] = asked
        return asked

    def shown_counts(self, circles: list, question: str, style) -> dict:
        """kind -> how many of its things here can be shown in a style (None: by name only)."""
        counts = {}
        for key in self.inside(circles):
            value = self.answer(key, question)
            if value is not None and value in self.fields[question]["values"] and (style is None or key in style):
                counts[value] = counts.get(value, 0) + 1
        return counts

    def makes_a_picture_set(self, circles: list, question: str) -> bool:
        return any(sum(1 for v, n in self.shown_counts(circles, question, style).items()
                       if v != IN_BETWEEN and n >= PER_GROUP) >= GROUPS for style in self.styles)

    def kinds_ready(self, circles: list, question: str) -> list:
        """The kinds that can be a group of a set here now, in the style such a set is drawn in."""
        for style in list(self.styles) + [None]:
            ready = [v for v, n in self.shown_counts(circles, question, style).items() if n >= PER_GROUP]
            if sum(1 for v in ready if v != IN_BETWEEN) >= GROUPS:
                return ready
        return []


def styles_on_disk(things: dict) -> list:
    """The ways a tile can be drawn, best first, as the game has them: its own drawn picture,
    an older photograph, an emoji. Each as the set of things that can be drawn that way."""
    pictures = read_json(DATA / "pictures.json", {}) or {}
    names, emoji = pictures.get("file_names", {}), pictures.get("emoji", {})
    art = {k for k in things if (ROOT / f"Assets/pictures/{k}.webp").exists()}
    photo = {k for k in things if (ROOT / f"Assets/{names.get(k, k)}_1.png").exists()}
    return [art, photo, {k for k in things if k in emoji}]


def build(dictionary: dict = None, things: dict = None, settings: dict = None, styles: list = None,
          tree: dict = None, words: dict = None) -> dict:
    """The map, from the master records as they stand on disk (or as given, for a test)."""
    dictionary = dictionary or read_json(DATA / "dictionary.json")
    things = things if things is not None else read_json(DATA / "things.json")["things"]
    settings = settings or read_json(DATA / "settings.json")
    world = World(dictionary, things, settings, styles if styles is not None else styles_on_disk(things))
    tree = tree if tree is not None else (read_json(TREE, {}) or {}).get("circles", {})
    words = words if words is not None else (read_json(CATALOGUE, {}) or {}).get("groups", {})
    need_pictures = settings.get("boards_need_pictures", False)
    ends = dictionary.get("ends", {})

    # every place: the first, then each answer to each question asked at a place, as deep as it goes
    places, level = {"seed": []}, [[]]
    for _ in range(DEEPEST):
        following = []
        for circles in level:
            for question, _ in world.asked_at(circles):
                for value in world.fields[question]["values"]:
                    child = world.canon(circles + [(question, value)])
                    name = world.name_of(child)
                    if name in places:
                        continue
                    # an empty overlap is no place, unless the job knows it as one still to be filled
                    if name not in tree and not world.inside(child):
                        continue
                    places[name] = child
                    if world.asked_at(child):
                        following.append(child)
        level = following

    records = {}
    for name, circles in places.items():
        pool = world.inside(circles)
        asks = []
        for question, why in world.asked_at(circles):
            field = world.fields[question]
            ready = set(world.kinds_ready(circles, question))
            counts = world.shown_counts(circles, question, None)
            drawn = world.shown_counts(circles, question, world.styles[0]) if world.styles else {}
            kinds = {}
            for value in field["kinds"]:
                if value in world.held_back.get(question, ()):
                    continue        # held back in the settings: left out everywhere
                group = words.get(f"{question}={value}", {})
                kinds[value] = {"name": field["values"][value], "things": counts.get(value, 0),
                                "with_pictures": drawn.get(value, 0), "ready": value in ready,
                                "place": world.name_of(world.canon(circles + [(question, value)])),
                                "clues": len(group.get("clues") or []),
                                "explanation": bool((group.get("explanation") or {}).get("text"))}
            asks.append({"question": question, "wording": field["wording"], "asked_because": why,
                         "makes_a_set": world.makes_a_picture_set(circles, question) if need_pictures else len(ready) >= GROUPS,
                         "kinds": kinds, "in_between": counts.get(IN_BETWEEN, 0),
                         "in_between_ready": IN_BETWEEN in ready,
                         "in_between_place": world.name_of(world.canon(circles + [(question, IN_BETWEEN)]))
                         if IN_BETWEEN in field["values"] else None})
        # the places one circle wider, with the answer this place adds to each: a fact about the
        # circles. And, of those, the places where a question leads here: a road to it.
        wider, roads = {}, []
        for i, step in enumerate(circles):
            rest = circles[:i] + circles[i + 1:]
            if world.name_of(rest) in places:
                wider[world.name_of(rest)] = list(step)
                if any(q == step[0] for q, _ in world.asked_at(rest)):
                    roads.append(world.name_of(rest))
        old = tree.get(name, {})
        ready = any(a["makes_a_set"] for a in asks)
        if name in ends:
            mark = ends[name]
            state, why = "end", mark.get("why", "") if isinstance(mark, dict) else str(mark)
        elif ready:
            state, why = "ready", ""
        elif old.get("status") in ("held", "rejected", "end"):
            state, why = "held", old.get("held_by") or ("the owner rejected it" if old["status"] == "rejected" else "")
        elif old:
            state, why = "can be made", "the job may prepare it: " + str(old.get("status", ""))
        else:
            state, why = "a group only", ("it has no set of its own, and it exists only where circles cross: "
                                          "the job does not know such places yet")
        last = circles[-1] if circles else None
        records[name] = {
            "name": world.fields[last[0]]["values"].get(last[1], last[1]) if last else settings["start"]["label"],
            "circles": [list(step) for step in circles],
            "depth": len(circles),
            "lies_in": wider,
            "reached_from": roads,
            "things": len(pool),
            "with_pictures": sum(1 for k in pool if world.styles and k in world.styles[0]),
            "asks": asks,
            "state": state,
            "why": why,
            "known_to_the_job": name in tree,
            "history": old.get("decisions", []),
        }
    counts = {}
    for record in records.values():
        counts[record["state"]] = counts.get(record["state"], 0) + 1
    return {
        "about": "The map: one record for each place of the game. Built by tools/catalogue/places.py from the "
                 "things, the dictionary, the settings and the decisions on record, whenever any of them "
                 "changes. Nobody edits it. A place is where circles overlap; its name is the answers that "
                 "define it, in the dictionary's order.",
        "built_on": datetime.date.today().isoformat(),
        "dictionary_version": dictionary.get("version"),
        "things": len(things),
        "start": "seed",
        "places_by_state": counts,
        "places": records,
    }


def write() -> dict:
    """Build the map from what is on disk and write it. Returns it."""
    the_map = build()
    old = read_json(PLACES)
    if old is not None and {k: v for k, v in old.items() if k != "built_on"} == {k: v for k, v in the_map.items() if k != "built_on"}:
        return old          # nothing has changed: the file, and its date, stay as they are
    PLACES.write_text(json.dumps(the_map, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    return the_map


def main():
    args = sys.argv[1:]
    if args[:1] == ["for"]:
        # The map of a made-up game, for a test: FILE holds {"dictionary", "things", "settings"}.
        # Printed, never written. The game's own tests ask for their maps this way, so that
        # the rules of what a place is are written once, here.
        world = read_json(args[1])
        print(json.dumps(build(world["dictionary"], world["things"], world["settings"], styles=[], tree={}, words={})))
        return
    the_map = write()
    places = the_map["places"]
    if args[:1] == ["show"]:
        if len(args) < 2 or args[1] not in places:
            raise SystemExit("No such place. Run without arguments for the list.")
        print(json.dumps(places[args[1]], indent=1, ensure_ascii=False))
        return
    print(f"The map holds {len(places)} places: " + ", ".join(f"{n} {state}" for state, n in the_map["places_by_state"].items()) + ".")
    for name, record in places.items():
        asks = "; ".join(f'"{a["wording"]}"' + ("" if a["makes_a_set"] else " (no set yet)") for a in record["asks"])
        roads = "" if len(record["lies_in"]) < 2 else f"  [lies in {len(record['lies_in'])} places]"
        print(f"  {'  ' * record['depth']}{record['name']} ({name}): {record['state']}, {record['things']} things"
              + (f". Asks: {asks}" if asks else "") + roads)


if __name__ == "__main__":
    main()
