#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands jq

library="$BOOK_MANAGER_ROOT/data/book_database.sh"
catalog="$BOOK_MANAGER_ROOT/books/catalog.sh"
[ -x "$library" ] || die "Missing library API: $library"
[ -x "$catalog" ] || die "Missing catalog API: $catalog"

# Empty history means no evidence to personalize from, so this strategy emits
# no candidates rather than inventing a reading profile.
library_json="$("$library" list | jq -s -c '.')"
[ "$library_json" != "[]" ] || exit 0
"$catalog" list | jq -c --argjson library "$library_json" '
  def norm: (tostring | ascii_downcase | gsub("[^\\p{L}\\p{N}]"; ""));
  def in_library($b): any($library[]?; .id == $b.id or ((.title|norm) == ($b.title|norm) and (.author|norm) == ($b.author|norm)));
  def overlap($a; $b): [($a // [])[] | ascii_downcase] as $left
    | [($b // [])[] | ascii_downcase] as $right
    | [$left[] as $x | select(any($right[]; . == $x)) | $x] | unique | length;
  [ $library[] | select((.rating == null or .rating > 2)
      and (.status == "finished" or .status == "want_to_read" or .status == "reading")) ] as $evidence
  | select(($evidence|length) > 0)
  | . as $book
  | select(($book.id|type)=="string" and ($book.title|type)=="string" and ($book.author|type)=="string")
  | select(($book.genre // "") != "" and ($book.link // "") != "")
  | select(in_library($book) | not)
  | [ $evidence[] as $e
      | (if ($e.author|norm) == ($book.author|norm) and ($book.author|norm) != "" then 2 else 0 end)
        + (if ($e.genre // "") == ($book.genre // "") then (if ($e.rating // 0) >= 4 or ($e.status // "") == "finished" then 2.5 else 1.2 end) else 0 end)
        + (overlap($e.subjects; $book.subjects) * (if ($e.rating // 0) >= 4 then 1.1 else 0.45 end))
    ] as $signals
  | ($signals | add // 0) as $raw
  | select($raw > 0)
  | [if any($evidence[]; (.author|norm) == ($book.author|norm) and ($book.author|norm) != "") then "same author as saved books" else empty end,
     if any($evidence[]; .genre == $book.genre and ($book.genre // "") != "") then "same genre as saved books" else empty end,
     if any($evidence[]; overlap(.subjects; $book.subjects) > 0) then "similar subjects to saved books" else empty end] as $why
  | $book + {strategy:"history", score: ([$raw,10]|min), reason: ($why|unique|join("; "))}
'
