#!/usr/bin/env bash
# Sanity-check the backlog. --fix reopens done tasks whose closed_by_commit
# is no longer reachable from HEAD (e.g. after a rebase that dropped the commit).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX=0
DIR=""
USE_GLOBAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix) FIX=1; shift ;;
        --dir) DIR="$2"; shift 2 ;;
        -g|--global) USE_GLOBAL=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

DIR_RESOLVED="$(todo_storage_dir "$DIR" "$USE_GLOBAL")"
if [[ ! -d "$DIR_RESOLVED" ]]; then
    echo "(no storage dir; nothing to verify)"
    exit 0
fi

shopt -s nullglob
files=("$DIR_RESOLVED"/*.md)
shopt -u nullglob

issues=0
fixed=0
count=0

# 1. Orphan filenames.
for f in "${files[@]:-}"; do
    [[ -z "$f" ]] && continue
    stem="$(basename "$f" .md)"
    [[ "$stem" =~ ^[0-9]+$ ]] || continue
    count=$((count + 1))
    id_field="$(todo_get_field "$f" "id")"
    if [[ -n "$id_field" && "$id_field" != "$stem" ]]; then
        echo "  orphan: $(basename "$f") has id=$id_field"
        issues=$((issues + 1))
    fi
done

# 2. Dangling blocked_by refs.
for f in "${files[@]:-}"; do
    [[ -z "$f" ]] && continue
    stem="$(basename "$f" .md)"
    [[ "$stem" =~ ^[0-9]+$ ]] || continue
    raw="$(todo_get_field "$f" "blocked_by")"
    mapfile -t deps < <(todo_parse_list "$raw")
    for d in "${deps[@]:-}"; do
        [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && continue
        if [[ ! -f "$DIR_RESOLVED/$d.md" ]]; then
            echo "  dangling: #$stem blocked_by #$d (no such task)"
            issues=$((issues + 1))
        fi
    done
done

# 3. Cycles.
for f in "${files[@]:-}"; do
    [[ -z "$f" ]] && continue
    stem="$(basename "$f" .md)"
    [[ "$stem" =~ ^[0-9]+$ ]] || continue
    raw="$(todo_get_field "$f" "blocked_by")"
    mapfile -t deps < <(todo_parse_list "$raw")
    for d in "${deps[@]:-}"; do
        [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && continue
        if todo_cycle_check "$stem" "$d" "$DIR_RESOLVED"; then
            echo "  cycle: #$stem <-> #$d (transitive)"
            issues=$((issues + 1))
        fi
    done
done

# 4. Reachability of closed_by_commit.
if git rev-parse --git-dir >/dev/null 2>&1; then
    for f in "${files[@]:-}"; do
        [[ -z "$f" ]] && continue
        stem="$(basename "$f" .md)"
        [[ "$stem" =~ ^[0-9]+$ ]] || continue
        status="$(todo_get_field "$f" "status")"
        [[ "$status" != "done" ]] && continue
        commit="$(todo_get_field "$f" "closed_by_commit")"
        [[ -z "$commit" ]] && continue
        if ! git merge-base --is-ancestor "$commit" HEAD >/dev/null 2>&1; then
            echo "  unreachable: #$stem closed by $commit (not in HEAD history)"
            issues=$((issues + 1))
            if [[ "$FIX" -eq 1 ]]; then
                todo_update_field "$f" "status" "open"
                todo_update_field "$f" "closed_by_commit" ""
                todo_update_field "$f" "updated" "$(todo_utc_now)"
                echo "    -> reopened #$stem"
                fixed=$((fixed + 1))
            fi
        fi
    done
else
    echo "  (not a git repo; skipping reachability check)"
fi

echo
if (( issues == 0 )); then
    echo "OK ($count tasks, no issues)"
else
    echo "$issues issue(s) found, $fixed fixed"
fi
