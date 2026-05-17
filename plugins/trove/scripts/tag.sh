#!/usr/bin/env bash
# Add or remove a single tag on an existing task.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ID=""
OP=""
TAG=""
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$ID" ]]; then ID="$1"
            elif [[ -z "$OP" ]]; then OP="$1"
            elif [[ -z "$TAG" ]]; then TAG="$1"
            else echo "unexpected: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

[[ -z "$ID" || -z "$OP" || -z "$TAG" ]] && { echo "Usage: todo tag <id> <add|remove> <tag>" >&2; exit 2; }
case "$OP" in add|remove) ;; *) echo "invalid op: $OP (add/remove)" >&2; exit 2 ;; esac

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"
[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }

raw="$(todo_get_field "$path" "tags")"
tags=()
while IFS= read -r __line; do tags+=("$__line"); done < <(todo_parse_list "$raw")

if [[ "$OP" == "add" ]]; then
    for t in "${tags[@]:-}"; do
        [[ "$t" == "$TAG" ]] && { echo "#$ID already has tag '$TAG'"; exit 0; }
    done
    tags+=("$TAG")
else  # remove
    out=()
    found=0
    for t in "${tags[@]:-}"; do
        if [[ "$t" == "$TAG" ]]; then found=1
        else out+=("$t")
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "#$ID does not have tag '$TAG'"
        exit 1
    fi
    tags=("${out[@]:-}")
fi

# Rebuild the tags list literal.
acc=""
first=1
for t in "${tags[@]:-}"; do
    [[ -z "$t" ]] && continue
    if (( first == 1 )); then acc="$t"; first=0; else acc+=", $t"; fi
done
todo_update_field "$path" "tags" "[$acc]"
todo_update_field "$path" "updated" "$(todo_utc_now)"

title="$(todo_get_title "$path")"
echo "#$ID tag $OP '$TAG': $title"
