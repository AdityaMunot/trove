#!/usr/bin/env bash
# Print one task's full markdown + blocked_by / blocks summary lines.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ID=""
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$ID" ]]; then
                ID="$1"
            else
                echo "unexpected arg: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

[[ -z "$ID" ]] && { echo "id is required" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"

[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }
cat "$path"

# Append relationship lines: blocked_by status + what this task blocks.
blocked_raw="$(todo_get_field "$path" "blocked_by")"
mapfile -t deps < <(todo_parse_list "$blocked_raw")
if (( ${#deps[@]} > 0 )) && [[ -n "${deps[0]:-}" ]]; then
    parts=""
    for d in "${deps[@]}"; do
        [[ -z "$d" ]] && continue
        bpath="$DIR_RESOLVED/$d.md"
        if [[ -f "$bpath" ]]; then
            bs="$(todo_get_field "$bpath" "status")"
            [[ -z "$bs" ]] && bs="open"
            if [[ "$bs" == "done" ]]; then
                parts+=" #$d [done]"
            else
                parts+=" #$d [open]"
            fi
        else
            parts+=" #$d [missing]"
        fi
    done
    parts="${parts# }"
    echo "blocked_by: $parts"
fi

# What does this id block?
blocks=""
while IFS= read -r bid; do
    [[ -z "$bid" ]] && continue
    bpath="$DIR_RESOLVED/$bid.md"
    bs="$(todo_get_field "$bpath" "status")"
    [[ -z "$bs" ]] && bs="open"
    if [[ "$bs" == "done" ]]; then
        blocks+=" #$bid [done]"
    else
        blocks+=" #$bid [open]"
    fi
done < <(todo_blocks_of "$ID" "$DIR_RESOLVED")
if [[ -n "$blocks" ]]; then
    blocks="${blocks# }"
    echo "blocks: $blocks"
fi
