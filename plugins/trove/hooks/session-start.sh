#!/usr/bin/env bash
# SessionStart hook: prints current-state snapshot + top ready todos.
# stdout is injected into the session context.

set -u
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    TODO="$CLAUDE_PLUGIN_ROOT/scripts/todo.sh"
else
    TODO="$HOME/.claude/scripts/trove/todo.sh"
fi
[[ -f "$TODO" ]] || exit 0

# Current-state snapshot (if cwd is inside a git repo).
if git rev-parse --git-dir >/dev/null 2>&1; then
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"
    dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "## Repo"
    echo "Branch: \`$branch\` ($dirty uncommitted change(s))"
    if git rev-parse HEAD >/dev/null 2>&1; then
        echo "Recent commits:"
        git log -n 3 --pretty=format:'  - %h %s' 2>/dev/null
        echo
    fi
    echo
fi

echo "## Backlog (top 5 ready)"
bash "$TODO" list --ready -n 5 2>/dev/null || true
