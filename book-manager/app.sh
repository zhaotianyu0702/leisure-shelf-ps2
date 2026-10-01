#!/bin/bash
# Entry point: runtime checks, optional isolated demo, then the main UI.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_commands gum jq curl python3
case "${1:-}" in
    --demo)
        BOOK_MANAGER_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/book-demo.XXXXXX")"
        export BOOK_MANAGER_DATA_DIR
        export BOOK_MANAGER_CACHE_DIR="$BOOK_MANAGER_DATA_DIR/cache"
        export BOOK_MANAGER_OFFLINE=1 BOOK_MANAGER_DEMO=1
        trap 'rm -rf "$BOOK_MANAGER_DATA_DIR"' EXIT
        "$BOOK_MANAGER_ROOT/data/book_database.sh" init
        while IFS= read -r book; do
            printf '%s\n' "$book" | "$BOOK_MANAGER_ROOT/workflows/manage_library.sh" add >/dev/null
        done <"$BOOK_MANAGER_ROOT/examples/demo_library.jsonl" ;;
    --help)
        printf 'Usage: ./app.sh [--demo]\n--demo: offline example library; discarded on exit.\n'
        exit 0 ;;
    '') "$BOOK_MANAGER_ROOT/data/book_database.sh" init ;;
    *) die "Usage: ./app.sh [--demo]" ;;
esac
"$BOOK_MANAGER_ROOT/ui/main_menu.sh"
