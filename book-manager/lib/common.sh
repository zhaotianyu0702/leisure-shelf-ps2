#!/bin/bash
# Paths and a few shared checks; no UI or book storage logic.
BOOK_MANAGER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BOOK_MANAGER_ROOT
export BOOK_MANAGER_DATA_DIR="${BOOK_MANAGER_DATA_DIR:-$BOOK_MANAGER_ROOT/data}"
export BOOK_MANAGER_CACHE_DIR="${BOOK_MANAGER_CACHE_DIR:-$BOOK_MANAGER_ROOT/.cache}"
export BOOK_MANAGER_OFFLINE="${BOOK_MANAGER_OFFLINE:-0}"
if [ -z "${BOOK_MANAGER_INTERESTS:-}" ]; then
    BOOK_MANAGER_INTERESTS="$(cat "$BOOK_MANAGER_ROOT/config/interests.txt")"
fi
export BOOK_MANAGER_INTERESTS

die() { printf '%s\n' "$*" >&2; exit 1; }
require_commands() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || die "Missing dependency: $command_name"
    done
}
