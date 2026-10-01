#!/bin/bash
# Small Gum display/selection helpers shared by both screens.

screen_title() {
    if [ -t 1 ]; then printf '\033[2J\033[H'; fi
    gum style --foreground 183 --border rounded --padding '0 2' "$1"
}

pause_screen() { gum input --placeholder 'Press Enter to continue' >/dev/null || true; }

# JSONL file -> JSON record on stdout. Gum's interface renders on the terminal.
choose_record() {
    local choice index
    choice="$(jq -sr 'to_entries[] | "\(.key + 1). \(.value.title) — \(.value.author)" | gsub("[\\r\\n\\t]"; " ")' "$1" \
        | gum choose --height 10 --header "$2")" || return 1
    index="${choice%%.*}"
    jq -sc --argjson index "$((index - 1))" '.[$index]' "$1"
}

choose_status() {
    local choice
    choice="$(gum choose --header 'Reading status' 'Want to read' 'Reading' 'Finished')" || return 1
    case "$choice" in
        'Want to read') printf 'want_to_read\n' ;;
        Reading) printf 'reading\n' ;;
        Finished) printf 'finished\n' ;;
    esac
}

book_details() {
    if [ -t 1 ]; then printf '\033[2J\033[H'; fi
    printf '%s\n' "$1" | jq -r '
        "\(.title)\nby \(.author)\n\n" +
        "Genre: \(.genre // "Unknown")   Catalog year: \(.year // "Unknown")\n" +
        "Status: \(.status // "not saved")   Rating: \(.rating // "unrated")\n" +
        "Owned: \(if .owned then "yes" else "no" end)\n" +
        (if .reason then "\nWhy: \(.reason)\n" else "" end) +
        (if (.link // "") != "" then "\n\(.link)" else "" end)
    ' | gum style --width 74 --border rounded --padding '1 2' --border-foreground 245
}
