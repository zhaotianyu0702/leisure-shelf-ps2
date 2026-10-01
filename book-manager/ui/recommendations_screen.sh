#!/bin/bash
# Show real workflow progress, recommendation reasons, and a save action.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$BOOK_MANAGER_ROOT/ui/helpers.sh"
require_commands gum jq
result_file="$(mktemp "${TMPDIR:-/tmp}/book-shortlist.XXXXXX")"
trap 'rm -f "$result_file"' EXIT
screen_title 'Find your next leisure read'
interests="$(gum input --value "$BOOK_MANAGER_INTERESTS" --width 70 \
    --placeholder 'Comma-separated interests, e.g. mystery,short stories')" || exit 0
[ -n "$interests" ] || interests="$BOOK_MANAGER_INTERESTS"
if ! "$BOOK_MANAGER_ROOT/workflows/get_recommendations.sh" "$interests" >"$result_file"; then
    printf 'Recommendations are unavailable right now.\n' >&2
    pause_screen
    exit 0
fi
if [ ! -s "$result_file" ]; then
    printf 'No new matches. Try a broader interest or a different genre.\n'
    pause_screen
    exit 0
fi
while true; do
    book="$(choose_record "$result_file" 'Your shortlist · choose a book to see why')" || break
    book_details "$book"
    action="$(gum choose 'Save to want-to-read' 'Choose another book' Back)" || break
    case "$action" in
        'Save to want-to-read')
            if printf '%s\n' "$book" | "$BOOK_MANAGER_ROOT/workflows/manage_library.sh" add >/dev/null; then
                printf 'Saved to your want-to-read shelf.\n'
                id="$(printf '%s\n' "$book" | jq -r '.id')"
                remaining="$(jq -c --arg id "$id" 'select(.id != $id)' "$result_file")"
                printf '%s' "$remaining" >"$result_file"
                [ -s "$result_file" ] || break
            fi ;;
        Back) break ;;
    esac
done
