# Leisure Shelf

A small personal book manager for leisure reading, built from Bash programs.
Browse and search your shelf, look up book metadata, track reading status and
ratings, and find your next read.

[Watch the silent terminal walkthrough](media/demo.mp4).
The recording uses an isolated example library. Add your own narration before
submitting the assignment; the current video has no audio.

## Run

Requires Bash 3.2+, Gum, jq, curl, and Python 3. On macOS:

```bash
brew install gum jq python
./book-manager/app.sh
```

For an offline demonstration with a temporary example library:

```bash
./book-manager/app.sh --demo
```

The personal library starts empty. Its changes persist in `book-manager/data/books.csv`.
Demo changes are discarded on exit. Set `BOOK_MANAGER_OFFLINE=1` to use cached
metadata and the bundled catalog without a network connection.

## Architecture

`app.sh` opens the Gum UI. The UI calls workflows, which coordinate book and
recommendation components. Only `data/book_database.sh` accesses the personal
CSV; it uses Python's standard CSV library to handle commas, quotes, and Unicode.
Components exchange one JSON object per line on stdout, while progress and errors
go to stderr. The recommendation workflow starts history, interest, and discovery
programs with `&`, saves their process IDs using `$!`, waits for them with `wait`,
then pipes their combined output into the refinement component.

## Personalization

This shelf is for unwinding with literature: novels, short stories, mysteries,
fantasy, and travel writing. Default interests are novels, short stories, and
travel; they can be edited in the recommendation screen or
`book-manager/config/interests.txt`. Discovery explores other literary genres.
The history strategy uses actual saved books and ratings, and skips an empty
library. Every recommendation includes a reason.

Book lookup uses the [Open Library Search API](https://openlibrary.org/dev/docs/api/search).
Recommendations use a bundled 21-book catalog with source links, so the three
strategies run independently and also work offline. They use explainable rules;
the shortlist reserves a place for discovery and prioritizes familiar interests
for the remaining places. Catalog years are source-reported metadata, not verified
first-publication dates. These rules do not call an LLM.

## Check and explain

```bash
python3 tests/smoke.py
```

The checks use temporary libraries and cover persistence, metadata-to-save,
refinement, Unicode, actual parallel overlap, and partial strategy failures.
See [file responsibilities and a traced workflow](docs/WORKFLOW.md),
[中文讲解](docs/讲解.md),
[interfaces](docs/INTERFACES.md), [metadata provenance](docs/CATALOG.md),
and [demo operations and narration outline](docs/DEMO.md).

Based on the [onexi/ps02 starter](https://github.com/onexi/ps02).
The original assignment is preserved in [docs/assignment.md](docs/assignment.md).
MIT license; see [LICENSE](LICENSE).
