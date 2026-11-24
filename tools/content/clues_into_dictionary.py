"""Clues live with the kinds they are clues to: in the dictionary, beside each kind's name.

The owner, 24 Nov 2026: "it is a bad habit to have to deal with this - when we create it...
as meta data of classification is extracted. can you look at the meta data, dictionary
entries etc... and add clues parallel to the particular metadata (for classification) we
use when we pick the card as clue? if we don't have this, can you add them yourself?"

Until then a group's clues were written afterwards, by a separate pass that looked at the
things that happened to be in the group that day. So a group that grew could be left with
clues that were no longer true ("comes up to breathe air", once the fish had joined the
wild animals in water), or with none at all. A clue that comes from what DEFINES the kind
is true of every thing that can ever belong to it.

So each question in the dictionary now carries, beside `values`, a `clues` entry: for each
kind a ladder of three, from a gentle hint to nearly there. From now on they are made when
the kind is made (the job asks for them with the question; tools/job/fields.py and
widen.py). This script did the one move that was needed for what was already there:

  - the ladders the game already had, and that were sound, were taken over as they stood;
  - the kinds that had none, and the few whose clues were no longer true of the kind, were
    written by the assistant, by hand, from the kind's own definition (the owner asked for
    exactly that). They are listed in WRITTEN below.

Every ladder is checked with no model before it is kept: three clues, none too long, none
holding the name of a thing of its group. Running it again changes nothing.

    python tools/content/clues_into_dictionary.py           do it, and say what was done
    python tools/content/clues_into_dictionary.py --check   only say what would be done
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
for folder in ("tools/research", "tools/catalogue", "tools/content"):
    if str(ROOT / folder) not in sys.path:
        sys.path.insert(0, str(ROOT / folder))
import catalogue as cat         # noqa: E402
import group_words              # noqa: E402  the check a clue must pass with no model
import reslib                   # noqa: E402

# Written by hand, from what defines the kind. Each is true of every thing that can belong.
WRITTEN = {
    "pet_farm_or_wild": {
        "wild_land": ["Think about an animal that nobody owns.",
                      "Nobody feeds it and nobody keeps it: it finds its own food.",
                      "It lives free, and it lives on land, not in water."],
        "wild_water": ["Think about an animal that is at home where it is wet.",
                       "Nobody feeds it and nobody keeps it: it finds its own food.",
                       "It lives free, in the sea, in a river or a pond, or right beside one."],
    },
    "kind_of_animal": {
        "amphibian": ["Think about an animal that lives two lives.",
                      "It begins its life in water, as a little swimmer with a tail.",
                      "When it grows up it gets legs, and then it can live on land too."],
        "arachnids": ["Think about a small creature with many legs.",
                      "Count its legs: there are eight, not six.",
                      "It has eight legs and no wings, and it is not an insect."],
    },
    "shape_of_the_land": {
        "flat": ["Think about land where you can see far, all around you.",
                 "The ground does not go up, and it does not go down.",
                 "It is wide and level, with no hill and no hole."],
        "by_water": ["Think about a place where the ground meets the wet.",
                     "On one side there is land, and on the other there is water.",
                     "It is the edge of the land, right beside a sea, a river or a lake."],
    },
    "what_people_do_there": {
        "live": ["Think about a place where a family stays.",
                 "People sleep there, cook there, and come back there every day.",
                 "It is somebody's home."],
        "learn": ["Think about a place full of books and questions.",
                  "Children and grown-ups go there to find things out.",
                  "A teacher helps people learn there."],
        "heal": ["Think about a place people go to when they are sick or hurt.",
                 "Doctors and nurses work there.",
                 "People go there to get well again."],
    },
    "how_we_play_with_it": {
        "throw": ["Think about a toy that does not stay in your hands.",
                  "You send it away from you, and someone sends it back.",
                  "You throw it, kick it or hit it, and off it goes."],
        "ride": ["Think about a toy that carries you.",
                 "You climb on it, and it holds you up.",
                 "You sit on it, and you ride, rock or roll along."],
        "wheel": ["Think about a toy that rolls.",
                  "It has wheels, and your hand pushes or pulls it along the floor.",
                  "You do not sit on it: it rolls along on its own little wheels."],
    },
    "part_we_eat": {
        "fruit": ["Think about the part of the plant that holds the seeds.",
                  "It grows where a flower was.",
                  "We eat this part, the one that has the plant's seeds inside it."],
    },
}

# The group of things that have no single answer, at the first question (the owner: "the
# branch in the main node which saying 'hard to classify' (or some apt shorter name)").
HARD_TO_PLACE = {
    "kind_of_thing": {"label": "Hard to place",
                      "clues": ["Think about things that do not fit in just one group.",
                                "They are a little like one kind of thing, and a little like another.",
                                "Even the people who study them do not agree where they belong."]},
}


def main():
    check_only = "--check" in sys.argv[1:]
    dictionary = cat.read_json(cat.DICTIONARY)
    catalogue = cat.load()
    things = cat.game_copy(catalogue)["things"]
    written = catalogue.get("groups", {})
    taken, by_hand, refused, none = 0, 0, [], []
    for field, definition in dictionary["fields"].items():
        if definition.get("merged_into") or not definition.get("sorts_boards", True) or len(definition["values"]) < cat.GROUPS:
            continue
        clues = dict(definition.get("clues") or {})
        for value, label in definition["values"].items():
            names = [t.get("shown_as") or t["name"] for t in things.values() if str(cat.value_of(t, field)).lower() == value]
            group = {"field": field, "value": value, "label": label, "question": definition["wording"]}
            mine = WRITTEN.get(field, {}).get(value)
            old = [c["text"] for c in written.get(cat.group_key(field, value), {}).get("clues", [])]
            ladder = mine or clues.get(value) or old
            if not ladder:
                none.append(f"{label} ({field})")
                continue
            wrong = group_words.clue_problems(ladder, group_words.banned_words(group, names))
            if wrong:
                refused.append(f"{label} ({field}): " + "; ".join(wrong))
                continue
            if clues.get(value) != ladder:
                clues[value] = ladder
                by_hand += bool(mine)
                taken += not mine
        if clues:
            definition["clues"] = {v: clues[v] for v in definition["values"] if v in clues}
        if field in HARD_TO_PLACE:
            definition["in_between"] = HARD_TO_PLACE[field]
    print(f"{taken} ladder(s) taken over as they stood; {by_hand} written by hand from the kind's definition.")
    for line in refused:
        print("  refused by the check: " + line)
    for line in none:
        print("  still without clues: " + line)
    if check_only:
        print("A check only: nothing was changed.")
        return
    reslib.write_json(cat.DICTIONARY, dictionary)
    with cat.changing("clues_into_dictionary.py"):
        pass        # saving the catalogue copies the dictionary's clues to every group a child can meet
    print("The dictionary has them now, and the game's copy was written from it.")


if __name__ == "__main__":
    main()
