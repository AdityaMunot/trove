#!/usr/bin/env bash
# Mark a task complete. Reports any tasks that became newly unblocked.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ID=""
DIR=""
USE_GLOBAL=0
COMMIT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) COMMIT="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$ID" ]]; then ID="$1"; else echo "unexpected: $1" >&2; exit 2; fi
            shift
            ;;
    esac
done

[[ -z "$ID" ]] && { echo "id is required" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"

[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }

todo_update_field "$path" "status" "done"
todo_update_field "$path" "updated" "$(todo_utc_now)"
if [[ -n "$COMMIT" ]]; then
    # Ensure the field exists (older files may lack it); append if missing.
    if grep -q '^closed_by_commit:' "$path"; then
        todo_update_field "$path" "closed_by_commit" "$COMMIT"
    else
        # Insert closed_by_commit line right before "created:" for stable ordering.
        if [[ "$(uname -s)" == "Darwin" ]]; then
            sed -i '' "/^created:/i\\
closed_by_commit: $COMMIT
" "$path"
        else
            sed -i "/^created:/i closed_by_commit: $COMMIT" "$path"
        fi
    fi
fi

title="$(todo_get_title "$path")"
echo "#$ID done: $title"

# Report tasks that became newly ready: status open, were blocked by this id,
# and now have no remaining open blockers.
unblocked=()
while IFS= read -r dep_id; do
    [[ -z "$dep_id" ]] && continue
    dep_path="$DIR_RESOLVED/$dep_id.md"
    [[ -f "$dep_path" ]] || continue
    dep_status="$(todo_get_field "$dep_path" "status")"
    [[ "$dep_status" == "done" ]] && continue
    rem="$(todo_open_blockers "$dep_path" "$DIR_RESOLVED")"
    if [[ -z "$rem" ]]; then
        unblocked+=("$dep_id")
    fi
done < <(todo_blocks_of "$ID" "$DIR_RESOLVED")

if (( ${#unblocked[@]} > 0 )); then
    parts=""
    for u in "${unblocked[@]}"; do parts+=" #$u"; done
    parts="${parts# }"
    echo "now unblocked: $parts"
fi
