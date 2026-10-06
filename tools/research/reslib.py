"""Shared helpers for the research scripts (dev-time only; nothing here runs in the game).

    fetch.py      save the source pages for a thing, with their addresses and revisions
    extract.py    DeepSeek reads only those pages and lists what they say, each item with
                  the exact sentence it came from; a script checks every sentence
    tell_apart.py a judge picks, from the checked features only, what tells each animal
                  from its look-alikes
    benchmark.py  compare the result with the research Claude did by hand on 6 Oct 2026

The rule the owner set on 6 Oct 2026: research must not depend on a Claude session, and
the model must work from fetched text, not from memory. So every item carries a quote,
and an item whose quote is not in the saved text is dropped.
"""
import datetime
import json
import os
import pathlib
import re
import threading
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/research"
CONFIG = HERE / "config.json"
CACHE = HERE / "cache"   # fetched pages, kept so the same text is read on every run
OUT = HERE / "out"       # what the scripts concluded
THINGS = ROOT / "Assets/data/things.json"


def read_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def today() -> str:
    return datetime.date.today().isoformat()


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def norm(text: str) -> str:
    """Text as compared by the quote check: case, spacing, and the kinds of quote mark
    and dash a model tends to swap are ignored. Nothing else is forgiven."""
    text = unicodedata.normalize("NFKC", text).lower()
    text = text.translate(str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"',
                                         "–": "-", "—": "-", "−": "-", " ": " "}))
    return re.sub(r"\s+", " ", text).strip()


def quote_found(quote: str, text: str) -> bool:
    """Is the quoted sentence in the saved text, word for word? Quotes shorter than
    twenty letters prove nothing and do not count."""
    quote = norm(quote).strip(" .\"'")
    return len(quote) >= 20 and quote in norm(text)


def saved_sources(thing: str) -> list:
    """The pages saved for one thing: [{id, url, revision, fetched_on, text}, ...]."""
    folder = CACHE / slug(thing)
    meta = read_json(folder / "sources.json", {"sources": []})
    return [dict(s, text=(folder / s["file"]).read_text(encoding="utf-8"))
            for s in meta["sources"] if s.get("file")]


def sources_block(sources: list, longest: int) -> str:
    """The saved pages as one block of text for the model. It goes first in every
    prompt about a thing, so repeated questions about the same pages cost less."""
    parts = []
    for s in sources:
        parts.append(f'<source id="{s["id"]}" title="{s.get("title", "")}">\n{s["text"][:longest]}\n</source>')
    return "\n\n".join(parts)


class Spend:
    """Counts tokens and money across calls, and stops the run at the cap."""

    def __init__(self, config: dict, cap_usd: float, prices: dict = None):
        self.prices, self.cap = prices or config["usd_per_million_tokens_at_peak"], cap_usd
        self.inr = config["inr_per_usd"]
        self.hit = self.miss = self.out = self.calls = 0
        self.lock = threading.Lock()

    @property
    def usd(self) -> float:
        p = self.prices
        return (self.hit * p["input_cache_hit"] + self.miss * p["input_cache_miss"]
                + self.out * p["output"]) / 1_000_000

    def add(self, usage):
        with self.lock:
            hit = getattr(usage, "prompt_cache_hit_tokens", 0) or 0
            self.hit += hit
            self.miss += usage.prompt_tokens - hit
            self.out += usage.completion_tokens
            self.calls += 1

    def check(self):
        if self.usd >= self.cap:
            raise SystemExit(f"Stopped at the cap: ${self.usd:.3f} of ${self.cap:.2f} spent. "
                             "What was finished is saved; run again to continue.")

    def summary(self) -> dict:
        return {"calls": self.calls, "input_tokens_cache_hit": self.hit,
                "input_tokens_cache_miss": self.miss, "output_tokens": self.out,
                "usd_at_peak_prices": round(self.usd, 4), "inr_at_peak_prices": round(self.usd * self.inr, 1)}

    def line(self) -> str:
        return (f"{self.calls} calls, {self.hit + self.miss:,} tokens read, {self.out:,} written: "
                f"at most ${self.usd:.3f}, about Rs {self.usd * self.inr:.0f} (peak prices).")


def deepseek():
    """DeepSeek client. The key is read from the environment and never written anywhere."""
    from openai import OpenAI

    key = os.environ.get("DEEPSEEK_API_KEY")
    if not key:
        raise SystemExit("DEEPSEEK_API_KEY is not set in the environment.")
    return OpenAI(api_key=key, base_url="https://api.deepseek.com")


def openai_client():
    """OpenAI client, through the key the picture scripts already use. Read from the
    environment and never written anywhere."""
    from openai import OpenAI

    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is not set in the environment.")
    return OpenAI()


def ask(client, config: dict, spend: Spend, system: str, user: str, judge: dict = None) -> dict:
    """One question to a model, answered as JSON. Without `judge` it goes to the
    everyday DeepSeek model with long reasoning off: copying sentences out of a page
    needs none, and with it off the answer is steadier (temperature 0 applies) and
    costs a fraction as much. A judge from config.json may reason at length."""
    judge = judge or {"provider": "deepseek", "model": config["model"], "thinking": config["thinking"]}
    spend.check()
    options = {}
    if judge["provider"] == "deepseek":
        options["extra_body"] = {"thinking": {"type": judge["thinking"]}}
        if judge["thinking"] == "disabled":
            options["temperature"] = 0
        elif judge.get("reasoning_effort"):
            options["reasoning_effort"] = judge["reasoning_effort"]
    reply = client.chat.completions.create(
        model=judge["model"], response_format={"type": "json_object"},
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}], **options)
    spend.add(reply.usage)
    try:
        return json.loads(reply.choices[0].message.content)
    except (json.JSONDecodeError, TypeError):
        return {}
