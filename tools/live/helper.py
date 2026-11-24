"""The helper on the owner's PC: it serves the game, and keeps sets ready ahead of the child.

The owner's design of 24 Nov 2026: "there is a one game... data is dynamic". The game
ships with its first set and the sets under it. After each set the game ranks the groups
by how well he did them and keeps the lines to follow in his saved progress, best first.
This helper reads those lines and keeps a few sets ready ahead of him: "max 3 to 4 sets
at any time... as one is used up... we prepare (either from the existing data or made
from api calls)... just like how chess branches are assessed by engines". A set that is
not in the data is made by the job (tools/prepare_next.py --only): DeepSeek for the
facts, the image model for the pictures, every check as before. He plays other sets
meanwhile, and the game takes up a new set as soon as it is ready, with no rebuild.

It runs on this PC because the keys are here and must never be in the game. The game is
the built web app (build/web), served from here; its data, pictures and sounds are
served straight from the project's Assets folder, so what the job adds shows at once.

    flutter build web --pwa-strategy=none       once, and after the game's own code changes (without the
                                                offline cache, so a reload always shows the game as built)
    python tools/live/helper.py                 serve at http://localhost:8200 and keep sets ready
    python tools/live/helper.py --lan           also for a tablet on the same Wi-Fi
    python tools/live/helper.py --no-making     serve only: nothing is made, nothing is spent

Spending: at most Rs 200 a day (the owner's figure while this is a demo) and at most
Rs 90 for one set, as hard caps handed to the job. It never pushes and never deploys.
What it does is written to tools/live/out/ (kept out of git): helper.log, ledger.json.
"""
import datetime
import http.server
import json
import mimetypes
import pathlib
import subprocess
import sys
import threading
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/catalogue"))
import catalogue as cat      # noqa: E402  the master record: which sets can open now

WEB = ROOT / "build/web"
ASSETS = ROOT / "Assets"
OUT = ROOT / "tools/live/out"
LEDGER = OUT / "ledger.json"
PROGRESS = ROOT / "tools/job/progress.json"
RUNS = ROOT / "tools/job/runs"
BUFFER = 3              # ready sets kept ahead of him (the owner: "max 3 to 4 sets at any time")
DAY_CAP_INR = 200       # the owner's figure of 24 Nov 2026, "for now"
SET_CAP_INR = 90        # the most one set may cost
SMALLEST_RUN_INR = 25   # below this a set could not be finished


def log(text: str):
    OUT.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  {text}"
    print(line, flush=True)
    with open(OUT / "helper.log", "a", encoding="utf-8") as file:
        file.write(line + "\n")


def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


# ------------------------------------------------------------------ what to make next

def lines_of(progress: dict) -> list:
    """The lines to follow, best first, as the game saved them."""
    lines = (progress or {}).get("lines")
    return [line for line in lines if isinstance(line, str)] if isinstance(lines, list) else []


def next_to_make(lines: list, can_open: dict, dead: dict, buffer: int = BUFFER):
    """Which set to make now, or None. `can_open` is circle -> whether its set can be made
    from the data as it stands. The buffer is his best lines: the first `buffer` of them
    are kept ready, best first, whatever lesser lines happen to be ready already ("while he
    is doing man-made things, the system gets what it wants of domestic animals"). A line
    that is no circle at all, or that could not be made (`dead`), does not take a place."""
    best = [line for line in lines if line in can_open and line not in dead][:buffer]
    return next((line for line in best if not can_open[line]), None)


def spent_today(ledger: list, today: datetime.date) -> float:
    return sum(entry.get("spent_inr", 0.0) for entry in ledger if entry.get("date") == today.isoformat())


def newest_run():
    runs = sorted(p for p in RUNS.iterdir() if p.is_dir()) if RUNS.exists() else []
    return runs[-1] if runs else None


def spent_inr(run_folder: pathlib.Path) -> float:
    run = read_json(run_folder / "run.json", {})
    rate = read_json(ROOT / "tools/pictures/plan.json", {})["prices"]["inr_per_usd"]
    return round(sum((run.get("spent_usd") or {}).values()) * rate, 1)


def can_open_now() -> dict:
    return {cid: bool(c.get("can_open_now")) for cid, c in cat.load()["worked_out"]["circles"].items()}


# ------------------------------------------------------------------ the state the game asks for

def version() -> str:
    """Changes whenever the data the game reads has changed."""
    files = sorted((ASSETS / "data").glob("*.json"))
    return str(max((f.stat().st_mtime_ns for f in files), default=0))


def files() -> list:
    """Every picture and sound the game may show or play, as the game names them."""
    found = []
    for folder in ("pictures", "audio", "images"):
        base = ASSETS / folder
        if base.exists():
            found += ["Assets/" + p.relative_to(ASSETS).as_posix() for p in base.rglob("*") if p.is_file()]
    return found


class Helper:
    def __init__(self, making: bool, buffer: int = BUFFER):
        self.making_allowed, self.buffer = making, buffer
        self.making = None          # the set being made now
        self.dead = {}              # line -> why it could not be made (for this run of the helper)
        self.note = ""
        self.wake = threading.Event()
        self.lock = threading.Lock()

    def state(self) -> dict:
        opens = can_open_now()
        lines = lines_of(read_json(PROGRESS, {}))
        return {"version": version(), "files": files(),
                "lines": lines, "ready": [line for line in lines if opens.get(line)],
                "making": self.making, "dead": sorted(set(self.dead) | {line for line in lines if line not in opens}),
                "why_not": self.dead, "note": self.note,
                "spent_today_inr": spent_today(read_json(LEDGER, []), datetime.date.today()), "day_cap_inr": DAY_CAP_INR}

    def take_progress(self, body: bytes) -> dict:
        progress = json.loads(body.decode("utf-8"))
        if not isinstance(progress, dict) or "boards" not in progress:
            raise ValueError("not a saved progress")
        with self.lock:
            PROGRESS.write_text(json.dumps(progress, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        self.wake.set()
        opens = can_open_now()
        return {"ok": True, "dead": sorted(set(self.dead) | {line for line in lines_of(progress) if line not in opens})}

    def work(self):
        """Keep sets ready ahead of him, one at a time, inside the day's cap."""
        while True:
            self.wake.wait(timeout=60)
            self.wake.clear()
            try:
                while self.making_allowed and self.make_one():
                    pass
            except Exception as error:      # the helper must keep serving whatever happens to a run
                log(f"a run went wrong: {type(error).__name__}: {error}")
                self.making = None

    def make_one(self) -> bool:
        """Make the next set, if one is wanted and the day's money allows. True if a run was made."""
        target = next_to_make(lines_of(read_json(PROGRESS, {})), can_open_now(), self.dead, self.buffer)
        if target is None:
            self.note = ""
            return False
        today = datetime.date.today()
        ledger = read_json(LEDGER, [])
        left = DAY_CAP_INR - spent_today(ledger, today)
        if left < SMALLEST_RUN_INR:
            self.note = f"the day's Rs {DAY_CAP_INR} is spent; {target} waits for tomorrow"
            return False
        cap = min(left, SET_CAP_INR)
        self.making, before = target, newest_run()
        log(f"making {target} (cap Rs {cap:.0f}; Rs {left:.0f} of today's Rs {DAY_CAP_INR} left)")
        done = subprocess.run([sys.executable, str(ROOT / "tools/prepare_next.py"), "--only", target, "--new-to-him",
                               "--cap", f"{cap:.0f}"], cwd=ROOT, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
        output = (done.stdout or "") + ("\n" + (done.stderr or "") if done.returncode else "")
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"run_{datetime.datetime.now():%Y%m%d_%H%M%S}_{target.replace('/', '_')}.log").write_text(output, encoding="utf-8")
        after = newest_run()
        spent = spent_inr(after) if after and after != before else 0.0
        ledger.append({"date": today.isoformat(), "set": target, "run": after.name if after and after != before else None,
                       "spent_inr": spent, "cap_inr": round(cap)})
        LEDGER.write_text(json.dumps(ledger, indent=1) + "\n", encoding="utf-8")
        if can_open_now().get(target):
            log(f"ready: {target} (Rs {spent:.1f})")
        else:
            why = next((line.strip() for line in output.splitlines()
                        if line.strip().startswith(("cannot prepare", "held", "STOPPED", "Held by the rules"))), "")
            self.dead[target] = why or "the job could not make it; see its log in tools/live/out"
            log(f"could not make {target} (Rs {spent:.1f}): {self.dead[target]}")
        self.making = None
        return True


# ------------------------------------------------------------------ serving

def inside(base: pathlib.Path, relative: str):
    """The file `relative` under `base`, or None if it is not a file there (never above it)."""
    path = (base / relative).resolve()
    return path if path.is_file() and base.resolve() in path.parents else None


def handler_for(helper: Helper):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):       # quiet: the helper's own log says what matters
            pass

        def reply(self, code: int, body: bytes, kind: str):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")       # the data grows while he plays
            self.end_headers()
            self.wfile.write(body)

        def reply_json(self, data, code: int = 200):
            self.reply(code, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def do_GET(self):
            path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path).lstrip("/")
            if path == "live/state":
                return self.reply_json(helper.state())
            file = None
            if path.startswith("assets/Assets/"):       # the game's data, pictures and sounds: live from the project
                file = inside(ASSETS, path[len("assets/Assets/"):])
            file = file or inside(WEB, path or "index.html")
            if file is None:
                return self.reply(404, b"not found", "text/plain")
            self.reply(200, file.read_bytes(), mimetypes.guess_type(file.name)[0] or "application/octet-stream")

        def do_POST(self):
            if urllib.parse.urlparse(self.path).path != "/live/progress":
                return self.reply(404, b"not found", "text/plain")
            try:
                body = self.rfile.read(min(int(self.headers.get("Content-Length") or 0), 2_000_000))
                self.reply_json(helper.take_progress(body))
            except (ValueError, KeyError) as error:
                self.reply_json({"ok": False, "why": str(error)}, 400)
    return Handler


def main():
    argv = sys.argv[1:]
    port = int(argv[argv.index("--port") + 1]) if "--port" in argv else 8200
    buffer = int(argv[argv.index("--buffer") + 1]) if "--buffer" in argv else BUFFER
    if not (WEB / "index.html").exists():
        raise SystemExit("The game is not built yet. Run:  flutter build web --pwa-strategy=none")
    mimetypes.add_type("application/wasm", ".wasm")
    mimetypes.add_type("image/webp", ".webp")
    helper = Helper(making="--no-making" not in argv, buffer=buffer)
    threading.Thread(target=helper.work, daemon=True).start()
    host = "0.0.0.0" if "--lan" in argv else "127.0.0.1"
    server = http.server.ThreadingHTTPServer((host, port), handler_for(helper))
    log(f"the game is at http://localhost:{port}" + ("  (and on this PC's Wi-Fi address)" if "--lan" in argv else "")
        + ("; sets are made ahead of the child, at most Rs %d a day" % DAY_CAP_INR if helper.making_allowed
           else "; serving only: nothing is made"))
    helper.wake.set()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
