#!/usr/bin/env bash
# git pull --rebase + git push for committed .claude/todos/ backlogs.
# Refuses if dirty outside .claude/todos/. Auto-renumbers add/add conflicts
# on numeric .md files (upstream keeps the id; local one moves to next free).
# Follow-up commits referencing the renumbered id will fail — resolve manually.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

NO_PUSH=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-push)       NO_PUSH=1; shift ;;
        --dry-run|-n)    DRY_RUN=1; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: todo sync [--no-push] [--dry-run]
  --no-push   pull only
  --dry-run   show commands without running

Runs git pull --rebase + git push inside a repo with `localize todos setup`.
Refuses if dirty outside .claude/todos/. Auto-renumbers add/add conflicts on
numeric .md (upstream keeps the id; local one moves to next free).
EOF
            exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "not in a git repo" >&2; exit 1
}
TODOS_REL=".claude/todos"
TODOS_ABS="$REPO_ROOT/$TODOS_REL"
[[ -d "$TODOS_ABS" ]] || {
    echo "no $TODOS_REL/ in $REPO_ROOT — run 'localize todos setup' first" >&2
    exit 1
}

# Refuse if working tree is dirty outside .claude/todos/.
dirty="$(git -C "$REPO_ROOT" status --porcelain | grep -vE '^\?\? \.claude/todos/|^[ MADRCU][ MADRCU]? \.claude/todos/' || true)"
if [[ -n "$dirty" ]]; then
    echo "working tree has changes outside .claude/todos/:" >&2
    printf '%s\n' "$dirty" | sed 's/^/  /' >&2
    echo "commit or stash them first" >&2
    exit 1
fi

run() {
    echo "+ $*"
    [[ "$DRY_RUN" -eq 1 ]] || "$@"
}

# Renumber a single conflicted file. Args: <relative-path-from-repo-root>
# Reads stage 3 (the local/incoming version during rebase), keeps upstream's
# file on disk, writes the local content to a fresh next-id with `id:` updated.
renumber_conflict() {
    local conflict_path="$1"
    local old_id new_id new_path tmp
    old_id="$(basename "$conflict_path" .md)"

    tmp="$(mktemp)"
    if ! git -C "$REPO_ROOT" show ":3:$conflict_path" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "could not extract local version of $conflict_path" >&2
        return 1
    fi

    # Keep upstream's version on disk; mark conflict resolved.
    git -C "$REPO_ROOT" checkout --ours -- "$conflict_path"
    git -C "$REPO_ROOT" add "$conflict_path"

    # Allocate a fresh id (after upstream's adds — todo_next_id reads the dir).
    new_id="$(todo_next_id "$TODOS_ABS")"
    new_path="$TODOS_ABS/$new_id.md"

    # Update the `id:` line in the local content to match the new filename.
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' -E "s|^id:[[:space:]]+${old_id}$|id: $new_id|" "$tmp"
    else
        sed -i -E "s|^id:[[:space:]]+${old_id}$|id: $new_id|" "$tmp"
    fi

    mv "$tmp" "$new_path"
    git -C "$REPO_ROOT" add "$new_path"

    echo "renumbered: #$old_id -> #$new_id (conflicted with upstream)"
}

# After a failed `pull --rebase`, loop until the rebase finishes or we hit a
# conflict we can't auto-resolve.
finish_rebase() {
    while [[ -d "$REPO_ROOT/.git/rebase-merge" || -d "$REPO_ROOT/.git/rebase-apply" ]]; do
        # Find add/add conflicts (`AA` in porcelain) on .claude/todos/<digits>.md.
        local conflicts
        mapfile -t conflicts < <(git -C "$REPO_ROOT" status --porcelain \
            | awk -v rel="$TODOS_REL" '/^AA / {
                sub(/^AA[[:space:]]+/, "")
                if ($0 ~ "^"rel"/[0-9]+\\.md$") print
            }')

        if [[ ${#conflicts[@]} -eq 0 ]]; then
            echo "" >&2
            echo "non-renumbering conflict during rebase. Resolve manually, then:" >&2
            echo "  git -C \"$REPO_ROOT\" rebase --continue" >&2
            return 1
        fi

        local c
        for c in "${conflicts[@]}"; do
            renumber_conflict "$c" || return 1
        done

        # GIT_EDITOR=true short-circuits the commit-message editor and reuses the existing message.
        GIT_EDITOR=true git -C "$REPO_ROOT" rebase --continue || true
    done
    return 0
}

# --- Pull (with auto-renumber on conflict) ---
echo "+ git -C \"$REPO_ROOT\" pull --rebase"
if [[ "$DRY_RUN" -eq 1 ]]; then
    : # dry-run skips the actual pull
elif ! git -C "$REPO_ROOT" pull --rebase; then
    finish_rebase || exit 1
fi

# --- Push ---
if [[ "$NO_PUSH" -eq 0 ]]; then
    run git -C "$REPO_ROOT" push
fi

echo "todo sync complete."
