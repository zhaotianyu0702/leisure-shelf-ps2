# How this application works

Book metadata comes from Open Library, while the personal library contains only
books the reader adds. Recommendations are selected from a bundled catalog of
21 leisure-reading books. This catalog includes source links, works offline,
and is separate from the reader's reading history. When adding a book, the app
can also look up titles outside the bundled catalog through a live search.

The default interests are novels, short stories, and travel writing. The reader
can enter other interests, such as `mystery,short stories`, on the recommendation
screen. The history strategy uses actual saved books and ratings; the interest
strategy matches genres or topics; the discovery strategy explores other
literary genres. The final shortlist reserves one place for discovery and
prioritizes history or interest matches for the remaining places.

## A concrete example: adding The Hobbit

1. `app.sh` opens the main menu, where the reader selects **Add Book**.
2. `ui/library_screen.sh` collects the title and author and passes them to
   `manage_library.sh lookup`.
3. The workflow calls `fetch_book_metadata.sh`, which calls `catalog.sh` to
   find matching candidates.
4. The reader selects the correct book, then chooses a reading status and
   whether they own it.
5. The workflow passes the book to `book_database.sh add`. The data layer
   validates its fields, checks for duplicates, saves the CSV, and returns the
   saved record.

Scripts exchange one JSON object per line. Here is a shortened example:

```json
{"id":"/works/OL27482W","title":"The Hobbit","author":"J.R.R. Tolkien","genre":"Fantasy"}
```

Full records also include the catalog year, subjects, source link, and other
fields. JSON safely represents commas, quotation marks, and Unicode characters
in book titles. `jq` selects and processes these fields. The data layer converts
JSON to CSV when saving and converts CSV back to JSON when reading. Other
components do not need to know how the CSV is parsed.

## Where parallel execution and pipes happen

In `workflows/get_recommendations.sh`, `&` starts each recommendation program
in the background, allowing all three to run concurrently. `$!` captures the
process ID of the program just started, and `wait` waits for that program to
finish. The terminal shows each strategy's status while they run. Three files
temporarily hold their results, which are then combined and passed through a
real pipe:

```bash
cat history.jsonl interests.jsonl discovery.jsonl | refine_recommendations.sh
```

This is a simplified illustration; the actual workflow uses a separate
temporary directory. The refinement program reads candidates from stdin,
excludes books already in the library, merges duplicate recommendations and
their reasons, and outputs a shortlist. The recommendation screen displays
that shortlist and lets the reader select a book to save.

Each program reserves stdout for JSON data and stderr for progress and errors.
This prevents progress messages from mixing with the book data passed to the
next program. If a strategy fails, the workflow discards its partial output;
the other successful strategies can still contribute results.

## Scope and limitations

The recommendations use explainable rules and do not call an LLM inside the
application. An empty library provides no history evidence, so the history
strategy skips it. Low-rated books are also excluded from positive evidence.
The recommendation candidate pool is currently limited to the bundled catalog.
Years are source-reported catalog metadata and should not automatically be
treated as first-publication dates. Genres are the project's classifications.

`--demo` uses a temporary example library that is deleted on exit. The real
personal library starts empty. The silent video demonstrates three operations;
the reader must add their own narration to meet the assignment's narrated-video
requirement.

See [WORKFLOW.md](WORKFLOW.md) for each file's inputs, outputs, and responsibilities,
and [INTERFACES.md](INTERFACES.md) for the command and data contracts.
