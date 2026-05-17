#!/usr/bin/env bash
# Copy trove's git hook templates into <project>/.git/hooks/.
# Templated copy: substitutes __TODO_DISPATCHER__ in post-commit and
# post-rewrite with the resolved absolute path of the sibling todo.sh.
# Skips files that already exist unless --force.

set -euo pipefail

PROJECT_PATH=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-path) PROJECT_PATH="$2"; shift 2 ;;
        --force|-f) FORCE=1; shift ;;
        -h|--help)
            sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$PROJECT_PATH" ]] && PROJECT_PATH="$(pwd)"

if [[ ! -d "$PROJECT_PATH/.git" ]]; then
    echo "Not a git repo: $PROJECT_PATH (no .git directory)" >&2
    exit 1
fi

HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "$HOOKS_SRC" ]]; then
    echo "Hook templates not found at $HOOKS_SRC." >&2
    exit 1
fi

# Locate the todo.sh dispatcher. Two layouts:
#   - Plugin mode:  $HOOKS_SRC = <plugin>/git-hooks/    → dispatcher at ../scripts/todo.sh
#   - Manual mode:  $HOOKS_SRC = ~/.claude/scripts/todo/git-hooks/ → dispatcher at ../todo.sh
TODO_DISPATCHER=""
for candidate in "$HOOKS_SRC/../scripts/todo.sh" "$HOOKS_SRC/../todo.sh"; do
    if [[ -f "$candidate" ]]; then
        TODO_DISPATCHER="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
        break
    fi
done
if [[ -z "$TODO_DISPATCHER" ]]; then
    echo "Cannot locate todo.sh dispatcher near $HOOKS_SRC (looked in ../scripts/todo.sh and ../todo.sh)." >&2
    exit 1
fi
# Normalize to forward-slash form so the substituted path works in Git Bash regardless of host shell.
if command -v cygpath >/dev/null 2>&1; then
    TODO_DISPATCHER="$(cygpath -m "$TODO_DISPATCHER" 2>/dev/null || printf '%s' "$TODO_DISPATCHER")"
fi

HOOKS_DST="$PROJECT_PATH/.git/hooks"
mkdir -p "$HOOKS_DST"

for name in post-commit post-rewrite; do
    src="$HOOKS_SRC/$name"
    dst="$HOOKS_DST/$name"
    if [[ ! -f "$src" ]]; then
        echo "  missing source: $src" >&2
        continue
    fi
    if [[ -e "$dst" && "$FORCE" -ne 1 ]]; then
        echo "  skip (already exists): $dst (use --force to overwrite)"
        continue
    fi
    # Substitute the dispatcher path into the template at copy time.
    # Use '|' as sed delimiter since the path may contain '/'.
    sed "s|__TODO_DISPATCHER__|${TODO_DISPATCHER}|g" "$src" > "$dst"
    chmod +x "$dst"
    echo "  installed: $dst  (dispatcher: $TODO_DISPATCHER)"
done

echo
echo "Done. Commits in this repo with 'closes #N' / 'fixes #N' / 'done #N'"
echo "will now auto-close the matching todos in $PROJECT_PATH/.claude/todos/."
