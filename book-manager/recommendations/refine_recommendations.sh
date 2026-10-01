#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands jq mktemp

limit="${1:-5}"
[[ "$limit" =~ ^[0-9]+$ ]] || die "Limit must be a non-negative integer"
library="$BOOK_MANAGER_ROOT/data/book_database.sh"
[ -x "$library" ] || die "Missing library API: $library"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/book-recommendations.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
valid="$tmp/valid.jsonl"
: > "$valid"
line_no=0
skipped=0
while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if printf '%s\n' "$line" | jq -e '
      type == "object"
      and (.id|type)=="string" and (.id|length)>0
      and (.title|type)=="string" and (.title|length)>0
      and (.author|type)=="string"
      and (.genre|type)=="string" and (.genre|length)>0
      and (.link|type)=="string" and (.link|length)>0
      and (.source|type)=="string" and (.source|length)>0
      and (.score|type)=="number" and .score >= 0 and .score <= 10
      and (.reason|type)=="string" and (.reason|length)>0
      and (.strategy == "history" or .strategy == "interests" or .strategy == "discovery")
      and ((.subjects // [])|type)=="array"
      and all((.subjects // [])[]; type=="string")
      and ((.strategies // [])|type)=="array"
      and all((.strategies // [])[]; . == "history" or . == "interests" or . == "discovery")
    ' >/dev/null 2>&1; then
        printf '%s\n' "$line" >> "$valid"
    else
        skipped=$((skipped + 1))
        printf 'refine: skipped invalid candidate on input line %s\n' "$line_no" >&2
    fi
done
if [ "$skipped" -gt 0 ]; then
    printf 'refine: skipped %s invalid candidate(s)\n' "$skipped" >&2
fi

existing="$("$library" list | jq -s -c '.')"
if [ ! -s "$valid" ] || [ "$limit" -eq 0 ]; then
    exit 0
fi

# Keep one discovery slot when discovery candidates exist. Fill all remaining
# positions from history/interests first, then use unselected discovery books
# only if the familiar strategies did not supply enough candidates.
jq -s -c --argjson existing "$existing" --argjson limit "$limit" '
  def norm: (tostring | ascii_downcase | gsub("[^\\p{L}\\p{N}]"; ""));
  def same_work($a; $b): ($a.id == $b.id) or (($a.title|norm) == ($b.title|norm) and ($a.author|norm) == ($b.author|norm));
  def strategies($x): ([$x.strategy] + ($x.strategies // [])) | map(select(. == "history" or . == "interests" or . == "discovery")) | unique;
  def merge_candidate($old; $new):
    (strategies($old) + strategies($new) | unique) as $strategies
    | ([$old.reason, $new.reason] | map(select(type=="string" and length>0)) | unique | join("；")) as $reason
    | ([$old.score, $new.score] | max) as $best_score
    | (if $new.score > $old.score then $new else $old end) as $best_record
    | $best_record + {strategy:$best_record.strategy, strategies:$strategies,
        score:([$best_score + ((($strategies|length)-1)*0.35),10]|min), reason:$reason};
  [ .[] | . + {strategies:strategies(.)} ]
  | reduce .[] as $candidate
      ([];
       ([range(0;length) as $i | select(same_work(.[ $i ]; $candidate)) | $i][0]) as $index
       | if $index == null then . + [$candidate]
         else .[$index] = merge_candidate(.[ $index ]; $candidate)
         end)
  | map(select((.id as $id | any($existing[]?; .id == $id)) | not)
      | select((.title|norm) as $title | (.author|norm) as $author | any($existing[]?; (.title|norm)==$title and (.author|norm)==$author) | not))
  | . as $candidates
  | def pick($remaining; $picked; $left):
      if $left <= 0 or ($remaining|length)==0 then $picked
      else
        ($remaining | map(. as $item
          | . + {_rank:($item.score
              + (if ($picked | map(.genre) | index($item.genre)) == null then 0.8 else 0 end))})
          | sort_by([ -._rank, (.title|ascii_downcase), (.author|ascii_downcase) ]) | .[0] | del(._rank)) as $next
        | pick([$remaining[] | select((same_work(.; $next)) | not)]; $picked + [$next]; $left - 1)
      end;
  def without_picked($source; $picked):
    [ $source[] as $candidate
      | select(all($picked[]; (same_work(.; $candidate)) | not))
      | $candidate ];
  ([ $candidates[] | select((strategies(.) | index("discovery")) != null) ]) as $discovery
  | ([ $candidates[] | select((strategies(.) | index("history")) != null or (strategies(.) | index("interests")) != null) ]) as $familiar
  | pick($discovery; []; (if ($discovery|length)>0 then 1 else 0 end)) as $exploration
  | pick(without_picked($familiar; $exploration); $exploration; $limit - ($exploration|length)) as $familiar_first
  | pick(without_picked($discovery; $familiar_first); $familiar_first; $limit - ($familiar_first|length))[]
' "$valid"
