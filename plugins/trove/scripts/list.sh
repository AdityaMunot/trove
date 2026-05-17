#!/usr/bin/env bash
# List tasks. Filters: status, priority, tag, --ready / --blocked, --due-before / --due-after.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STATUS="open"
PRIORITY=""
TAG=""
LIMIT=0
READY=0
BLOCKED=0
DUE_BEFORE=""
DUE_AFTER=""
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--status) STATUS="$2"; shift 2 ;;
        -p|--priority) PRIORITY="$2"; shift 2 ;;
        -t|--tag) TAG="$2"; shift 2 ;;
        -n|--limit) LIMIT="$2"; shift 2 ;;
        --ready)   READY=1; shift ;;
        --blocked) BLOCKED=1; shift ;;
        --due-before) DUE_BEFORE="$2"; shift 2 ;;
        --due-after)  DUE_AFTER="$2";  shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

case "$STATUS" in
    open|done|all) ;;
    *) echo "invalid status: $STATUS (must be open/done/all)" >&2; exit 2 ;;
esac
if [[ "$READY" -eq 1 && "$BLOCKED" -eq 1 ]]; then
    echo "--ready and --blocked are mutually exclusive" >&2; exit 2
fi

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"

if [[ ! -d "$DIR_RESOLVED" ]]; then
    echo "(none)"
    exit 0
fi

shopt -s nullglob
files=("$DIR_RESOLVED"/*.md)
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
    echo "(none)"
    exit 0
fi

mapfile -t sorted < <(printf '%s\n' "${files[@]}" | awk -F/ '{print $NF}' | sort -t. -k1n)

shown=0
matched=0
for f in "${sorted[@]}"; do
    path="$DIR_RESOLVED/$f"
    id="${f%.md}"
    [[ "$id" =~ ^[0-9]+$ ]] || continue

    s="$(todo_get_field "$path" "status")"
    [[ -z "$s" ]] && s="open"
    [[ "$STATUS" != "all" && "$s" != "$STATUS" ]] && continue

    p="$(todo_get_field "$path" "priority")"
    [[ -z "$p" ]] && p="med"
    [[ -n "$PRIORITY" && "$p" != "$PRIORITY" ]] && continue

    tags_raw="$(todo_get_field "$path" "tags")"
    mapfile -t tags < <(todo_parse_list "$tags_raw")

    if [[ -n "$TAG" ]]; then
        found=0
        for t in "${tags[@]:-}"; do
            [[ "$t" == "$TAG" ]] && { found=1; break; }
        done
        [[ "$found" -eq 0 ]] && continue
    fi

    # Due date filters. ISO 8601 (YYYY-MM-DD...) is lexicographically ordered.
    # Tasks without a due date never match --due-before / --due-after.
    if [[ -n "$DUE_BEFORE" || -n "$DUE_AFTER" ]]; then
        due="$(todo_get_field "$path" "due")"
        [[ -z "$due" ]] && continue
        [[ -n "$DUE_BEFORE" && ! "$due" < "$DUE_BEFORE" ]] && continue
        [[ -n "$DUE_AFTER"  && ! "$due" > "$DUE_AFTER"  ]] && continue
    fi

    # Compute open blockers (only meaningful for non-done tasks).
    open_blockers=""
    if [[ "$s" != "done" ]]; then
        open_blockers="$(todo_open_blockers "$path" "$DIR_RESOLVED")"
    fi

    # Apply --ready / --blocked filters.
    if [[ "$READY" -eq 1 ]]; then
        # Ready = open + no open blockers.
        [[ "$s" == "done" || -n "$open_blockers" ]] && continue
    fi
    if [[ "$BLOCKED" -eq 1 ]]; then
        [[ "$s" == "done" || -z "$open_blockers" ]] && continue
    fi

    title="$(todo_get_title "$path")"

    todo_format_line "$id" "$s" "$p" "$title" "$open_blockers" "${tags[@]:-}"
    matched=$((matched + 1))
    shown=$((shown + 1))

    [[ "$LIMIT" -gt 0 && "$shown" -ge "$LIMIT" ]] && break
done

if (( matched == 0 )); then
    echo "(none)"
fi
