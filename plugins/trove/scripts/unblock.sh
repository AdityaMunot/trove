#!/usr/bin/env bash
# Remove a blocked_by relationship.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ID=""
BLOCKER=""
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)
            if   [[ -z "$ID" ]];      then ID="$1"
            elif [[ -z "$BLOCKER" ]]; then BLOCKER="$1"
            else echo "unexpected: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

[[ -z "$ID" || -z "$BLOCKER" ]] && { echo "Usage: unblock <id> <blocker-id>" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"

[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }

if todo_blocked_by_remove "$path" "$BLOCKER"; then
    todo_update_field "$path" "updated" "$(todo_utc_now)"
    echo "#$ID no longer blocked by #$BLOCKER"
else
    echo "#$ID was not blocked by #$BLOCKER (no change)"
fi
