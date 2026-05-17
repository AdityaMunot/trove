#!/usr/bin/env bash
# Dispatcher: forwards to a sibling <action>.sh with the remaining args.
# Action scripts can also be invoked directly — same semantics.

set -euo pipefail

# Bash 4+ required (mapfile, associative arrays). macOS default is 3.2 —
# `brew install bash` to get a modern bash on PATH, then re-run.
if (( BASH_VERSINFO[0] < 4 )); then
    echo "trove requires bash 4+ (you have $BASH_VERSION)." >&2
    echo "macOS users: brew install bash" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: todo.sh <add|list|show|done|reopen|rm|edit|priority|tag|due|block|unblock|next|where|verify|sync> [args...]" >&2
    exit 2
fi

ACTION="$1"; shift

case "$ACTION" in
    add|list|show|done|reopen|rm|edit|priority|tag|due|where|block|unblock|next|verify|sync)
        exec "$SCRIPT_DIR/$ACTION.sh" "$@"
        ;;
    -h|--help)
        cat <<'EOF'
Usage: todo.sh <action> [args...]

Actions:
  add      "title" [-p high|med|low] [-d DATE] [-t tag1 tag2 ...] [-b id1 id2 ...]
  list     [-s open|done|all] [-p PRIORITY] [-t TAG] [-n N] [--ready] [--blocked]
           [--due-before YYYY-MM-DD] [--due-after YYYY-MM-DD]
  show     <id>
  done     <id>
  reopen   <id>
  rm       <id>
  edit     <id>                     (open in $EDITOR)
  priority <id> <high|med|low>
  tag      <id> <add|remove> <tag>
  due      <id> <YYYY-MM-DD|clear>
  block    <id> <blocker-id>
  unblock  <id> <blocker-id>
  next     (alias for `list --ready`)
  where
  verify   [--fix]                  (check / repair backlog state)
  sync     [--no-push] [--dry-run]  (git pull --rebase + git push for committed backlog)

Global options for all actions (except sync, where, verify):
  --dir <path>     Use an explicit storage directory.
  -g, --global     Use ~/.claude/todos (default is ~/.claude/projects/<cwd-slug>/todos).
EOF
        exit 0
        ;;
    *)
        echo "Invalid action: '$ACTION'" >&2
        echo "Valid: add, list, show, done, reopen, rm, edit, priority, tag, due, block, unblock, next, where, verify, sync" >&2
        exit 2
        ;;
esac
