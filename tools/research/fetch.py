"""Step 1 - save the source pages for a thing. No model is used here.

For each thing this saves, under tools/research/cache/<thing>/:
  - the English Wikipedia article as plain text, with its revision number;
  - the Simple English article, where one exists;
  - the Natural History Museum's Dino Directory page, where there is one;
  - any page a person has listed for it under `hints` in config.json.
Only the hosts listed in config.json are ever read. A page already saved is not
fetched again unless --again is given, so later runs read exactly the same text.

    python tools/research/fetch.py --prehistoric
    python tools/research/fetch.py "Tyrannosaurus rex" Titanoboa [--again]
"""
import hashlib
import re
import sys
import time
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

from reslib import CACHE, CONFIG, THINGS, read_json, slug, today, write_json

AGENT = {"User-Agent": "IshansGamesResearch/0.1 (github.com/jijilr/kids-connection-game; "
                       "a children's learning game; a few pages a day)"}
BLOCKS = ["p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "td", "th", "dt", "dd",
          "br", "section", "figcaption", "blockquote"]
ENDS = re.compile(r"\n==\s*(References|See also|External links|Bibliography|Notes|Further reading|"
                  r"Sources|Citations|Footnotes)\s*==\n")


def true_dinosaurs() -> set:
    """Names the game's data marks as dinosaurs to a scientist. Only these can have a
    page in the museum's Dino Directory; sea reptiles, flyers and snakes cannot."""
    return {t["name"] for t in read_json(THINGS)["things"].values()
            if t["fields"].get("dinosaur_academic") is True}


def prehistoric() -> dict:
    """name -> the group it must be told apart within. Read from the game's own data,
    plus the animals drawn but not yet in the game."""
    groups = {}
    for thing in read_json(THINGS)["things"].values():
        fields = thing["fields"]
        if fields.get("kind_of_dinosaur"):
            groups[thing["name"]] = fields["kind_of_dinosaur"]
        elif fields.get("extinct") is True and fields.get("kind_of_animal") == "reptile":
            groups[thing["name"]] = "giant_snake"
    for name, fields in read_json(CONFIG)["not_in_the_game_yet"].items():
        groups[name] = fields["kind_of_dinosaur"]
    return groups


def wikipedia(host: str, name: str) -> dict:
    for attempt in range(4):
        reply = requests.get(f"https://{host}/w/api.php", headers=AGENT, timeout=40, params={
            "action": "query", "format": "json", "formatversion": 2, "redirects": 1, "titles": name,
            "prop": "extracts|revisions|info", "explaintext": 1, "exsectionformat": "wiki",
            "rvprop": "ids|timestamp", "inprop": "url"})
        if reply.status_code != 429 and reply.status_code < 500:
            break
        # asked to slow down, or the site is busy: wait as long as it says, then try again
        wait = reply.headers.get("Retry-After", "")
        time.sleep(min(float(wait) if wait.isdigit() else 10 * (attempt + 1), 90))
    reply.raise_for_status()
    page = reply.json()["query"]["pages"][0]
    if page.get("missing") or not page.get("extract"):
        return {"problem": "no article by this name"}
    if page["title"].split()[0].lower() != name.split()[0].lower():
        # a redirect to a broader article (Mosasaurus -> Mosasaur) is about something else
        return {"url": page["fullurl"], "title": page["title"],
                "problem": f"the name leads to an article about '{page['title']}', not this animal"}
    text = page["extract"]
    cut = ENDS.search(text)   # the reading list at the end is not about the animal
    return {"url": page["fullurl"], "title": page["title"], "revision": page["revisions"][0]["revid"],
            "revision_time": page["revisions"][0]["timestamp"], "text": text[:cut.start()] if cut else text}


def web_page(url: str) -> dict:
    reply = requests.get(url, headers=AGENT, timeout=40)
    if reply.status_code != 200:
        return {"url": url, "problem": f"the site answered {reply.status_code}"}
    soup = BeautifulSoup(reply.text, "lxml")
    for tag in soup(["script", "style", "nav", "header", "footer", "form", "noscript", "aside"]):
        tag.decompose()
    body = soup.find("main") or soup.find("article") or soup.body
    if body is None:
        return {"url": url, "problem": "the page held almost no text"}
    # a line break around each block and none inside a sentence, so a sentence reads as written
    for tag in body.find_all(BLOCKS):
        tag.insert_before("\n")
        tag.insert_after("\n")
    text = re.sub(r"[ \t]+", " ", body.get_text())
    text = re.sub(r" ?\n[ \n]*", "\n", text).strip()
    if len(text) < 300:
        return {"url": url, "problem": "the page held almost no text"}
    return {"url": url, "title": (soup.title.string or "").strip() if soup.title else "", "text": text}


def fetch(name: str, config: dict, again: bool) -> list:
    folder = CACHE / slug(name)
    known = {s["id"]: s for s in read_json(folder / "sources.json", {"sources": []})["sources"]}
    allowed = {s["host"] for s in config["sources"].values()}
    wanted = [("wikipedia_en", lambda: wikipedia("en.wikipedia.org", name)),
              ("wikipedia_simple", lambda: wikipedia("simple.wikipedia.org", name))]
    if name in true_dinosaurs():
        wanted.append(("nhm_dino_directory", lambda: web_page(
            config["sources"]["nhm_dino_directory"]["pattern"].format(genus=name.split()[0].lower()))))
    else:
        known.pop("nhm_dino_directory", None)   # not a dinosaur: the Dino Directory has no page for it
    for source, url in config["hints"].get(name, {}).items():
        if urlparse(url).hostname not in allowed:
            raise SystemExit(f"{url} is not on a host listed in config.json. Nothing was fetched from it.")
        wanted.append((source, lambda url=url: web_page(url)))

    for source, get in wanted:
        if source in known and not again and not known[source].get("problem"):
            continue
        try:
            found = get()
        except requests.RequestException as error:
            code = getattr(getattr(error, "response", None), "status_code", "")
            found = {"problem": f"could not be reached: {type(error).__name__} {code}".strip()}
        if "text" not in found and known.get(source, {}).get("file"):
            # a retry that fails never throws away a page already saved
            known[source]["last_retry"] = {"on": today(), "problem": found["problem"]}
            continue
        record = {"id": source, "fetched_on": today(), **{k: v for k, v in found.items() if k != "text"}}
        if "text" in found:
            folder.mkdir(parents=True, exist_ok=True)
            (folder / f"{source}.txt").write_text(found["text"], encoding="utf-8")
            record.update(file=f"{source}.txt", chars=len(found["text"]),
                          sha256=hashlib.sha256(found["text"].encode("utf-8")).hexdigest())
        known[source] = record
        time.sleep(1.5)   # a few pages, slowly
    write_json(folder / "sources.json", {"thing": name, "sources": list(known.values())})
    return list(known.values())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    names = list(prehistoric()) if "--prehistoric" in sys.argv else args
    if not names:
        raise SystemExit(__doc__)
    config = read_json(CONFIG)
    for name in names:
        sources = fetch(name, config, "--again" in sys.argv)
        got = ", ".join(f"{s['id']} ({s['chars']:,} letters)" for s in sources if s.get("file"))
        missing = ", ".join(f"{s['id']}: {s['problem']}" for s in sources if s.get("problem"))
        print(f"  {name}: {got or 'NOTHING'}" + (f"   [not found - {missing}]" if missing else ""))


if __name__ == "__main__":
    main()
