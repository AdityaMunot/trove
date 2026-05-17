#!/usr/bin/env bash
# Install a SessionStart hook into a project's .claude/settings.json.
# Adds a SessionStart entry calling the sibling session-start.sh. Resolves
# the wrapper's absolute path at install time (works in both plugin and
# manual install modes). Merges with existing hooks; doesn't clobber.
# Requires `jq`.
#
# Usage:
#   install-session-hook.sh [--project-path /path/to/repo]

set -euo pipefail

PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-path) PROJECT_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$PROJECT_PATH" ]] && PROJECT_PATH="$(pwd)"
CLAUDE_DIR="$PROJECT_PATH/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but not installed. brew install jq / apt install jq" >&2
    exit 1
fi

mkdir -p "$CLAUDE_DIR"
[[ -f "$SETTINGS" ]] || echo "{}" > "$SETTINGS"
[[ -s "$SETTINGS" ]] || echo "{}" > "$SETTINGS"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_START="$SCRIPT_DIR/session-start.sh"
if [[ ! -f "$SESSION_START" ]]; then
    echo "Sibling session-start.sh not found at $SESSION_START." >&2
    exit 1
fi
CMD="bash \"$SESSION_START\""

# No-op if our command is already wired up.
already=$(jq --arg cmd "$CMD" '
    (.hooks.SessionStart // []) | map(.hooks // [] | map(select(.command == $cmd)) | length) | add // 0
' "$SETTINGS")

if [[ "$already" -gt 0 ]]; then
    echo "SessionStart hook already wired in $SETTINGS (no change)"
    exit 0
fi

tmp="$SETTINGS.tmp.$$"
jq --arg cmd "$CMD" '
    .hooks.SessionStart = ((.hooks.SessionStart // []) + [{
        matcher: "",
        hooks: [{type: "command", command: $cmd}]
    }])
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Installed SessionStart hook to $SETTINGS"
