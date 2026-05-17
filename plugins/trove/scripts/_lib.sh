#!/usr/bin/env bash
# Shared helpers. Bash 4+ assumed (mapfile, associative arrays).

# ---- Path / slug helpers ----

# Slug: ':' '/' '\\' -> '-' (matches localize). On Windows, cygpath -m normalizes
# /c/X and c:/X to C:/X first so bash and PowerShell produce the same slug.
todo_slug() {
    local p="$1"
    if command -v cygpath >/dev/null 2>&1; then
        p="$(cygpath -m "$p" 2>/dev/null || printf '%s' "$p")"
    fi
    printf '%s' "$p" | tr ':/\\' '-'
}

# Resolve storage directory. Args: <dir> <use_global>
todo_storage_dir() {
    local dir="${1:-}" use_global="${2:-0}"
    if [[ -n "$dir" ]]; then
        if [[ "$dir" = /* ]]; then
            printf '%s' "$dir"
        elif command -v realpath >/dev/null 2>&1; then
            realpath -m "$dir"
        else
            local parent base
            parent="$(cd "$(dirname "$dir")" 2>/dev/null && pwd)" || parent="$(pwd)/$(dirname "$dir")"
            base="$(basename "$dir")"
            printf '%s' "$parent/$base"
        fi
        return
    fi
    if [[ "$use_global" -eq 1 ]]; then
        printf '%s' "$HOME/.claude/todos"
        return
    fi
    local cwd slug
    cwd="$(pwd)"
    slug="$(todo_slug "$cwd")"
    printf '%s' "$HOME/.claude/projects/$slug/todos"
}

todo_next_id() {
    local dir="$1"
    [[ -d "$dir" ]] || { echo 1; return; }
    local max=0
    shopt -s nullglob
    local files=("$dir"/*.md)
    shopt -u nullglob
    # Empty-glob guard: under `set -u`, "${files[@]}" on an empty array is
    # unbound on older bash (macOS default 3.2).
    [[ ${#files[@]} -eq 0 ]] && { echo 1; return; }
    for f in "${files[@]}"; do
        local base
        base="$(basename "$f" .md)"
        if [[ "$base" =~ ^[0-9]+$ ]]; then
            (( base > max )) && max="$base"
        fi
    done
    echo "$((max + 1))"
}

todo_utc_now() {
    date -u +'%Y-%m-%dT%H:%M:%S+00:00'
}

# ---- Frontmatter parsing ----

# Read one frontmatter field by name. Empty string if not present.
todo_get_field() {
    local path="$1" field="$2"
    awk -v field="$field" '
        BEGIN { state = 0 }
        /^---[[:space:]]*$/ {
            state++
            if (state >= 2) exit
            next
        }
        state == 1 {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            re = "^" field "[[:space:]]*:[[:space:]]*"
            if (line ~ re) {
                sub(re, "", line)
                sub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$path"
}

todo_get_title() {
    local path="$1"
    awk '
        BEGIN { state = 0 }
        /^---[[:space:]]*$/ { state++; next }
        state >= 2 {
            line = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "") next
            sub(/^#+[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "$path"
}

# Parse `[a, b, c]` -> newline-separated values. Empty if `[]` or missing.
todo_parse_list() {
    local raw="${1:-[]}"
    raw="${raw#[}"
    raw="${raw%]}"
    raw="${raw// /}"
    [[ -z "$raw" ]] && return
    printf '%s\n' "${raw//,/$'\n'}"
}

# Backward-compat alias.
todo_parse_tags() { todo_parse_list "$@"; }

# ---- Dependency helpers ----

# Echo open blocker IDs (space-separated, single line) for a given task file.
# A blocker is "open" if the referenced task exists and is not done.
todo_open_blockers() {
    local path="$1" dir="$2"
    local blocked_raw
    blocked_raw="$(todo_get_field "$path" "blocked_by")"
    local ids
    mapfile -t ids < <(todo_parse_list "$blocked_raw")
    local out=()
    for bid in "${ids[@]:-}"; do
        [[ "$bid" =~ ^[0-9]+$ ]] || continue
        local bpath="$dir/$bid.md"
        if [[ -f "$bpath" ]]; then
            local bs
            bs="$(todo_get_field "$bpath" "status")"
            [[ -z "$bs" ]] && bs="open"
            if [[ "$bs" != "done" ]]; then
                out+=("$bid")
            fi
        fi
    done
    if (( ${#out[@]} > 0 )); then
        printf '%s' "${out[*]}"
    fi
}

# IDs of tasks that have <id> in their blocked_by list. Newline-separated.
todo_blocks_of() {
    local id="$1" dir="$2"
    shopt -s nullglob
    local files=("$dir"/*.md)
    shopt -u nullglob
    [[ ${#files[@]} -eq 0 ]] && return
    for f in "${files[@]}"; do
        local stem
        stem="$(basename "$f" .md)"
        [[ "$stem" =~ ^[0-9]+$ ]] || continue
        local raw
        raw="$(todo_get_field "$f" "blocked_by")"
        local ids
        mapfile -t ids < <(todo_parse_list "$raw")
        for did in "${ids[@]:-}"; do
            [[ "$did" == "$id" ]] && echo "$stem" && break
        done
    done
}

# Would adding "A blocked_by B" create a cycle?  Returns 0 (true) if yes.
# DFS from B through blocked_by edges; if we ever reach A, cycle would form.
todo_cycle_check() {
    local a="$1" b="$2" dir="$3"
    [[ "$a" == "$b" ]] && return 0
    declare -A visited
    local stack=("$b")
    while (( ${#stack[@]} > 0 )); do
        local cur="${stack[-1]}"
        unset 'stack[-1]'
        [[ -n "${visited[$cur]:-}" ]] && continue
        visited[$cur]=1
        [[ "$cur" == "$a" ]] && return 0
        local cpath="$dir/$cur.md"
        [[ -f "$cpath" ]] || continue
        local raw
        raw="$(todo_get_field "$cpath" "blocked_by")"
        local deps
        mapfile -t deps < <(todo_parse_list "$raw")
        for d in "${deps[@]:-}"; do
            [[ "$d" =~ ^[0-9]+$ ]] && stack+=("$d")
        done
    done
    return 1
}

# ---- In-place field update (frontmatter only) ----

todo_update_field() {
    local path="$1" field="$2" value="$3"
    local escaped
    escaped="${value//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' -E "s|^${field}:[[:space:]]*.*$|${field}: ${escaped}|" "$path"
    else
        sed -i -E "s|^${field}:[[:space:]]*.*$|${field}: ${escaped}|" "$path"
    fi
}

# Add a single id to the blocked_by list, preserving the rest. No-op if already present.
todo_blocked_by_add() {
    local path="$1" new_id="$2"
    local raw
    raw="$(todo_get_field "$path" "blocked_by")"
    local ids
    mapfile -t ids < <(todo_parse_list "$raw")
    for x in "${ids[@]:-}"; do
        [[ "$x" == "$new_id" ]] && return 1   # already present
    done
    ids+=("$new_id")
    local acc="" first=1
    for x in "${ids[@]}"; do
        [[ -z "$x" ]] && continue
        if (( first == 1 )); then acc="$x"; first=0; else acc+=", $x"; fi
    done
    todo_update_field "$path" "blocked_by" "[$acc]"
    return 0
}

# Remove a single id from the blocked_by list. Returns 1 if it wasn't present.
todo_blocked_by_remove() {
    local path="$1" rm_id="$2"
    local raw
    raw="$(todo_get_field "$path" "blocked_by")"
    local ids
    mapfile -t ids < <(todo_parse_list "$raw")
    local out=() found=0
    for x in "${ids[@]:-}"; do
        if [[ "$x" == "$rm_id" ]]; then
            found=1
        else
            out+=("$x")
        fi
    done
    [[ "$found" -eq 0 ]] && return 1
    local acc="" first=1
    for x in "${out[@]:-}"; do
        [[ -z "$x" ]] && continue
        if (( first == 1 )); then acc="$x"; first=0; else acc+=", $x"; fi
    done
    todo_update_field "$path" "blocked_by" "[$acc]"
    return 0
}

# ---- Output formatting ----

# Compact one-line list output.
# Args: id status priority title open_blockers_csv tag1 tag2 ...
#   open_blockers_csv: space-separated open blocker IDs (empty for ready/done).
todo_format_line() {
    local id="$1" status="$2" priority="$3" title="$4" open_blockers="${5:-}"
    shift 5
    local tags=("$@")

    local box prio idstr tagstr="" blockstr=""
    if [[ "$status" == "done" ]]; then
        box="[x]"
    elif [[ -n "$open_blockers" ]]; then
        box="[~]"
    else
        box="[ ]"
    fi
    case "$priority" in
        high) prio="!" ;;
        low)  prio="." ;;
        *)    prio=" " ;;
    esac
    idstr="$(printf '%3d' "$id")"
    for t in "${tags[@]:-}"; do
        [[ -n "$t" ]] && tagstr+=" #$t"
    done
    if [[ -n "$open_blockers" ]]; then
        local b acc=""
        for b in $open_blockers; do acc+=" #$b"; done
        acc="${acc# }"
        blockstr="  (blocked by $acc)"
    fi
    printf '%s #%s %s %s%s%s\n' "$box" "$idstr" "$prio" "$title" "$tagstr" "$blockstr"
}

# Write a complete todo markdown file.
# Args: path id title status priority due created updated blocked_csv tag1 tag2 ...
#   due: ISO 8601 date string, or empty for no due date.
#   blocked_csv: space-separated blocker IDs (empty for none).
todo_create_file() {
    local path="$1" id="$2" title="$3" status="$4" priority="$5" due="${6:-}" created="$7" updated="$8" blocked_csv="${9:-}"
    shift 9
    # Tags list
    local tags_str="[]"
    if (( $# > 0 )); then
        local acc="" first=1
        for t in "$@"; do
            [[ -z "$t" ]] && continue
            if (( first == 1 )); then acc="$t"; first=0; else acc+=", $t"; fi
        done
        tags_str="[$acc]"
    fi
    # Blocked-by list
    local blocked_str="[]"
    if [[ -n "$blocked_csv" ]]; then
        local b acc="" first=1
        for b in $blocked_csv; do
            [[ -z "$b" ]] && continue
            if (( first == 1 )); then acc="$b"; first=0; else acc+=", $b"; fi
        done
        blocked_str="[$acc]"
    fi
    {
        echo "---"
        echo "id: $id"
        echo "status: $status"
        echo "priority: $priority"
        echo "due: $due"
        echo "tags: $tags_str"
        echo "blocked_by: $blocked_str"
        echo "created: $created"
        echo "updated: $updated"
        echo "---"
        echo "# $title"
    } > "$path"
}

# Ensure a frontmatter field exists. If missing, insert just before
# `created:` (stable ordering, matching the closed_by_commit pattern).
todo_ensure_field() {
    local path="$1" field="$2" value="${3:-}"
    if grep -q "^${field}:" "$path"; then
        todo_update_field "$path" "$field" "$value"
    else
        if [[ "$(uname -s)" == "Darwin" ]]; then
            sed -i '' "/^created:/i\\
${field}: ${value}
" "$path"
        else
            sed -i "/^created:/i ${field}: ${value}" "$path"
        fi
    fi
}
