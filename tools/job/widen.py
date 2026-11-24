"""Widening a place: a new kind beside the kinds a set already has, and the group "in between".

The owner's rulings of the evening of 24 Nov 2026 (see DESIGN.md, sections 7 and 8).

Until then the job could only make a whole new set under a group. It could not add to a
place that already had a set, and the first set was made by hand. Two things are added
here, and both go through the same stages as every other thing afterwards: names, pages,
facts with their sentences, the one-solution rule, pictures, checks.

A NEW KIND. "Mushrooms are neither plant nor animal, and nobody disputes it; they need a
kind of their own." The model proposes kinds the question lacks. A kind is kept only if
two separate sortings, worded differently, both put at least four of its things in it,
and neither takes into it a thing the place already holds: a kind that swallows what is
there is not a new kind.

IN BETWEEN. "Virus, Pluto, Schrödinger's cat, Centaur, Photon... things resist binary
classification." A thing with no single answer to a question is not left out and not
forced into one answer. Two keys, and both must turn:
  1. THE SOURCES SAY SO. From the thing's own whole pages the model copies, for each
     answer the pages give it, one sentence that says so, and one sentence saying that the
     answer is disputed or on the border, if there is one. A script checks every sentence
     against the saved text, word for word. Two answers with their sentences: the thing
     lists both. A sentence of dispute: it is marked "depends", and the sentence is its
     note. "The world does not agree" is a fact and goes in; "we could not find out" is
     not, and such a thing stays held as before.
  2. TWO CHECKS DO NOT GIVE IT ONE PLACE. The same two sortings that settle every other
     thing are asked. If both put it in one and the same kind, it has a place after all,
     whatever a page says, and it is not in between.
It is not a dump: a thing that fits no kind because a kind is missing calls for a new
kind, and the model is told so.

Nothing here writes anything. The job (tools/prepare_next.py --widen) does that.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
for folder in ("tools/research", "tools/content", "tools/catalogue"):
    if str(ROOT / folder) not in sys.path:
        sys.path.insert(0, str(ROOT / folder))
import reslib                                   # noqa: E402
import fields as field_rules                    # noqa: E402  the two sortings
from boards import PER_GROUP                    # noqa: E402

NEW_KINDS = 2             # kinds asked for in one go
NEW_NAMES = 7             # things asked for with each
BETWEEN_NAMES = 9         # things with no single answer asked for in one go

KINDER = "You know how a subject is divided into kinds. You answer only with JSON."

KINDS_TASK = """A picture-sorting game holds this part: {chain}.
It is sorted by the question: "{wording}"
The kinds it has now, each with some of its things:
{kinds}

Which other true answers does this question have for things of this part: kinds that are none of the kinds above? Give at most {count}, the most important first. Give none if the kinds above already cover the subject. A kind is good only if ALL of these hold:
- It is a real kind that a teacher of the subject would name, standing beside the kinds above: not inside one of them, and not a wider thing that takes them in.
- Nothing listed above belongs in it.
- It is not "others", "mixed" or any catch-all, and it is not a kind for things that are hard to place.
- It has at least six well-known members, each a different thing with an encyclopedia article of its own, and each clearly different from the others in a small picture.
- It is not a colour and not a size.

For each kind give {new} of its members under "new", the best known first, named as the things above are named.

Return JSON: {{"kinds": [{{"key": "short_snake_case", "label": "The group's name, one to four words", "why": "a few words", "new": ["..."]}}]}}"""

BETWEEN_TASK = """A sorting game holds this part: {chain}.
It is sorted by the question: "{wording}"
Its kinds: {kinds}

Every way of sorting has edges. Name up to {count} things of this part that have no single answer to this question TODAY, the best known first: the cases a teacher of the subject uses to show where this sorting frays. A thing counts only if one of these is true of it, and its encyclopedia article says so in plain words:
- it truly is of two of the kinds at once (not merely looks like one and is another);
- the people who study it do not agree today which kind it is;
- it is on the border between kinds, or is said to be none of them.
A dispute of the past that is settled today does not count. A thing that only surprises (it looks like one kind and is plainly another) does not count. A thing that belongs to a kind the question lacks does not count: that needs a new kind, not this.
Each must be a real, single thing with an article of its own, that one clear picture can show, and fit to show a young child.
Not any of these, which the game already has: {taken}.

For each, under "between" give the keys of the kinds it lies between (two or more), or an empty list if people simply do not agree.

Return JSON: {{"things": [{{"name": "...", "between": ["kind key", "kind key"], "why": "a few words"}}]}}"""

READER = "You read source text about one thing and report only what it says. You answer only with JSON."

READ_TASK = """The sources above are about "{name}".

A sorting game asks of it: "{wording}"
The possible answers: {kinds}

From the sources only, never from what you know:
1. For each answer that the sources say {name} IS, today, copy ONE whole sentence from the sources that says so. Leave out an answer the sources only compare it with (it looks like one, it was once thought to be one), and an answer that no sentence states.
2. If the sources say that TODAY the answer is disputed or uncertain, that {name} is on the border between answers, or that it is none of them, copy ONE whole sentence that says so. A dispute of the past that the sources say is now settled does not count: leave this empty.

Copy the sentences exactly, word for word.

Return JSON: {{"answers": {{"<answer key>": "the sentence"}}, "disputed": "the sentence, or an empty string"}}"""


def options(config: dict, most: int) -> dict:
    return {"provider": "deepseek", "model": config["model"], "thinking": config["thinking"], "most_written": most}


def kinds_line(definition: dict, such_as: dict = None) -> str:
    return "; ".join(f'{key} = "{label}"' + (f" (such as {', '.join(such_as[key][:4])})" if (such_as or {}).get(key) else "")
                     for key, label in definition["values"].items())


# ------------------------------------------------------------------ a new kind

def propose_kinds(client, config, spend, chain: str, definition: dict, such_as: dict) -> list:
    """Kinds the question lacks, each with names for it. Shaped and cleaned; not yet tested."""
    kinds = "\n".join(f'- {label}: {", ".join(such_as.get(key, [])[:8]) or "nothing yet"}'
                      for key, label in definition["values"].items())
    answer = reslib.ask(client, config, spend, KINDER, KINDS_TASK.format(
        chain=chain, wording=definition["wording"], kinds=kinds, count=NEW_KINDS, new=NEW_NAMES), options(config, 700))
    taken_labels = {field_rules.norm(label) for label in definition["values"].values()}
    out = []
    for item in answer.get("kinds") or []:
        if not isinstance(item, dict):
            continue
        key, label = field_rules.key_of(item.get("key", "")), str(item.get("label", "")).strip()
        names = list(dict.fromkeys(str(n).strip() for n in item.get("new") or [] if str(n).strip()))
        if not key or not label or key in definition["values"] or key in ("in_between", "depends", "other", "others"):
            continue
        if field_rules.norm(label) in taken_labels or key in {o["key"] for o in out}:
            continue
        out.append({"key": key, "label": label, "why": str(item.get("why", "")).strip(), "new": names})
    return out[:NEW_KINDS]


def test_kind(client, config, spend, chain: str, definition: dict, such_as: dict, kind: dict, there: list) -> dict:
    """Is it a kind of its own? The things already at the place (`there`) and the kind's
    own names are sorted twice over the old kinds and the new one together. It passes when
    both sortings put at least four of its names in it, and neither puts there a thing the
    place already holds. Returns {"why": [...], "names": the names both put in it,
    "takes": the things it would take}."""
    values = [{"key": key, "label": label, "such_as": such_as.get(key, [])[:4]} for key, label in definition["values"].items()]
    values.append({"key": kind["key"], "label": kind["label"], "such_as": []})
    names = list(dict.fromkeys(there + kind["new"]))
    first, second = field_rules.sort_twice(client, config, spend, chain,
                                           {"wording": definition["wording"], "values": values}, names)
    placed, _ = field_rules.one_value_each(names, first, second, [v["key"] for v in values],
                                           {v["key"]: v["label"] for v in values})
    mine = [n for n in kind["new"] if placed.get(n) == kind["key"]]
    takes = [n for n in there if n not in kind["new"]
             and kind["key"] in field_rules.values_named(n, first, second, [v["key"] for v in values],
                                                         {v["key"]: v["label"] for v in values})]
    why = []
    if takes:
        why.append(f"it is not a kind of its own: {', '.join(takes[:4])}, already here, would belong to it")
    if len(mine) < PER_GROUP:
        why.append(f"two checks put only {len(mine)} of its {len(kind['new'])} things in it, and a group needs {PER_GROUP}")
    if not why:
        # It must stand BESIDE the kinds there, not inside one of them: sorted over the old
        # kinds alone, its things must have no place. (Tried on 24 Nov 2026: "Clothing"
        # passed at the first place, although clothes are plainly things people make.)
        old = values[:-1]
        first, second = field_rules.sort_twice(client, config, spend, chain,
                                               {"wording": definition["wording"], "values": old}, mine)
        at_home, _ = field_rules.one_value_each(mine, first, second, [v["key"] for v in old],
                                                {v["key"]: v["label"] for v in old})
        if len(at_home) * 2 >= len(mine):
            inside = max(set(at_home.values()), key=list(at_home.values()).count)
            why.append(f"it lies inside a kind that is there: two checks put {len(at_home)} of its {len(mine)} things "
                       f"in '{definition['values'][inside]}'")
    return {"why": why, "names": mine, "takes": takes}


# ------------------------------------------------------------------ in between

def propose_between(client, config, spend, chain: str, definition: dict, taken: list) -> list:
    """Things said to have no single answer to the question. Names only; not yet read."""
    answer = reslib.ask(client, config, spend, KINDER, BETWEEN_TASK.format(
        chain=chain, wording=definition["wording"], kinds=kinds_line(definition), count=BETWEEN_NAMES,
        taken=", ".join(taken[:60]) or "none"), options(config, 700))
    have, out = {field_rules.norm(n) for n in taken}, []
    for item in answer.get("things") or []:
        name = str(item.get("name", "")).strip() if isinstance(item, dict) else ""
        if not name or field_rules.norm(name) in have or field_rules.norm(name) in {field_rules.norm(o["name"]) for o in out}:
            continue
        sides = [str(s) for s in item.get("between") or [] if str(s) in definition["values"]]
        out.append({"name": name[0].upper() + name[1:], "between": sides, "why": str(item.get("why", "")).strip()})
    return out[:BETWEEN_NAMES]


def read_between(client, config, spend, name: str, definition: dict, sources: list, block: str) -> dict:
    """The first key: what the thing's own pages say. `sources` are its saved pages and
    `block` the text of them sent to the model. Every sentence is checked by a script
    against the saved text. Returns {"value": a list of two or more answers, or "depends",
    or None; "sentences": {answer or "disputed": sentence}; "why": why not, if None}."""
    answer = reslib.ask(client, config, spend, READER, block + "\n\n" + READ_TASK.format(
        name=name, wording=definition["wording"], kinds=kinds_line(definition)), options(config, 500))
    text = "\n".join(s["text"] for s in sources)
    said = answer.get("answers") if isinstance(answer.get("answers"), dict) else {}
    kept = {key: str(said[key]).strip() for key in definition["values"]
            if key in said and reslib.quote_found(str(said[key]), text)}
    disputed = str(answer.get("disputed") or "").strip()
    disputed = disputed if reslib.quote_found(disputed, text) else ""
    if len(kept) >= 2:
        return {"value": list(kept), "sentences": dict(kept, **({"disputed": disputed} if disputed else {})), "why": ""}
    if disputed:
        return {"value": "depends", "sentences": dict(kept, disputed=disputed), "why": ""}
    if len(kept) == 1:
        label = definition["values"][next(iter(kept))]
        return {"value": None, "sentences": kept, "why": f"its pages give it one answer, '{label}', and no sentence says that is disputed"}
    return {"value": None, "sentences": {}, "why": "no sentence in its pages gives it two answers or says the answer is disputed"}


def one_place(client, config, spend, chain: str, definition: dict, such_as: dict, name: str):
    """The second key: the place two separate sortings both give the thing, or None when
    they give it none, several, or disagree."""
    values = [{"key": key, "label": label, "such_as": such_as.get(key, [])[:4]} for key, label in definition["values"].items()]
    first, second = field_rules.sort_twice(client, config, spend, chain,
                                           {"wording": definition["wording"], "values": values}, [name])
    placed, _ = field_rules.one_value_each([name], first, second, [v["key"] for v in values],
                                           {v["key"]: v["label"] for v in values})
    return placed.get(name)


def note_for(definition: dict, read: dict) -> str:
    """What is written on the thing for a grown-up: the sentences that make it in between."""
    parts = [f"{definition['values'][key]}: \"{sentence}\"" for key, sentence in read["sentences"].items() if key != "disputed"]
    if read["sentences"].get("disputed"):
        parts.append(f"Not settled: \"{read['sentences']['disputed']}\"")
    return ("It has no single answer here, by its own sources. " + " ".join(parts)
            + " Two checks, sorting it as a parent would, did not agree on one group either.")
