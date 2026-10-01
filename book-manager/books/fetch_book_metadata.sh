#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "Usage: fetch_book_metadata.sh TITLE [AUTHOR]"
[ -n "$1" ] || die "Title must not be empty"
exec "$SCRIPT_DIR/catalog.sh" search "$1" "${2:-}"
