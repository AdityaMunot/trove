#!/usr/bin/env bash
# Set or clear a task's due date. Accepts ISO 8601 (YYYY-MM-DD or full timestamp) or "clear".

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ID=""
VALUE=""
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$ID" ]]; then ID="$1"
            elif [[ -z "$VALUE" ]]; then VALUE="$1"
            else echo "unexpected: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

[[ -z "$ID" || -z "$VALUE" ]] && { echo "Usage: todo due <id> <YYYY-MM-DD|clear>" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"
[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }

if [[ "$VALUE" == "clear" ]]; then
    new_due=""
else
    # Light validation: ISO-8601-ish. Accepts YYYY-MM-DD with optional time/zone tail.
    if [[ ! "$VALUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([T\ ][0-9:.+Z-]+)?$ ]]; then
        echo "invalid date: '$VALUE' (expected YYYY-MM-DD or ISO 8601, or 'clear')" >&2
        exit 2
    fi
    new_due="$VALUE"
fi

todo_ensure_field "$path" "due" "$new_due"
todo_update_field "$path" "updated" "$(todo_utc_now)"

title="$(todo_get_title "$path")"
if [[ -z "$new_due" ]]; then
    echo "#$ID due cleared: $title"
else
    echo "#$ID due -> $new_due: $title"
fi
