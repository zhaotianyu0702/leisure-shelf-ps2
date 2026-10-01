#!/usr/bin/env python3
"""Offline integration checks; never modify the reader's real library."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1] / "book-manager"


def run(root, env, path, *args, payload=None, ok=True):
    result = subprocess.run([str(root / path), *args], env=env,
                            input=payload, text=True, capture_output=True, timeout=30)
    if ok and result.returncode:
        raise AssertionError(f"{path}: {result.stderr}")
    return result


def records(result):
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]


with tempfile.TemporaryDirectory(prefix="book-manager-check-") as directory:
    temp = Path(directory)
    env = dict(os.environ, BOOK_MANAGER_DATA_DIR=str(temp / "library"),
               BOOK_MANAGER_CACHE_DIR=str(temp / "cache"), BOOK_MANAGER_OFFLINE="1")
    workflow = "workflows/manage_library.sh"
    run(ROOT, env, "data/book_database.sh", "init")
    assert records(run(ROOT, env, workflow, "list")) == []
    shortlist = records(run(ROOT, env, "workflows/get_recommendations.sh"))
    assert len(shortlist) == 5
    assert any("discovery" in item["strategies"] for item in shortlist)
    assert any("interests" in item["strategies"] for item in shortlist)
    assert all("history" not in item["strategies"] for item in shortlist)

    matches = records(run(ROOT, env, workflow, "lookup", "The Hobbit", "J.R.R. Tolkien"))
    book = next(item for item in matches if item["title"] == "The Hobbit")
    saved = records(run(ROOT, env, workflow, "add", payload=json.dumps(book)))[0]
    assert saved["id"] == book["id"] and saved["status"] == "want_to_read"
    assert run(ROOT, env, workflow, "add", payload=json.dumps(book), ok=False).returncode != 0
    assert records(run(ROOT, env, "recommendations/recommend_from_history.sh")), "Unrated saved books must supply history evidence"
    run(ROOT, env, workflow, "update", saved["id"], "status", "finished")
    run(ROOT, env, workflow, "update", saved["id"], "rating", "5")
    reread = records(run(ROOT, env, workflow, "get", saved["id"]))[0]
    assert reread["rating"] == 5 and reread["status"] == "finished"
    assert records(run(ROOT, env, "books/search_books.sh", payload="finished\n"))[0]["id"] == book["id"]

    manual = {"title": '中文，书名 "A"\n下一行', "author": "读者 作者", "genre": "Short stories"}
    manual_saved = records(run(ROOT, env, workflow, "add", payload=json.dumps(manual)))[0]
    assert records(run(ROOT, env, workflow, "get", manual_saved["id"]))[0]["title"] == manual["title"]
    assert run(ROOT, env, "data/book_database.sh", "add", payload="not JSON", ok=False).returncode != 0
    assert run(ROOT, env, workflow, "update", saved["id"], "rating", "6", ok=False).returncode != 0
    candidates = records(run(ROOT, env, "recommendations/recommend_from_history.sh"))
    assert candidates and all(item["id"] != saved["id"] for item in candidates)

    # The pipe collapses duplicate strategies, excludes existing works, and
    # tolerates malformed candidates without contaminating stdout.
    candidate = next(item for item in shortlist if item["id"] != book["id"])
    duplicate = dict(candidate, strategy="history", reason="History also suggests this book")
    existing = dict(book, strategy="interests", score=10, reason="Already saved")
    payload = "\n".join(json.dumps(item) for item in [candidate, duplicate, existing]) + "\ninvalid\n"
    refined = records(run(ROOT, env, "recommendations/refine_recommendations.sh", "5", payload=payload))
    assert len(refined) == 1 and "history" in refined[0]["strategies"]
    unicode_existing = dict(manual_saved, id="/works/OL999999W", title='中文书名A下一行',
                            author="读者作者", source="fixture", link="https://example.org/book",
                            strategy="history", score=5, reason="Same title with punctuation removed")
    assert records(run(ROOT, env, "recommendations/refine_recommendations.sh", payload=json.dumps(unicode_existing))) == []
    latest = records(run(ROOT, env, "workflows/get_recommendations.sh", "小说，短篇"))
    assert latest and all(item["id"] != saved["id"] for item in latest)
    run(ROOT, env, workflow, "add", payload=json.dumps(latest[0]))

    # A copied application with timed fixtures verifies actual process overlap
    # and that partial output from a failed agent is discarded.
    copied = temp / "timed-app"
    shutil.copytree(ROOT, copied, ignore=shutil.ignore_patterns(".cache"))
    timed_env = dict(env, BOOK_MANAGER_DATA_DIR=str(temp / "timed-library"))
    run(copied, timed_env, "data/book_database.sh", "init")
    events = temp / "events"
    events.mkdir()
    scripts = [("history", "recommend_from_history.sh"), ("interests", "recommend_from_interests.sh"),
               ("discovery", "recommend_for_discovery.sh")]
    for index, (strategy, filename) in enumerate(scripts):
        fixture = dict(shortlist[index], strategy=strategy, strategies=[strategy])
        code = ("#!/bin/bash\nset -e\n"
                f"python3 -c 'import time; print(time.time())' > '{events / (strategy + '.start')}'\n"
                "sleep 0.4\n"
                f"python3 -c 'import time; print(time.time())' > '{events / (strategy + '.end')}'\n"
                "cat <<'JSON'\n" + json.dumps(fixture) + "\nJSON\n")
        script = copied / "recommendations" / filename
        script.write_text(code)
        script.chmod(0o755)
    timed = run(copied, timed_env, "workflows/get_recommendations.sh")
    assert len(records(timed)) == 3
    starts = [float(path.read_text()) for path in events.glob("*.start")]
    ends = [float(path.read_text()) for path in events.glob("*.end")]
    assert max(starts) < min(ends), "Recommendation strategies did not overlap"
    failed = copied / "recommendations" / scripts[0][1]
    failed.write_text(failed.read_text() + "exit 7\n")
    partial = run(copied, timed_env, "workflows/get_recommendations.sh")
    assert "history: failed" in partial.stderr
    assert len(records(partial)) == 2
    assert shortlist[0]["id"] not in {item["id"] for item in records(partial)}

print("PASS: isolated library, metadata lookup, pipe refinement, Unicode, parallel overlap, and partial failure")
