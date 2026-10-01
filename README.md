# Leisure Shelf

A personal terminal book manager for leisure literature, built from Bash programs.

[Watch the terminal demo](media/demo.mp4) — 42 seconds, currently silent.
The recording uses a temporary example library.

## Run

Requires Bash 3.2+, Gum, jq, curl, and Python 3. On macOS:

```bash
brew install gum jq python
./book-manager/app.sh
```

For an offline demo with a temporary example library:

```bash
./book-manager/app.sh --demo
```

Regular mode saves changes in `book-manager/data/books.csv`; the initial library
is empty. Demo changes are discarded on exit.

## Architecture

`app.sh` opens the Gum UI. The UI calls workflows, which coordinate book and
recommendation components. Only `data/book_database.sh` accesses the personal
CSV; it uses Python's standard CSV library to handle commas, quotes, and Unicode.
Components exchange one JSON object per line on stdout, while progress and errors
go to stderr. The recommendation workflow starts history, interest, and discovery
programs with `&`, saves their process IDs using `$!`, waits for them with `wait`,
then pipes their combined output into the refinement component.

## Personalization

This shelf is for novels, short stories, mysteries, fantasy, and travel writing.
Default interests are novels, short stories, and travel; edit them in the
recommendation screen or `book-manager/config/interests.txt`. History uses actual
saved books and ratings, interests match genres and topics, and discovery explores
other literary genres. The rule-based shortlist includes reasons and reserves a
place for discovery. Metadata lookup uses English-edition titles from the
[Open Library Search API](https://openlibrary.org/dev/docs/api/search), while
recommendations use a bundled 21-book catalog with source links. Years are
source-reported catalog metadata.

Based on the [onexi/ps02 starter](https://github.com/onexi/ps02).
MIT license; see [LICENSE](LICENSE).
