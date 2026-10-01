# External metadata catalog

`book-manager/books/catalog.sh list` emits the bundled, source-linked catalog
as JSON Lines. The snapshot contains 21 Open Library work records collected on
2026-10-01. The stored title, author, source-reported catalog year (`year`), subjects,
edition count, and work ID come from Open Library Search API results; `link`
points to each work record.
The `genre` field is our leisure-reading classification, not an Open Library
field. Subjects are the first twelve subject labels returned by the API.

Year provenance exceptions: Open Library reports 1998 for *The Book Thief*,
but Markus Zusak's official books page dates it to 2005, so this snapshot leaves
that `year` null instead of carrying forward the conflicting value. Open
Library reports 2017 for *The Travelling Cat Chronicles*; Kodansha's official
rights catalog also gives 2017 for the listed edition. This confirms that edition's
date, not the work's first publication. The UI calls this field "Catalog year".
See [Zusak's
book list](https://www.markuszusak.com/books) and [Kodansha's catalog
entry](https://kbirc.kodansha.co.jp/books/1000).

Use `catalog.sh search QUERY [AUTHOR]` for a live lookup. It requests only the
work key, title, author names, first publication year, subjects, and edition
count, returns at most ten candidates, and caches the JSONL result under
`BOOK_MANAGER_CACHE_DIR`. Search output is a set of candidates. A person must
compare title and author and select the intended work before adding it to the
personal library. `fetch_book_metadata.sh TITLE [AUTHOR]` is the same candidate
lookup intended for the metadata-enrichment step; it does not accept the first
result automatically. Live candidates have an empty `genre` because genre is
assigned only for the curated snapshot.

Set `BOOK_MANAGER_OFFLINE=1` to skip the network. The command returns the exact
matching cached search when available, otherwise matching bundled records.
When an online request fails, it uses those same fallbacks. Notices and errors
never go to stdout, so successful output remains JSONL. Concurrent API requests
share a one-second request gate and repeat searches use the local cache. Fallback
status is reported on stderr; stdout remains JSONL only.

Open Library describes its Search API as experimental and asks clients to avoid
bulk metadata downloads. This catalog uses small, user-triggered searches and
does not crawl the service. API details: [Search API](https://openlibrary.org/dev/docs/api/search)
and [API usage guidelines](https://openlibrary.org/developers/api).
