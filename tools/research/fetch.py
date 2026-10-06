"""Step 1 - save the source pages for a thing. No model is used here.

For each thing this saves, under tools/research/cache/<thing>/:
  - the English Wikipedia article as plain text, with its revision number;
  - the Simple English article, where one exists;
  - the Natural History Museum's Dino Directory page, where there is one;
  - any page a person has listed for it under `hints` in config.json.
For an ordinary thing it saves the two Wikipedia articles and, for a plant, the page
of the Royal Botanic Gardens, Kew, where there is one.

Only the hosts listed in config.json are ever read. A page already saved is not
fetched again unless --again is given, so later runs read exactly the same text.

    python tools/research/fetch.py --prehistoric
    python tools/research/fetch.py --ordinary          every thing in the game that is not prehistoric
    python tools/research/fetch.py "Tyrannosaurus rex" Titanoboa [--again]
"""
import hashlib
import re
import sys
import time
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

from reslib import CACHE, CATALOGUE, CONFIG, THINGS, read_json, slug, today, write_json

AGENT = {"User-Agent": "IshansGamesResearch/0.1 (github.com/jijilr/kids-connection-game; "
                       "a children's learning game; a few pages a day)"}
REFUSED = {}   # a site that has turned this run away is not asked again in the same run
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
    """name -> the group it must be told apart within. Read from the catalogue: the
    animals in the game, and those ready but not in it yet."""
    groups = {}
    for thing in read_json(CATALOGUE)["things"].values():
        if thing["status"] not in ("in the game", "not in the game yet"):
            continue
        fields = thing["fields"]
        if fields.get("kind_of_dinosaur"):
            groups[thing["name"]] = fields["kind_of_dinosaur"]
        elif fields.get("extinct") is True and fields.get("kind_of_animal") == "reptile":
            groups[thing["name"]] = "giant_snake"
    return groups


def ordinary() -> dict:
    """name -> its fields. Every thing in the game that is not a prehistoric animal."""
    old_ones = set(prehistoric())
    return {t["name"]: t["fields"] for t in read_json(THINGS)["things"].values() if t["name"] not in old_ones}


def narrowing_words(fields: dict, config: dict) -> list:
    """Words that say which meaning of a name is wanted, taken from the thing's kind,
    the most exact kind first: a thing in the house gives 'furniture', 'dishware';
    rocks and soil give 'geology'."""
    table = config["words_that_narrow_a_name"]
    kinds = [(k, v) for k, v in fields.items() if k != "kind_of_thing" and isinstance(v, str)][::-1]   # the deepest first
    kinds.append(("kind_of_thing", fields.get("kind_of_thing")))
    # the same word can be a value of two fields: a key written field=value speaks for that field only
    return list(dict.fromkeys(word for field, kind in kinds for word in table.get(f"{field}={kind}", table.get(kind, []))))


def other_names(name: str) -> list:
    """The name, then the name without a last word that only says what kind of thing it
    is: 'Tomato plant' is filed under 'Tomato', 'Rohu fish' under 'Rohu'."""
    words = name.split()
    return [name] + ([" ".join(words[:-1])] if len(words) > 1 and words[-1].lower() in ("plant", "tree", "fish") else [])


def wikipedia(host: str, name: str, strict: bool = True) -> dict:
    """`strict` is for prehistoric animals, where a redirect to a broader article is about
    something else. An ordinary thing may be filed under another name (Hen under Chicken),
    so its redirect is followed and the page's own title is recorded."""
    if strict is False:   # try each name it may be filed under; None below means "this one name, any title"
        for candidate in other_names(name):
            found = wikipedia(host, candidate, strict=None)
            if "text" in found:
                return dict(found, asked_for=candidate)
        return found
    for attempt in range(4):
        reply = requests.get(f"https://{host}/w/api.php", headers=AGENT, timeout=40, params={
            "action": "query", "format": "json", "formatversion": 2, "redirects": 1, "titles": name,
            "prop": "extracts|revisions|info|pageprops", "explaintext": 1, "exsectionformat": "wiki",
            "rvprop": "ids|timestamp", "inprop": "url", "ppprop": "disambiguation"})
        if reply.status_code != 429 and reply.status_code < 500:
            break
        # asked to slow down, or the site is busy: wait as long as it says, then try again
        wait = reply.headers.get("Retry-After", "")
        time.sleep(min(float(wait) if wait.isdigit() else 10 * (attempt + 1), 90))
    reply.raise_for_status()
    page = reply.json()["query"]["pages"][0]
    if page.get("missing") or not page.get("extract"):
        return {"problem": "no article by this name"}
    if "disambiguation" in page.get("pageprops", {}):
        return {"url": page["fullurl"], "title": page["title"], "problem": SEVERAL}
    if strict and page["title"].split()[0].lower() != name.split()[0].lower():
        # a redirect to a broader article (Mosasaurus -> Mosasaur) is about something else
        return {"url": page["fullurl"], "title": page["title"],
                "problem": f"the name leads to an article about '{page['title']}', not this animal"}
    text = page["extract"]
    cut = ENDS.search(text)   # the reading list at the end is not about the animal
    return {"url": page["fullurl"], "title": page["title"], "revision": page["revisions"][0]["revid"],
            "revision_time": page["revisions"][0]["timestamp"], "text": text[:cut.start()] if cut else text}


SEVERAL = "the name has several meanings on Wikipedia, and a script cannot tell which is meant"


def ask_openings(host: str, wanted: dict) -> dict:
    """wanted: name -> the titles to try for it, in order. One request for them all.
    Returns name -> what wikipedia() returns, for the first title that has an article."""
    asked = list(dict.fromkeys(title for titles in wanted.values() for title in titles))
    for attempt in range(4):
        reply = requests.get(f"https://{host}/w/api.php", headers=AGENT, timeout=60, params={
            "action": "query", "format": "json", "formatversion": 2, "redirects": 1, "titles": "|".join(asked),
            "prop": "extracts|revisions|info|pageprops", "exintro": 1, "explaintext": 1, "exlimit": 20,
            "rvprop": "ids|timestamp", "inprop": "url", "ppprop": "disambiguation"})
        if reply.status_code != 429 and reply.status_code < 500:
            break
        wait = reply.headers.get("Retry-After", "")
        time.sleep(min(float(wait) if wait.isdigit() else 10 * (attempt + 1), 90))
    reply.raise_for_status()
    query = reply.json()["query"]
    leads_to = {}   # the title asked for -> the title of the page it is filed under
    for step in ("normalized", "redirects"):
        for move in query.get(step, []):
            leads_to[move["from"]] = move["to"]
    pages = {page["title"]: page for page in query.get("pages", [])}
    found = {}
    for name, titles in wanted.items():
        result = {"problem": "no article by this name"}
        for candidate in titles:
            title = leads_to.get(candidate, candidate)
            title = leads_to.get(title, title)
            page = pages.get(title)
            if page is None or page.get("missing"):
                continue
            if "disambiguation" in page.get("pageprops", {}):
                result = {"url": page["fullurl"], "title": page["title"], "problem": SEVERAL}
                continue
            if page.get("extract"):
                result = {"url": page["fullurl"], "title": page["title"], "asked_for": candidate,
                          "revision": page["revisions"][0]["revid"],
                          "revision_time": page["revisions"][0]["timestamp"],
                          "part": "the opening only", "text": page["extract"]}
                break
        found[name] = result
    time.sleep(1.5)
    return found


def meanings(host: str, title: str) -> tuple:
    """The articles a page of several meanings points to, and what the page says of them."""
    reply = requests.get(f"https://{host}/w/api.php", headers=AGENT, timeout=60, params={
        "action": "query", "format": "json", "formatversion": 2, "titles": title, "redirects": 1,
        "prop": "links|extracts", "pllimit": 200, "plnamespace": 0, "explaintext": 1})
    reply.raise_for_status()
    pages = reply.json()["query"].get("pages", [])
    time.sleep(1.5)
    if not pages:
        return [], ""
    return [link["title"] for link in pages[0].get("links", [])], pages[0].get("extract", "")[:3000]


def openings(host: str, names: list, words: dict = None, choose=None, narrowed: bool = False) -> dict:
    """The opening of the article for each name, ten things to a request. A thing's
    fields are settled by how its article begins, so the whole article is not needed,
    and a hundred things cost a dozen requests, not two hundred.

    A name with several meanings (Table, Rock, Plate) is then asked again with a word
    from the thing's kind in brackets, as Wikipedia files such articles: Table
    (furniture), Rock (geology). `words` gives those words for each name. `narrowed`
    asks that way even when the plain name has an article: the plain article for
    Sponge is about the sea animal, and the thing wanted is filed under Sponge (tool).
    Returns name -> what wikipedia() returns."""
    found = {}
    for start in range(0, len(names), 10):
        batch = names[start:start + 10]
        found.update(ask_openings(host, {name: other_names(name) for name in batch}))
    unclear = [n for n in names if (narrowed or "text" not in found[n]) and (words or {}).get(n)]
    for start in range(0, len(unclear), 2):   # few things at a time: each has several titles to try
        batch = unclear[start:start + 2]
        again = ask_openings(host, {name: [f"{base} ({word})" for word in words[name] for base in other_names(name)][:10]
                                    for name in batch})
        for name, result in again.items():
            if "text" in result:
                found[name] = dict(result, narrowed_by="the thing's kind")
    # still several meanings: `choose` picks one from the page's OWN list of meanings, and
    # only a title on that list is ever fetched
    for name in names:
        if choose and found[name].get("problem") == SEVERAL:
            links, text = meanings(host, found[name]["title"])
            picked = choose(name, links, text) if links else None
            if picked in links:
                result = ask_openings(host, {name: [picked]})[name]
                if "text" in result:
                    found[name] = dict(result, narrowed_by="chosen from the page's own list of meanings")
    return found


def fetch_openings(names: list, again: bool, words: dict = None, choose=None, narrowed: bool = False) -> dict:
    """Save the two Wikipedia openings for each ordinary thing. A page already saved,
    whole or opening, is kept unless --again is given. `words` narrows a name that has
    several meanings (see openings)."""
    results = {name: {s["id"]: s for s in read_json(CACHE / slug(name) / "sources.json", {"sources": []})["sources"]}
               for name in names}
    for source, host in (("wikipedia_en", "en.wikipedia.org"), ("wikipedia_simple", "simple.wikipedia.org")):
        need = [n for n in names if again or not results[n].get(source, {}).get("file")]
        for name, found in openings(host, need, words, choose, narrowed).items():
            record = {"id": source, "fetched_on": today(), **{k: v for k, v in found.items() if k != "text"}}
            if "text" in found:
                folder = CACHE / slug(name)
                folder.mkdir(parents=True, exist_ok=True)
                (folder / f"{source}.txt").write_text(found["text"], encoding="utf-8")
                record.update(file=f"{source}.txt", chars=len(found["text"]),
                              sha256=hashlib.sha256(found["text"].encode("utf-8")).hexdigest())
            results[name][source] = record
    for name in names:
        write_json(CACHE / slug(name) / "sources.json", {"thing": name, "sources": list(results[name].values())})
    return results


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


def kew(name: str, config: dict) -> dict:
    """Kew's page for a plant, by its everyday name. The address is guessed from the
    name; where the guess is wrong there is simply no page."""
    if REFUSED.get("kew"):
        return {"problem": REFUSED["kew"]}
    for candidate in other_names(name):
        found = web_page(config["sources"]["kew"]["pattern"].format(name=candidate.lower().replace(" ", "-")))
        if "text" in found:
            return found
        if "403" in found.get("problem", ""):
            # the site turns scripts away; asking again for every plant would only be slow and rude
            REFUSED["kew"] = "Kew's site refuses requests from scripts (it answered 403)"
            return {"url": found["url"], "problem": REFUSED["kew"]}
    return found


def fetch(name: str, config: dict, again: bool, strict: bool = True, plant: bool = False) -> list:
    folder = CACHE / slug(name)
    known = {s["id"]: s for s in read_json(folder / "sources.json", {"sources": []})["sources"]}
    allowed = {s["host"] for s in config["sources"].values()}
    wanted = [("wikipedia_en", lambda: wikipedia("en.wikipedia.org", name, strict)),
              ("wikipedia_simple", lambda: wikipedia("simple.wikipedia.org", name, strict))]
    if plant:
        wanted.append(("kew", lambda: kew(name, config)))
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
    things = ordinary()
    if "--prehistoric" in sys.argv:
        names = list(prehistoric())
    elif "--ordinary" in sys.argv:
        names = list(things)
    else:
        names = args
    if not names:
        raise SystemExit(__doc__)
    config, old_ones = read_json(CONFIG), set(prehistoric())
    if "--ordinary" in sys.argv:
        # openings only, many to a request; Kew turns scripts away, so it is not asked here
        words = {name: narrowing_words(things[name], config) for name in names}
        for name, sources in fetch_openings(names, "--again" in sys.argv, words).items():
            got = ", ".join(f"{s['id']} ({s['chars']:,} letters, filed under '{s['title']}')"
                            for s in sources.values() if s.get("file"))
            missing = ", ".join(f"{s['id']}: {s['problem']}" for s in sources.values() if s.get("problem"))
            print(f"  {name}: {got or 'NOTHING'}" + (f"   [not found - {missing}]" if missing else ""), flush=True)
        return
    for name in names:
        plant = things.get(name, {}).get("kind_of_thing") == "plant"
        sources = fetch(name, config, "--again" in sys.argv, strict=name in old_ones, plant=plant)
        got = ", ".join(f"{s['id']} ({s['chars']:,} letters)" for s in sources if s.get("file"))
        missing = ", ".join(f"{s['id']}: {s['problem']}" for s in sources if s.get("problem"))
        print(f"  {name}: {got or 'NOTHING'}" + (f"   [not found - {missing}]" if missing else ""), flush=True)


if __name__ == "__main__":
    main()
