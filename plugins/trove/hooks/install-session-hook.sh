#!/usr/bin/env bash
# Install a SessionStart hook into a project's .claude/settings.json.
# Adds a SessionStart entry calling the sibling session-start.sh. Resolves
# the wrapper's absolute path at install time (works in both plugin and
# manual install modes). Merges with existing hooks; doesn't clobber.
# Uses jq if available for safe in-place merging; otherwise writes a fresh
# settings.json (common case) or prints a paste-this snippet (rare edge).
#
# Usage:
#   install-session-hook.sh [--project-path /path/to/repo]

set -euo pipefail

PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-path) PROJECT_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$PROJECT_PATH" ]] && PROJECT_PATH="$(pwd)"
CLAUDE_DIR="$PROJECT_PATH/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_START="$SCRIPT_DIR/session-start.sh"
if [[ ! -f "$SESSION_START" ]]; then
    echo "Sibling session-start.sh not found at $SESSION_START." >&2
    exit 1
fi
CMD="bash \"$SESSION_START\""

# JSON-escape the command string (just backslash + double-quote).
escape_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}
CMD_JSON="\"$(escape_json "$CMD")\""

# Snippet we want present in settings.json's hooks.SessionStart array.
FRESH_JSON=$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": $CMD_JSON }
        ]
      }
    ]
  }
}
EOF
)

mkdir -p "$CLAUDE_DIR"

# Case 1: no settings.json yet (or empty) — write fresh, no merge needed.
if [[ ! -s "$SETTINGS" ]] || [[ "$(tr -d '[:space:]' < "$SETTINGS")" == "{}" ]]; then
    printf '%s\n' "$FRESH_JSON" > "$SETTINGS"
    echo "Installed SessionStart hook to $SETTINGS"
    exit 0
fi

# Case 2: settings.json has content. If our command is already present, no-op.
if grep -qF "$CMD" "$SETTINGS" 2>/dev/null; then
    echo "SessionStart hook already wired in $SETTINGS (no change)"
    exit 0
fi

# Case 3: existing content; merge. Prefer jq if available.
if command -v jq >/dev/null 2>&1; then
    tmp="$SETTINGS.tmp.$$"
    jq --arg cmd "$CMD" '
        .hooks.SessionStart = ((.hooks.SessionStart // []) + [{
            matcher: "",
            hooks: [{type: "command", command: $cmd}]
        }])
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "Installed SessionStart hook to $SETTINGS (merged via jq)"
    exit 0
fi

# Case 4: no jq, can't safely merge — print snippet for manual paste.
cat >&2 <<EOF
$SETTINGS already exists with other content. Auto-merge needs jq, which
isn't installed. Two options:

  1. Install jq (recommended):
       winget install jqlang.jq  # Windows
       brew install jq           # macOS
       sudo apt install jq       # Debian/Ubuntu
     then re-run this script.

  2. Manually merge this into the file's hooks.SessionStart array:

     {
       "matcher": "",
       "hooks": [
         { "type": "command", "command": $CMD_JSON }
       ]
     }

EOF
exit 1
