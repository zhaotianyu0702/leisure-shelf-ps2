#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_commands jq curl

CATALOG_FILE="$BOOK_MANAGER_ROOT/data/catalog.jsonl"
USER_AGENT="PS2 Leisure Book Manager/1.0 (Open Library catalog lookup)"
RATE_GATE=""

cleanup_rate_gate() {
    if [ -n "$RATE_GATE" ]; then
        rm -f "$RATE_GATE/owner"
        rmdir "$RATE_GATE" 2>/dev/null || true
        RATE_GATE=""
    fi
}

stop_on_signal() {
    cleanup_rate_gate
    trap - INT TERM
    exit 130
}

trap cleanup_rate_gate EXIT
trap stop_on_signal INT TERM

emit_local_matches() {
    local query="$1" author="${2:-}"
    jq -c --arg q "$query" --arg a "$author" '
      select(
        ((.title // "") | ascii_downcase | contains($q | ascii_downcase)) or
        ((.author // "") | ascii_downcase | contains($q | ascii_downcase)) or
        ((.subjects // [] | join(" ")) | ascii_downcase | contains($q | ascii_downcase))
      ) |
      select($a == "" or
        (((.author // "") | ascii_downcase | gsub("[ .]"; "")) |
         contains($a | ascii_downcase | gsub("[ .]"; ""))))
    ' "$CATALOG_FILE"
}

cache_path() {
    local query="$1" author="${2:-}" digest
    digest="$(printf '%s\n%s' "$query" "$author" | cksum | awk '{print $1}')"
    printf '%s/openlibrary-%s.jsonl\n' "$BOOK_MANAGER_CACHE_DIR" "$digest"
}

emit_cached() {
    local file="$1"
    [ -f "$file" ] || return 1
    jq -c 'select(type == "object" and (.id | strings) and (.title | strings))' "$file" 2>/dev/null
}

throttle_request() {
    local gate="$BOOK_MANAGER_CACHE_DIR/openlibrary-rate-gate" stamp="$BOOK_MANAGER_CACHE_DIR/openlibrary-last-request" now last owner deadline
    mkdir -p "$BOOK_MANAGER_CACHE_DIR"
    deadline="$(($(date +%s) + 5))"
    while :; do
        if mkdir "$gate" 2>/dev/null; then
            RATE_GATE="$gate"
            printf '%s\n' "$$" > "$gate/owner"
            break
        fi
        owner=""
        [ ! -f "$gate/owner" ] || owner="$(cat "$gate/owner" 2>/dev/null || true)"
        case "$owner" in
            ''|*[!0-9]*) ;;
            *)
                if ! kill -0 "$owner" 2>/dev/null; then
                    rm -f "$gate/owner"
                    rmdir "$gate" 2>/dev/null || true
                    continue
                fi
                ;;
        esac
        now="$(date +%s)"
        if [ "$now" -ge "$deadline" ]; then
            # Recover the tiny mkdir-before-owner-file interruption window.
            if [ ! -f "$gate/owner" ] && rmdir "$gate" 2>/dev/null; then continue; fi
            die "Timed out waiting for Open Library rate gate"
        fi
        sleep 0.1
    done
    if [ -f "$stamp" ]; then
        last="$(cat "$stamp" 2>/dev/null || printf '0')"
        now="$(date +%s)"
        if [ "$last" -ge "$now" ]; then sleep "$((last + 1 - now))"; fi
    fi
    date +%s > "$stamp"
    cleanup_rate_gate
}

live_search() {
    local query="$1" author="${2:-}" output="$3" api_query tmp collected
    api_query="title:\"${query//\"/\\\"}\""
    if [ -n "$author" ]; then
        api_query="$api_query AND author:\"${author//\"/\\\"}\""
    fi
    throttle_request
    # Another process may have filled this exact cache entry while we waited.
    if [ -f "$output" ]; then return 0; fi
    tmp="$(mktemp "$BOOK_MANAGER_CACHE_DIR/openlibrary.XXXXXX")"
    collected="$(date +%Y-%m-%d)"
    if curl -fsS --connect-timeout 4 --max-time 12 --retry 0 -A "$USER_AGENT" \
        --get 'https://openlibrary.org/search.json' \
        --data-urlencode "q=$api_query" \
        --data-urlencode 'fields=key,title,author_name,first_publish_year,subject,edition_count' \
        --data-urlencode 'limit=10' |
        jq -c --arg collected "$collected" '
          (.docs // [])[] |
          select((.key // "") | test("^/works/OL[0-9]+W$")) |
          {id:.key,title:(.title // ""),author:((.author_name // []) | join("; ")),genre:"",
           year:(.first_publish_year // null),subjects:((.subject // [])[:12]),
           link:("https://openlibrary.org" + .key),source:"Open Library Search API",
           edition_count:(.edition_count // null),collected_at:$collected}
        ' > "$tmp" 2>/dev/null; then
        # A broad query can recover localized titles that are not indexed under
        # the caller's exact title spelling (including Chinese queries).
        if [ ! -s "$tmp" ]; then
            local broad_query="$query"
            [ -z "$author" ] || broad_query="$broad_query $author"
            throttle_request
            if ! curl -fsS --connect-timeout 4 --max-time 12 --retry 0 -A "$USER_AGENT" \
                --get 'https://openlibrary.org/search.json' \
                --data-urlencode "q=$broad_query" \
                --data-urlencode 'fields=key,title,author_name,first_publish_year,subject,edition_count' \
                --data-urlencode 'limit=10' |
                jq -c --arg collected "$collected" '
                  (.docs // [])[] |
                  select((.key // "") | test("^/works/OL[0-9]+W$")) |
                  {id:.key,title:(.title // ""),author:((.author_name // []) | join("; ")),genre:"",
                   year:(.first_publish_year // null),subjects:((.subject // [])[:12]),
                   link:("https://openlibrary.org" + .key),source:"Open Library Search API",
                   edition_count:(.edition_count // null),collected_at:$collected}
                ' > "$tmp" 2>/dev/null; then
                rm -f "$tmp"
                return 1
            fi
        fi
        mv "$tmp" "$output"
    else
        rm -f "$tmp"
        return 1
    fi
}

usage() {
    die "Usage: catalog.sh list | search QUERY [AUTHOR]"
}

[ "$#" -ge 1 ] || usage
case "$1" in
    list)
        [ "$#" -eq 1 ] || usage
        cat "$CATALOG_FILE"
        ;;
    search)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
        query="$2"
        author="${3:-}"
        [ -n "$query" ] || die "Search query must not be empty"
        cache_file="$(cache_path "$query" "$author")"
        mkdir -p "$BOOK_MANAGER_CACHE_DIR"

        if [ "$BOOK_MANAGER_OFFLINE" = 1 ]; then
            if [ -s "$cache_file" ]; then
                printf '%s\n' "catalog: offline mode; using cached Open Library results" >&2
                emit_cached "$cache_file"
            else
                printf '%s\n' "catalog: offline mode; using bundled catalog matches" >&2
                emit_local_matches "$query" "$author"
            fi
            exit 0
        fi

        if [ -s "$cache_file" ]; then
            printf '%s\n' "catalog: using cached Open Library results" >&2
            emit_cached "$cache_file"
            exit 0
        fi
        if live_search "$query" "$author" "$cache_file"; then
            if [ -s "$cache_file" ]; then
                emit_cached "$cache_file"
            else
                printf '%s\n' "catalog: no online candidates; using bundled catalog matches" >&2
                emit_local_matches "$query" "$author"
            fi
        elif [ -s "$cache_file" ]; then
            printf '%s\n' "catalog: lookup failed; using cached Open Library results" >&2
            emit_cached "$cache_file"
        else
            printf '%s\n' "catalog: lookup failed; using bundled catalog matches" >&2
            emit_local_matches "$query" "$author"
        fi
        ;;
    *) usage ;;
esac
