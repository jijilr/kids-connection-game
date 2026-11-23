"""The weekly run of the job, started by Windows Task Scheduler on the owner's machine.

The owner's ruling of 23 Nov 2026: the job runs in the background; it may spend at most
Rs 200 a week without asking; his results reach this machine as the file a grown-up saves
from the game (tools/job/progress.json); and nothing goes to the live site without his
yes. So this does no more than run `prepare_next.py` once, under what is left of the
week's Rs 200, and leave the digest where he will find it:

    tools/job/weekly/LATEST.md      the digest of the last weekly run, or why it did not run
    tools/job/weekly/ledger.json    what each weekly run spent, to keep the week's cap

It does not run when the work is not in a fit state for a run to commit to: another
branch checked out than the work branch, or changes not yet committed (someone is at
work here). It then says why in LATEST.md and tries again next week. Like the job, it
never pushes and never deploys. The folder tools/job/weekly is kept out of git.

    python tools/job/weekly.py              what the scheduled task runs
    python tools/job/weekly.py --dry-run    the plan only: nothing is spent or recorded
    python tools/job/weekly.py --install    register the weekly task (Sundays, 11:00)
"""
import datetime
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/job/weekly"
LEDGER = HERE / "ledger.json"
LATEST = HERE / "LATEST.md"
RUNS = ROOT / "tools/job/runs"
WEEK_CAP_INR = 200          # the owner's cap for the background job, per seven days
SMALLEST_RUN_INR = 10       # below this, a run could not finish even one thing
WORK_BRANCH = "fresh-start"
TASK = "Connections game - prepare the next level (weekly)"


def git(*args) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout.strip()


def read_ledger() -> list:
    try:
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []


def spent_this_week(ledger: list, today: datetime.date) -> float:
    week_ago = today - datetime.timedelta(days=6)
    return sum(entry.get("spent_inr", 0.0) for entry in ledger
               if datetime.date.fromisoformat(entry["date"]) >= week_ago)


def why_not(today: datetime.date, ledger: list) -> str:
    """Why a run must not start now, or '' when it may."""
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch != WORK_BRANCH:
        return f"the branch checked out is '{branch}', not the work branch '{WORK_BRANCH}'"
    if git("status", "--porcelain", "--untracked-files=normal"):
        return "there are changes not yet committed: someone is at work here, and a run would mix its commit with theirs"
    left = WEEK_CAP_INR - spent_this_week(ledger, today)
    if left < SMALLEST_RUN_INR:
        return f"the week's Rs {WEEK_CAP_INR} is spent (Rs {WEEK_CAP_INR - left:.0f} in the last seven days)"
    return ""


def newest_run() -> pathlib.Path:
    runs = sorted(p for p in RUNS.iterdir() if p.is_dir()) if RUNS.exists() else []
    return runs[-1] if runs else None


def spent_inr(run_folder: pathlib.Path) -> float:
    run = json.loads((run_folder / "run.json").read_text(encoding="utf-8"))
    rate = json.loads((ROOT / "tools/pictures/plan.json").read_text(encoding="utf-8"))["prices"]["inr_per_usd"]
    return round(sum((run.get("spent_usd") or {}).values()) * rate, 1)


def write_latest(lines: list):
    HERE.mkdir(parents=True, exist_ok=True)
    LATEST.write_text("\n".join(lines) + "\n", encoding="utf-8")


def install():
    """Register the weekly task with Windows Task Scheduler, for this user: Sundays at
    11:00, and at the next chance if the machine was off then. It runs only while he is
    signed in, so the keys in his environment are there and nothing is stored with it."""
    python = sys.executable.replace("'", "''")
    script = str(pathlib.Path(__file__).resolve()).replace("'", "''")
    root = str(ROOT).replace("'", "''")
    command = (
        f"$action = New-ScheduledTaskAction -Execute '{python}' -Argument '\"{script}\"' -WorkingDirectory '{root}'; "
        "$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 11:00; "
        "$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 3) "
        "-DontStopIfGoingOnBatteries -AllowStartIfOnBatteries; "
        f"Register-ScheduledTask -TaskName '{TASK}' -Action $action -Trigger $trigger -Settings $settings "
        "-Description 'Runs tools/job/weekly.py: the job that prepares the next level, at most Rs 200 a week. Never pushes or deploys.' "
        "-Force | Out-Null; "
        f"(Get-ScheduledTask -TaskName '{TASK}').State; "
        f"(Get-ScheduledTaskInfo -TaskName '{TASK}').NextRunTime")
    done = subprocess.run(["powershell", "-NoProfile", "-Command", command], capture_output=True, text=True)
    print(done.stdout.strip() or done.stderr.strip())


def main():
    if "--install" in sys.argv:
        install()
        return
    dry = "--dry-run" in sys.argv
    today = datetime.date.today()
    ledger = read_ledger()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    reason = why_not(today, ledger)
    if reason and not dry:
        write_latest([f"# Weekly run of {stamp}: did not run", "", f"It did not run because {reason}.",
                      "It tries again next week; or run it by hand: python tools/job/weekly.py"])
        print("did not run:", reason)
        return
    cap = WEEK_CAP_INR - spent_this_week(ledger, today)
    before = newest_run()
    command = [sys.executable, str(ROOT / "tools/prepare_next.py"), "--cap", f"{cap:.0f}"] + (["--dry-run"] if dry else [])
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = (done.stdout or "") + (("\n" + done.stderr) if done.returncode else "")
    if dry:
        print(output)
        return
    after = newest_run()
    spent = spent_inr(after) if after and after != before else 0.0
    ledger.append({"date": today.isoformat(), "run": after.name if after and after != before else None,
                   "spent_inr": spent, "cap_inr": round(cap)})
    HERE.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(ledger, indent=1) + "\n", encoding="utf-8")
    digest = output[output.find("DIGEST"):] if "DIGEST" in output else output[-3000:]
    write_latest([f"# Weekly run of {stamp}", "",
                  f"Spent Rs {spent:.1f} of the week's Rs {WEEK_CAP_INR} (this run's cap was Rs {cap:.0f}).",
                  "Nothing was pushed or put on the live site; that waits for the owner's yes.", "",
                  "```", digest.strip(), "```"])
    print(f"spent Rs {spent:.1f}; digest in {LATEST.relative_to(ROOT)}")
    if done.returncode:
        sys.exit(done.returncode)


if __name__ == "__main__":
    main()
