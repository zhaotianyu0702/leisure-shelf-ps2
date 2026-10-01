#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands jq

interests="${1:-$BOOK_MANAGER_INTERESTS}"
library="$BOOK_MANAGER_ROOT/data/book_database.sh"
catalog="$BOOK_MANAGER_ROOT/books/catalog.sh"
[ -x "$library" ] || die "Missing library API: $library"
[ -x "$catalog" ] || die "Missing catalog API: $catalog"

library_json="$("$library" list | jq -s -c '.')"
"$catalog" list | jq -c --arg interests "$interests" --argjson library "$library_json" '
  def norm: (tostring | ascii_downcase | gsub("[^\\p{L}\\p{N}]"; ""));
  def mapped_genres($term):
    if ($term|test("short stor|shortstor")) then ["Short stories"]
    elif ($term|test("novel|fiction")) then ["Literary fiction"]
    elif ($term|test("mystery|detective")) then ["Mystery"]
    elif ($term|test("fantasy|magic")) then ["Fantasy"]
    elif ($term|test("travel|essay")) then ["Travel & essays"]
    else [] end;
  ($interests | split(",") | map(norm) | map(select(length > 0)) | unique) as $terms
  | ([$terms[] | mapped_genres(.)[]] | unique) as $interest_genres
  | ([ $library[]? | select((.status // "") == "finished" or (.status // "") == "reading" or (.status // "") == "want_to_read") | .genre // empty ] | unique) as $library_genres
  | . as $book
  | select(($book.id|type)=="string" and ($book.title|type)=="string" and ($book.author|type)=="string")
  | select(($book.genre // "") != "" and ($book.link // "") != "")
  | select(([$interest_genres[], $library_genres[]] | index($book.genre)) == null)
  | select(any($library[]?; .id == $book.id or ((.title|norm) == ($book.title|norm) and (.author|norm) == ($book.author|norm))) | not)
  | $book + {strategy:"discovery", score:7.5,
      reason:("Explore another leisure literature genre: \($book.genre) is outside your interests and saved genres")}
'
