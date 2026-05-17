#!/usr/bin/env bash
# Delete a task file.

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
            if [[ -z "$ID" ]]; then ID="$1"; else echo "unexpected: $1" >&2; exit 2; fi
            shift
            ;;
    esac
done

[[ -z "$ID" ]] && { echo "id is required" >&2; exit 2; }

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
path="$DIR_RESOLVED/$ID.md"

[[ ! -f "$path" ]] && { echo "no task with id $ID" >&2; exit 1; }
rm -f "$path"
echo "#$ID removed"
