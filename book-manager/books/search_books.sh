#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
if [ "$#" -gt 1 ]; then
    die "Usage: search_books.sh TERM (or provide TERM on stdin)"
fi
if [ "$#" -eq 1 ]; then
    term="$1"
else
    IFS= read -r term || [ -n "${term:-}" ] || die "A search term is required"
fi
[ -n "${term//[[:space:]]/}" ] || die "A search term is required"
exec "$BOOK_MANAGER_ROOT/data/book_database.sh" search "$term"
