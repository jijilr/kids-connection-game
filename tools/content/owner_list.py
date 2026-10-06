"""Apply what the owner supplied or ruled directly. Nothing here is drafted or guessed by AI.

- The dinosaur branch is the first child's own list (given 6 Oct 2026): the names he
  knows, grouped the way the owner grouped them.
- His snakes are added to the reptiles.
- Things the owner ruled out are removed and stay out on later drafts.
- Candidates the owner has still to choose between go to the review queue.

`name` keeps the full scientific name; `shown_as` is how the child says it, used on
tiles and by the voice.

    python tools/content/owner_list.py
"""
from lib import DICTIONARY, THINGS, read_json, set_queue, slug, write_json

SOURCE = "owner:list"

# kind_of_dinosaur -> (dinosaur_academic, names)
DINOSAURS = {
    "land_hunter": (True, ["Tyrannosaurus rex", "Giganotosaurus", "Velociraptor", "Allosaurus", "Spinosaurus"]),
    "land_grazer": (True, ["Brachiosaurus", "Brontosaurus", "Diplodocus", "Argentinosaurus", "Amargasaurus",
                           "Triceratops", "Ankylosaurus", "Stegosaurus", "Pachycephalosaurus", "Parasaurolophus"]),
    "swimmer": (False, ["Mosasaurus", "Kronosaurus", "Mixosaurus", "Tylosaurus", "Plesiosaurus", "Elasmosaurus"]),
    "flyer": (False, ["Pterodactylus", "Pteranodon", "Quetzalcoatlus"]),
}

# name -> extinct
SNAKES = {"Anaconda": False, "Python": False, "Titanoboa": True, "Vasuki indicus": True}

# kind_of_plant -> names. The owner chose these when he ruled on the plants field.
PLANTS = {
    "grass_grain": ["Wheat", "Sugarcane", "Bamboo"],
    "vegetable": ["Tomato plant", "Brinjal plant", "Chilli plant", "Pumpkin plant"],
}

SHOWN_AS = {"Tyrannosaurus rex": "T. rex", "Pterodactylus": "Pterodactyl"}

# A note is keyed by the field it is about, or "general" when it is about the thing itself.
NOTES = {
    "Spinosaurus": {"kind_of_dinosaur": "Scientists debate how much time Spinosaurus spent in water."},
    "Vasuki indicus": {"general": "Its length is estimated from fossil backbones, so it is uncertain. "
                                  "Its picture is drawn like a very large python, the living snake scientists "
                                  "model it on; what it really looked like is not known."},
    "Titanoboa": {"general": "Its picture is drawn like a giant boa or anaconda, its closest living relatives; "
                             "what it really looked like is not known."},
}

# The owner knows the child. These kinds of thing are familiar to him, and the checker
# is told so: it had been judging familiarity too strictly.
FAMILIAR_KINDS = ["turtles", "tortoises", "crocodiles", "lizards", "chameleons"]

# Ruled out by the owner; removed here and skipped by check.py on later runs.
EXCLUDED = {
    "salmon": "not familiar enough to a four-year-old",
    "tuna": "not familiar enough to a four-year-old",
    "swordfish": "not familiar enough to a four-year-old",
}

# Must be present after the exclusions (the owner's well-known fish).
REQUIRED = ["goldfish", "shark", "clownfish"]

# Waiting for the owner: the first child picks one as the fourth flyer; the other stays here.
FLYER_CANDIDATES = ["Rhamphorhynchus", "Dimorphodon"]

# Waiting for a field, or a board, that does not exist yet.
WAITING = {
    "Basilisk": "needs a field for real versus story creatures before it can be added",
    "Cactus": "a plant the owner is keeping for a later board",
    "Tulsi": "a plant the owner is keeping for a later board",
    "Money plant": "a plant the owner is keeping for a later board",
    "Aloe vera": "a plant the owner is keeping for a later board",
}


def dinosaur(kind: str, academic: bool) -> dict:
    return {"kind_of_thing": "animal", "kind_of_animal": "dinosaur",
            "dinosaur_academic": academic, "kind_of_dinosaur": kind, "extinct": True}


def record(name: str, fields: dict, version: int) -> dict:
    thing = {"name": name, "fields": fields, "familiar": 1.0, "reviewed": version, "source": SOURCE}
    if name in SHOWN_AS:
        thing["shown_as"] = SHOWN_AS[name]
    if name in NOTES:
        thing["notes"] = NOTES[name]
    return thing


def main():
    dictionary = read_json(DICTIONARY)
    version = dictionary["version"]
    store = read_json(THINGS, {"dictionary_version": version, "things": {}})
    things = {k: v for k, v in store["things"].items() if v.get("source") != SOURCE}

    for kind, (academic, names) in DINOSAURS.items():
        for name in names:
            things[slug(name)] = record(name, dinosaur(kind, academic), version)
    for name, extinct in SNAKES.items():
        fields = {"kind_of_thing": "animal", "kind_of_animal": "reptile", "extinct": extinct}
        things[slug(name)] = record(name, fields, version)
    for kind, names in PLANTS.items():
        for name in names:
            fields = {"kind_of_thing": "plant", "extinct": False, "kind_of_plant": kind}
            things[slug(name)] = record(name, fields, version)

    removed = [key for key in EXCLUDED if things.pop(key, None) is not None]
    missing = [key for key in REQUIRED if key not in things]

    store["things"] = things
    write_json(THINGS, store)
    set_queue("owner", [
        {"name": name, "fields": dinosaur("flyer", False),
         "why": ["candidate for the fourth flyer: the first child chooses one, the other stays here"]}
        for name in FLYER_CANDIDATES
    ] + [{"name": name, "fields": {}, "why": [why]} for name, why in WAITING.items()])

    added = (sum(len(names) for _, names in DINOSAURS.values()) + len(SNAKES)
             + sum(len(names) for names in PLANTS.values()))
    print(f"Owner's list: {added} things in place; removed {removed or 'nothing'}.")
    if missing:
        print(f"WARNING - the owner expects these but they are missing: {missing}")


if __name__ == "__main__":
    main()
