#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands python3
if [ "${1:-}" = "add" ]; then
    BOOK_MANAGER_JSON_INPUT="$(cat)"
    export BOOK_MANAGER_JSON_INPUT
fi

exec python3 - "$@" <<'PY'
import csv
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata

FIELDS = ["id", "title", "author", "genre", "year", "subjects", "link",
          "source", "status", "rating", "owned"]
STATUSES = {"want_to_read", "reading", "finished"}
DATA_DIR = os.environ["BOOK_MANAGER_DATA_DIR"]
CSV_PATH = os.path.join(DATA_DIR, "books.csv")

def fail(message):
    print("book_database.sh: " + message, file=sys.stderr)
    raise SystemExit(2)

def emit(book):
    result = dict(book)
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))

def normalize(value):
    value = unicodedata.normalize("NFKC", value).casefold()
    return "".join(ch for ch in value if ch.isalnum())

def empty_record():
    return {"id": "", "title": "", "author": "", "genre": "", "year": None,
            "subjects": [], "link": "", "source": "", "status": "want_to_read",
            "rating": None, "owned": False}

def decode_row(row):
    book = empty_record()
    book.update(row)
    try:
        book["year"] = int(book["year"]) if book["year"] else None
        book["rating"] = int(book["rating"]) if book["rating"] else None
        book["subjects"] = json.loads(book["subjects"] or "[]")
        book["owned"] = book["owned"] in ("1", "true", "True")
    except (ValueError, TypeError, json.JSONDecodeError):
        fail("books.csv contains an invalid record")
    return book

def load():
    if not os.path.exists(CSV_PATH):
        return []
    try:
        with open(CSV_PATH, "r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != FIELDS:
                fail("books.csv has an unexpected header; run init only for a new library")
            return [decode_row(row) for row in reader]
    except (OSError, csv.Error) as exc:
        fail("cannot read books.csv: " + str(exc))

def write_all(books):
    os.makedirs(DATA_DIR, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".books.", suffix=".csv", dir=DATA_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS, lineterminator="\n")
            writer.writeheader()
            for book in books:
                row = dict(book)
                row["year"] = "" if book["year"] is None else book["year"]
                row["rating"] = "" if book["rating"] is None else book["rating"]
                row["subjects"] = json.dumps(book["subjects"], ensure_ascii=False, separators=(",", ":"))
                row["owned"] = "true" if book["owned"] else "false"
                writer.writerow(row)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, CSV_PATH)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise

def validate(book):
    if not isinstance(book, dict):
        fail("input must be one JSON object")
    allowed = set(FIELDS)
    if set(book) - allowed:
        fail("unknown field(s): " + ", ".join(sorted(set(book) - allowed)))
    clean = empty_record()
    clean.update(book)
    for key in ("title", "author", "genre", "link", "source"):
        if not isinstance(clean[key], str):
            fail(key + " must be a string")
    clean["title"] = clean["title"].strip()
    clean["author"] = clean["author"].strip()
    if not clean["title"] or not clean["author"]:
        fail("title and author are required")
    if clean["year"] is not None and (type(clean["year"]) is not int or not 0 < clean["year"] < 10000):
        fail("year must be null or a four-digit positive integer")
    if not isinstance(clean["subjects"], list) or any(not isinstance(item, str) for item in clean["subjects"]):
        fail("subjects must be an array of strings")
    if clean["status"] not in STATUSES:
        fail("status must be want_to_read, reading, or finished")
    if clean["rating"] is not None and (type(clean["rating"]) is not int or clean["rating"] < 1 or clean["rating"] > 5):
        fail("rating must be null or an integer from 1 to 5")
    if type(clean["owned"]) is not bool:
        fail("owned must be a boolean")
    if not isinstance(clean["id"], str):
        fail("id must be a string")
    if clean["id"]:
        if not re.match(r"^/works/OL[0-9]+W$|^manual:[0-9a-f]{64}$", clean["id"]):
            fail("id must be an Open Library work ID or a data-layer manual ID")
    else:
        clean["id"] = "manual:" + hashlib.sha256((normalize(clean["title"]) + "\0" + normalize(clean["author"])).encode("utf-8")).hexdigest()
    return clean

def main():
    if len(sys.argv) < 2:
        fail("usage: book_database.sh init|list|search TERM|get ID|exists ID|add|update ID FIELD VALUE")
    command = sys.argv[1]
    args = sys.argv[2:]
    if command == "init" and not args:
        os.makedirs(DATA_DIR, exist_ok=True)
        if not os.path.exists(CSV_PATH):
            write_all([])
        else:
            load()
        return
    books = load()
    if command == "list" and not args:
        for book in books: emit(book)
    elif command == "search" and len(args) == 1 and args[0].strip():
        term = normalize(args[0])
        for book in books:
            searchable = " ".join([book["title"], book["author"], book["genre"], book["status"]] + book["subjects"])
            if term in normalize(searchable): emit(book)
    elif command in ("get", "exists") and len(args) == 1:
        match = next((book for book in books if book["id"] == args[0]), None)
        if command == "exists":
            raise SystemExit(0 if match else 1)
        if match is None: fail("book not found: " + args[0])
        emit(match)
    elif command == "add" and not args:
        try:
            raw = os.environ.get("BOOK_MANAGER_JSON_INPUT", "")
            parsed = json.loads(raw)
        except (ValueError, UnicodeError) as exc:
            fail("stdin must contain one valid JSON object: " + str(exc))
        book = validate(parsed)
        book_key = (normalize(book["title"]), normalize(book["author"]))
        for old in books:
            if old["id"] == book["id"] or (normalize(old["title"]), normalize(old["author"])) == book_key:
                fail("duplicate book ID or normalized title+author")
        books.append(book)
        write_all(books)
        emit(book)
    elif command == "update" and len(args) == 3:
        book_id, field, value = args
        if field not in ("status", "rating", "owned"):
            fail("field must be status, rating, or owned")
        book = next((item for item in books if item["id"] == book_id), None)
        if book is None: fail("book not found: " + book_id)
        if field == "status":
            if value not in STATUSES: fail("status must be want_to_read, reading, or finished")
            book[field] = value
        elif field == "rating":
            if value == "null": book[field] = None
            elif re.match(r"^[1-5]$", value): book[field] = int(value)
            else: fail("rating must be null or an integer from 1 to 5")
        else:
            if value not in ("true", "false"): fail("owned must be true or false")
            book[field] = value == "true"
        write_all(books)
        emit(book)
    else:
        fail("invalid command or arguments")

main()
PY
