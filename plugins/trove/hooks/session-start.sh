#!/usr/bin/env bash
# SessionStart hook: prints top ready todos. stdout is injected into the session.

set -u
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    TODO="$CLAUDE_PLUGIN_ROOT/scripts/todo.sh"
else
    TODO="$HOME/.claude/scripts/trove/todo.sh"
fi
[[ -f "$TODO" ]] || exit 0

echo "## Backlog (top 5 ready)"
bash "$TODO" list --ready -n 5 2>/dev/null || true
