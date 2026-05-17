#!/usr/bin/env bash
# Create a new task. Returns the new id.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

TITLE_PARTS=()
PRIORITY="med"
DUE=""
TAGS=()
BLOCKED_BY=()
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--priority) PRIORITY="$2"; shift 2 ;;
        -d|--due)      DUE="$2"; shift 2 ;;
        -t|--tags)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                TAGS+=("$1")
                shift
            done
            ;;
        -b|--blocked-by)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                BLOCKED_BY+=("$1")
                shift
            done
            ;;
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        --) shift; TITLE_PARTS+=("$@"); break ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *) TITLE_PARTS+=("$1"); shift ;;
    esac
done

TITLE="${TITLE_PARTS[*]:-}"
TITLE="${TITLE# }"
TITLE="${TITLE% }"

[[ -z "$TITLE" ]] && { echo "title is required" >&2; exit 2; }

case "$PRIORITY" in
    high|med|low) ;;
    *) echo "invalid priority: $PRIORITY (must be high/med/low)" >&2; exit 2 ;;
esac

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
mkdir -p "$DIR_RESOLVED"

# Validate blockers exist.
for bid in "${BLOCKED_BY[@]:-}"; do
    [[ -z "$bid" ]] && continue
    [[ "$bid" =~ ^[0-9]+$ ]] || { echo "invalid blocker id: $bid" >&2; exit 2; }
    [[ -f "$DIR_RESOLVED/$bid.md" ]] || { echo "blocker #$bid does not exist" >&2; exit 1; }
done

NEW_ID="$(todo_next_id "$DIR_RESOLVED")"
NOW="$(todo_utc_now)"
BLOCKED_CSV="${BLOCKED_BY[*]:-}"

todo_create_file "$DIR_RESOLVED/$NEW_ID.md" "$NEW_ID" "$TITLE" "open" "$PRIORITY" "$DUE" "$NOW" "$NOW" "$BLOCKED_CSV" "${TAGS[@]:-}"

note=""
if [[ -n "$BLOCKED_CSV" ]]; then
    acc=""
    for b in $BLOCKED_CSV; do acc+=" #$b"; done
    acc="${acc# }"
    note=" (blocked by $acc)"
fi
echo "#$NEW_ID added: $TITLE$note"
