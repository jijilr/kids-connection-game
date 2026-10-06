"""Shared helpers for the content scripts (dev-time only; nothing here runs in the game)."""
import json
import os
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
DICTIONARY = ROOT / "Assets/data/dictionary.json"
THINGS = ROOT / "Assets/data/things.json"   # the game's copy: read it freely, change it only through catalogue()
DRAFT = ROOT / "tools/content/_draft.json"
CHECKED = ROOT / "tools/content/_checked.json"
REVIEW_QUEUE = ROOT / "tools/content/review_queue.json"


def read_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def applies(expected_on, fields: dict) -> bool:
    """Does a dictionary field's `expected_on` rule match a thing's fields?"""
    if expected_on == "everything":
        return True
    for key, want in expected_on.items():
        wanted = want if isinstance(want, list) else [want]
        if fields.get(key) not in wanted:
            return False
    return True


def allowed_values(field_def: dict) -> list:
    """Dictionary keys are strings; 'true'/'false' stand for real booleans in a thing."""
    out = []
    for key in field_def["values"]:
        out.append({"true": True, "false": False}.get(key, key))
    return out


def label(field_def: dict, value) -> str:
    return field_def["values"][str(value).lower() if isinstance(value, bool) else value]


def deepseek():
    """DeepSeek client. The key is read from the environment and never written anywhere."""
    from openai import OpenAI

    key = os.environ.get("DEEPSEEK_API_KEY")
    if not key:
        raise SystemExit("DEEPSEEK_API_KEY is not set in the environment.")
    return OpenAI(api_key=key, base_url="https://api.deepseek.com")


def ask_json(client, system: str, user: str, temperature: float) -> dict:
    reply = client.chat.completions.create(
        model="deepseek-chat",
        temperature=temperature,
        response_format={"type": "json_object"},
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
    )
    return json.loads(reply.choices[0].message.content)


def catalogue():
    """The master record of every thing (tools/catalogue/catalogue.py). Since 6 Oct 2026
    things.json is the game's copy of it and the review queue is its list of what is held,
    so the scripts here read and write things through it. Imported late, because the
    catalogue itself uses this folder's rules."""
    import sys
    sys.path.insert(0, str(ROOT / "tools/catalogue"))
    import catalogue as module
    return module


def set_queue(sender: str, entries: list):
    """Replace one script's entries in the owner's review queue, leaving the others alone."""
    catalogue().set_queue(sender, entries)
