"""Board rules shared by the content scripts. The game applies the same rules in Dart
(lib/services/board_assembler.dart); keep the two in step.

A board is one field, four of its values, and four things for each value.
"""
import random

GROUPS = 4
PER_GROUP = 4


def value_of(thing: dict, field: str):
    """A thing's single value for a field, or None. A thing marked "depends", or one
    that lists several values, never takes part in a board sorted by that field."""
    value = thing["fields"].get(field)
    return None if value is None or value == "depends" or isinstance(value, list) else value


def members(things: dict, path: list) -> list:
    """Keys of the things inside a circle, given the (field, value) steps that lead to it."""
    return [key for key, thing in things.items()
            if all(thing["fields"].get(field) == value for field, value in path)]


def boardable_fields(dictionary: dict) -> list:
    """Fields that could ever fill a board: allowed to sort one, with four or more values."""
    return [name for name, definition in dictionary["fields"].items()
            if definition.get("sorts_boards", True) and len(definition["values"]) >= GROUPS]


def sub_kind(dictionary: dict, things: dict, keys: list, path: list, parent_field: str):
    """The field that splits a circle into sub-kinds: one that could sort a board of its
    own and that every member carries (kind of animal, for Animals)."""
    used = {field for field, _ in path} | {parent_field}
    for name in boardable_fields(dictionary):
        if name in used:
            continue
        if keys and all(name in things[k]["fields"] for k in keys):
            return name
    return None


def split(things: dict, keys: list, field: str) -> dict:
    """value -> keys, for the members that carry the field."""
    groups = {}
    for key in keys:
        value = value_of(things[key], field)
        if value is not None:
            groups.setdefault(value, []).append(key)
    return groups


def second_solution(dictionary: dict, things: dict, tiles: list, sorted_by: str):
    """Another field that ALSO splits these 16 tiles cleanly four by four, or None.
    Every stored field is tried, not only the ones that sort boards."""
    for name, definition in dictionary["fields"].items():
        if name == sorted_by or len(definition["values"]) < GROUPS:
            continue
        groups = split(things, tiles, name)
        counted = sum(len(g) for g in groups.values())
        if counted == len(tiles) and len(groups) == GROUPS \
                and all(len(g) == PER_GROUP for g in groups.values()):
            return name
    return None


def make_board(dictionary: dict, things: dict, path: list, field: str = None, avoid: set = (),
               rng: random.Random = None, tries: int = 20):
    """THE way a board is made (the owner's ruling of 7 Oct 2026): sixteen things in four
    groups of four, sorted by one field, with exactly one clean solution, from what the
    game already holds. The game does the same in BoardAssembler.makeBoard; this is the
    worker's copy, so that it can tell what a child would meet. `avoid` are the sixteen
    of the board just played. Returns {"field", "groups": {value: [keys]}, "tiles"}, or
    None when the circle cannot fill such a board. It never pads a group and never sorts
    by a shallower field to make a board possible."""
    rng = rng or random.Random(0)
    keys = members(things, path)
    field = field or sub_kind(dictionary, things, keys, path, path[-1][0] if path else None)
    if field is None or not dictionary["fields"][field].get("sorts_boards", True):
        return None
    groups = split(things, keys, field)
    full = [value for value, inside in groups.items() if len(inside) >= PER_GROUP]
    if len(full) < GROUPS:
        return None
    board = None
    for _ in range(tries):
        chosen = {value: rng.sample(groups[value], PER_GROUP) for value in rng.sample(full, GROUPS)}
        tiles = [key for inside in chosen.values() for key in inside]
        if second_solution(dictionary, things, tiles, field):
            continue
        board = {"field": field, "groups": chosen, "tiles": tiles}
        if set(tiles) != set(avoid):
            break
    return board


def second_solution_rate(dictionary: dict, things: dict, groups: dict, sorted_by: str,
                         samples: int = 200) -> float:
    """Share of random boards over these groups that have a second clean solution.
    The game rebuilds such boards, so a low rate is fine; a high one means the circle
    cannot really open."""
    full = [value for value, keys in groups.items() if len(keys) >= PER_GROUP]
    if len(full) < GROUPS:
        return 1.0
    rng = random.Random(0)  # same answer every run
    ambiguous = 0
    for _ in range(samples):
        tiles = [key for value in rng.sample(full, GROUPS)
                 for key in rng.sample(groups[value], PER_GROUP)]
        if second_solution(dictionary, things, tiles, sorted_by):
            ambiguous += 1
    return ambiguous / samples
