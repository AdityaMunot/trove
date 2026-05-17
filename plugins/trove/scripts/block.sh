#!/usr/bin/env bash
# Add a blocked_by relationship. Refuses if it would create a cycle.

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

[[ -z "$ID" || -z "$BLOCKER" ]] && { echo "Usage: block <id> <blocker-id>" >&2; exit 2; }
[[ "$ID" =~ ^[0-9]+$ ]] || { echo "invalid id: $ID" >&2; exit 2; }
[[ "$BLOCKER" =~ ^[0-9]+$ ]] || { echo "invalid blocker id: $BLOCKER" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"
bpath="$DIR_RESOLVED/$BLOCKER.md"

[[ ! -f "$path" ]]  && { echo "no task with id $ID" >&2; exit 1; }
[[ ! -f "$bpath" ]] && { echo "no task with id $BLOCKER (intended blocker)" >&2; exit 1; }

if todo_cycle_check "$ID" "$BLOCKER" "$DIR_RESOLVED"; then
    echo "refusing: would create a dependency cycle (#$BLOCKER already depends on #$ID, directly or transitively)" >&2
    exit 1
fi

if todo_blocked_by_add "$path" "$BLOCKER"; then
    todo_update_field "$path" "updated" "$(todo_utc_now)"
    echo "#$ID now blocked by #$BLOCKER"
else
    echo "#$ID already blocked by #$BLOCKER"
fi
