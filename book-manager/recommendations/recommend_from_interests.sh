#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands jq

interests="${1:-$BOOK_MANAGER_INTERESTS}"
catalog="$BOOK_MANAGER_ROOT/books/catalog.sh"
[ -x "$catalog" ] || die "Missing catalog API: $catalog"

"$catalog" list | jq -c --arg interests "$interests" '
  def norm: (tostring | ascii_downcase | gsub("[^\\p{L}\\p{N}]"; ""));
  def mapped_genres($term):
    if ($term|test("short stor|shortstor")) then ["Short stories"]
    elif ($term|test("novel|fiction")) then ["Literary fiction"]
    elif ($term|test("mystery|detective")) then ["Mystery"]
    elif ($term|test("fantasy|magic")) then ["Fantasy"]
    elif ($term|test("travel|essay")) then ["Travel & essays"]
    else [] end;
  ($interests | split(",") | map(norm) | map(select(length > 0)) | unique) as $terms
  | . as $book
  | select(($book.id|type)=="string" and ($book.title|type)=="string" and ($book.author|type)=="string")
  | select(($book.genre // "") != "" and ($book.link // "") != "")
  | [ $terms[] as $term
      | {term:$term, genre_hit:(mapped_genres($term) | index($book.genre) != null),
         text_hit:((([$book.title,$book.author,$book.genre] + ($book.subjects // [])) | map(norm) | join(" ") | contains($term)))}
    ] as $hits
  | [$hits[] | select(.genre_hit or .text_hit)] as $matched
  | select(($matched|length)>0)
  | ([ $matched[] | (if .genre_hit then 4.2 else 0 end) + (if .text_hit then 2.3 else 0 end) ] | add) as $raw
  | ([ $matched[] | if .genre_hit then "\($book.genre) matches your interest in \(.term)" else "book details match your interest in \(.term)" end ] | unique | join("; ")) as $why
  | $book + {strategy:"interests", score: ([$raw,10]|min), reason:$why}
'
