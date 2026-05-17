#!/usr/bin/env bash
# Print the resolved storage directory for the current mode.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

todo_storage_dir "$DIR" "$USE_GLOBAL"
