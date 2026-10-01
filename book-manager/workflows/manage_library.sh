#!/bin/bash
# Route library actions to their components; never touch the CSV here.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
action="${1:-list}"
if [ "$#" -gt 0 ]; then shift; fi
case "$action" in
    add)
        # Metadata and recommendations carry extra fields; persist only library data.
        require_commands jq
        jq -c '{id:(.id // ""),title,author,genre:(.genre // ""),year:(.year // null),
            subjects:(.subjects // []),link:(.link // ""),source:(.source // ""),
            status:(.status // "want_to_read"),rating:(.rating // null),owned:(.owned // false)}' \
            | "$BOOK_MANAGER_ROOT/data/book_database.sh" add ;;
    list|get|update|exists)
        "$BOOK_MANAGER_ROOT/data/book_database.sh" "$action" "$@" ;;
    search)
        "$BOOK_MANAGER_ROOT/books/search_books.sh" "$@" ;;
    lookup)
        "$BOOK_MANAGER_ROOT/books/fetch_book_metadata.sh" "$@" ;;
    *) die "Unknown library action: $action" ;;
esac
