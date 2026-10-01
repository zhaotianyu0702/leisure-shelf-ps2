#!/bin/bash
# Three independent background programs, synchronization, then a real pipe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
interests="${1:-$BOOK_MANAGER_INTERESTS}"
limit="${2:-5}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/book-recommendations.XXXXXX")"
pids=()
cleanup() {
    local pid
    for pid in "${pids[@]:-}"; do
        [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
    done
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$BOOK_MANAGER_ROOT/recommendations/recommend_from_history.sh" \
    >"$work_dir/history.jsonl" 2>"$work_dir/history.err" &
history_pid=$!
pids+=("$history_pid")
"$BOOK_MANAGER_ROOT/recommendations/recommend_from_interests.sh" "$interests" \
    >"$work_dir/interests.jsonl" 2>"$work_dir/interests.err" &
interests_pid=$!
pids+=("$interests_pid")
"$BOOK_MANAGER_ROOT/recommendations/recommend_for_discovery.sh" "$interests" \
    >"$work_dir/discovery.jsonl" 2>"$work_dir/discovery.err" &
discovery_pid=$!
pids+=("$discovery_pid")
printf 'Recommendations: history, interests, discovery running in parallel.\n' >&2

process_state() {
    if kill -0 "$1" 2>/dev/null; then printf 'running'; else printf 'done'; fi
}
started=$SECONDS
while kill -0 "$history_pid" 2>/dev/null || kill -0 "$interests_pid" 2>/dev/null \
    || kill -0 "$discovery_pid" 2>/dev/null; do
    if [ -t 2 ]; then
        printf '\r  history: %-7s | interests: %-7s | discovery: %-7s | %ss ' \
            "$(process_state "$history_pid")" "$(process_state "$interests_pid")" \
            "$(process_state "$discovery_pid")" "$((SECONDS - started))" >&2
    fi
    sleep 0.15
done
if [ -t 2 ]; then printf '\n' >&2; fi

successes=0
for index in 0 1 2; do
    case "$index" in 0) name=history ;; 1) name=interests ;; 2) name=discovery ;; esac
    if wait "${pids[$index]}"; then
        successes=$((successes + 1))
        printf '  %s: done\n' "$name" >&2
    else
        printf '  %s: failed; using other available results\n' "$name" >&2
        # Never accept half-written output from a failed agent.
        : >"$work_dir/$name.jsonl"
    fi
    cat "$work_dir/$name.err" >&2
done
pids=()
[ "$successes" -gt 0 ] || die "All recommendation strategies failed."
cat "$work_dir/history.jsonl" "$work_dir/interests.jsonl" "$work_dir/discovery.jsonl" \
    | "$BOOK_MANAGER_ROOT/recommendations/refine_recommendations.sh" "$limit"
