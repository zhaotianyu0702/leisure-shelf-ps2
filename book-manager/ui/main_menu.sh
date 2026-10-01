#!/bin/bash
# Interaction only: choose a screen, then return to the main menu.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$BOOK_MANAGER_ROOT/ui/helpers.sh"
require_commands gum jq
while true; do
    screen_title 'Leisure Shelf · Personal Book Manager'
    if [ "${BOOK_MANAGER_DEMO:-0}" = 1 ]; then
        printf 'DEMO · example library, discarded when you quit\n'
    fi
    action="$(gum choose --header 'Choose your next chapter' \
        'Browse Library' 'Add Book' 'Search Library' 'Get Recommendations' 'Quit')" || break
    case "$action" in
        'Browse Library') "$BOOK_MANAGER_ROOT/ui/library_screen.sh" browse || true ;;
        'Add Book') "$BOOK_MANAGER_ROOT/ui/library_screen.sh" add || true ;;
        'Search Library')
            query="$(gum input --placeholder 'Title, author, genre, or status')" || continue
            [ -n "$query" ] && "$BOOK_MANAGER_ROOT/ui/library_screen.sh" search "$query" || true ;;
        'Get Recommendations') "$BOOK_MANAGER_ROOT/ui/recommendations_screen.sh" || true ;;
        Quit) break ;;
    esac
done
printf 'See you next chapter.\n'
