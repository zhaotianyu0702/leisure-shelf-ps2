#!/bin/bash
# Library display, metadata match selection, and edits chosen by the reader.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$BOOK_MANAGER_ROOT/ui/helpers.sh"
require_commands gum jq
workflow="$BOOK_MANAGER_ROOT/workflows/manage_library.sh"
result_file="$(mktemp "${TMPDIR:-/tmp}/book-screen.XXXXXX")"
trap 'rm -f "$result_file"' EXIT

manual_book() {
    local author genre year
    author="$(gum input --value "$author_query" --placeholder 'Author (required)')" || return 1
    [ -n "$author" ] || { printf 'An author is required.\n' >&2; return 1; }
    genre="$(gum choose --header 'Shelf' 'Literary fiction' Mystery Fantasy 'Short stories' 'Travel & essays')" || return 1
    year="$(gum input --placeholder 'Publication year (optional)')" || return 1
    if [ -n "$year" ] && ! [[ "$year" =~ ^[0-9]{1,4}$ ]]; then
        printf 'Year must be a number.\n' >&2; return 1
    fi
    jq -nc --arg title "$title" --arg author "$author" --arg genre "$genre" --arg year "$year" \
        '{title:$title,author:$author,genre:$genre,year:(if $year=="" then null else ($year|tonumber) end),subjects:[],link:"",source:"manual"}'
}

add_book() {
    local title author_query book method status ownership genre
    screen_title 'Add a book'
    title="$(gum input --placeholder 'Book title')" || return 0
    [ -n "$title" ] || return 0
    author_query="$(gum input --placeholder 'Author (optional, helps find the right book)')" || return 0
    if ! gum spin --title 'Looking up book metadata…' --show-output -- \
        "$workflow" lookup "$title" "$author_query" >"$result_file"; then
        : >"$result_file"
    fi
    if [ -s "$result_file" ]; then
        method="$(gum choose --header 'Choose how to add this book' 'Select a metadata match' 'Enter details manually' Cancel)" || return 0
    else
        printf 'No matching metadata available. You can enter details manually.\n'
        method='Enter details manually'
    fi
    case "$method" in
        'Select a metadata match') book="$(choose_record "$result_file" 'Select the correct title and author')" || return 0 ;;
        'Enter details manually') book="$(manual_book)" || return 0 ;;
        *) return 0 ;;
    esac
    if [ -z "$(printf '%s\n' "$book" | jq -r '.genre // ""')" ]; then
        genre="$(gum choose --header 'Choose a shelf for this book' 'Literary fiction' Mystery Fantasy 'Short stories' 'Travel & essays')" || return 0
        book="$(printf '%s\n' "$book" | jq -c --arg genre "$genre" '.genre=$genre')"
    fi
    book_details "$book"
    status="$(choose_status)" || return 0
    ownership="$(gum choose --header 'Do you own this book?' 'Not owned' 'I own it')" || return 0
    book="$(printf '%s\n' "$book" | jq -c --arg status "$status" --arg ownership "$ownership" \
        '. + {status:$status,owned:($ownership=="I own it")}')"
    if printf '%s\n' "$book" | "$workflow" add >"$result_file"; then
        printf 'Saved to your library.\n'
    fi
    pause_screen
}

browse_books() {
    local book id action value
    "$workflow" "$@" >"$result_file"
    if [ ! -s "$result_file" ]; then
        printf 'No books found. Add a book to start your shelf.\n'
        pause_screen
        return 0
    fi
    book="$(choose_record "$result_file" 'Choose a book to view or update')" || return 0
    id="$(printf '%s\n' "$book" | jq -r '.id')"
    while true; do
        book_details "$book"
        action="$(gum choose --header 'Book details' 'Change reading status' 'Set rating' 'Change ownership' Back)" || break
        case "$action" in
            'Change reading status')
                value="$(choose_status)" || continue
                book="$("$workflow" update "$id" status "$value")" ;;
            'Set rating')
                value="$(gum choose --header 'Your rating · 1 low, 5 high' Unrated 1 2 3 4 5)" || continue
                [ "$value" != Unrated ] || value=null
                book="$("$workflow" update "$id" rating "$value")" ;;
            'Change ownership')
                value="$(gum choose 'Not owned' 'I own it')" || continue
                if [ "$value" = 'I own it' ]; then value=true; else value=false; fi
                book="$("$workflow" update "$id" owned "$value")" ;;
            Back) break ;;
        esac
    done
}

case "${1:-browse}" in
    add) add_book ;;
    browse) screen_title 'Your library'; browse_books list ;;
    search) screen_title 'Search results'; browse_books search "${2:-}" ;;
    *) die "Unknown library screen: $1" ;;
esac
