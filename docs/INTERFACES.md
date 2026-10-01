# Book Manager interfaces

The required five layers live under `book-manager/`. Target Bash 3.2+, jq,
curl, Python 3 (CSV handling only), and Gum. Keep components short and readable.

## Shared runtime

Every script uses `set -euo pipefail` and sources `../lib/common.sh` (or
`lib/common.sh` from app.sh). It defines:

- `BOOK_MANAGER_ROOT`: absolute directory containing app.sh.
- `BOOK_MANAGER_DATA_DIR`: default `$BOOK_MANAGER_ROOT/data`; override for tests/demo.
- `BOOK_MANAGER_CACHE_DIR`: default `$BOOK_MANAGER_ROOT/.cache`.
- `BOOK_MANAGER_OFFLINE`: default `0`; `1` disables network.
- `BOOK_MANAGER_INTERESTS`: comma-separated terms, default from config/interests.txt.
- `require_commands`: checks its arguments are installed, errors on stderr.
- `die`: prints its argument on stderr and exits 1.

## Records

One compact JSON object per line (JSON Lines). Never put progress/UI text on a
component's stdout. Missing year/rating is null. Missing text is an empty string.

Book metadata fields:
`id,title,author,genre,year,subjects,link,source`.
`subjects` is an array of strings. Open Library work IDs use `/works/OL...W`.
Manual books use a deterministic `manual:` ID assigned by the data layer.

The personal library adds `status,rating,owned`.
Statuses: `want_to_read`, `reading`, `finished`.
Rating: null or integer 1..5. Owned: boolean, default false.

Recommendation candidates add `strategy,score,reason`.
Strategies: `history`, `interests`, `discovery`. Score range: 0..10, local heuristic,
not a prediction of how much someone will enjoy a book. Refined candidates add
`strategies` (array), retaining `reason` as a readable explanation.

Genres for the bundled leisure catalog: `Literary fiction`, `Mystery`, `Fantasy`,
`Short stories`, `Travel & essays`. Default interests: `novels,short stories,travel`.
Support common Chinese aliases in interest matching. Discovery stays within
leisure literature, favoring a different genre from the reader's library/interests.
The real personal library starts empty; demo/example books never become claimed
reading history.

## Commands

```
data/book_database.sh init
data/book_database.sh list
data/book_database.sh search TERM
data/book_database.sh get ID
data/book_database.sh exists ID          # exit 0 if exists, 1 otherwise
data/book_database.sh add               # ONE JSON record on stdin; emits saved record
data/book_database.sh update ID FIELD VALUE # status/rating/owned; emits updated record
books/search_books.sh TERM              # alternatively one search term on stdin
books/fetch_book_metadata.sh TITLE [AUTHOR] # JSONL candidates; user selects a match
books/catalog.sh list                   # verified bundled metadata, JSONL
books/catalog.sh search QUERY [AUTHOR]  # live lookup, cache/bundled fallback
recommendations/recommend_from_history.sh
recommendations/recommend_from_interests.sh [INTERESTS]
recommendations/recommend_for_discovery.sh [INTERESTS]
recommendations/refine_recommendations.sh [LIMIT]  # JSONL stdin, default limit 5
workflows/manage_library.sh list|search|lookup|add|get|update ...
workflows/get_recommendations.sh [INTERESTS] [LIMIT]
```

Only `data/book_database.sh` directly reads/writes `books.csv`. Standard-library
Python CSV handling may be embedded there so commas, quotes, and Unicode remain
safe. Other scripts ask it for JSONL. Exclude duplicates by work ID and normalized
title+author. Validate input and atomically replace the CSV on write.

`books/catalog.sh` owns external catalog retrieval/cache, separate from the
personal library. Retain source links and collection date for bundled metadata.
Live search returns candidates, not an automatically accepted identity. Unknown
books can be added manually with clearly absent metadata.

`get_recommendations.sh` launches three programs using `&`, saves `$!`, reports
running/done via stderr, waits for each PID, and pipes combined results to refine.
Failures must be reported, successful agents may still contribute. Refine removes
existing library books and duplicates, merges strategy reasons, and favors a
shortlist that includes discovery when available. No fabricated reading history.
