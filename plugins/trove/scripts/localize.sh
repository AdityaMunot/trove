#!/usr/bin/env bash
# Redirect ~/.claude/projects/<slug>/<kind>/ into <project>/.claude/<kind>/
# via symlink (Unix) / junction (Windows, see localize.ps1).
# Kinds: `memory` (Claude Code auto-memory), `todos` (the todo tool's storage).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: localize.sh <kind> [setup|status|cleanup] [--project-path <path>] [--project-slug <slug>] [--restore]

Kinds:
  memory   Claude Code auto-memory
  todos    the todo tool's per-project storage

Actions:
  setup    Create the symlink. Migrates existing files if the user-level
           folder is a real directory with contents.
  status   Show the current state for the project. (default)
  cleanup  Remove the symlink. Project-local files preserved by default;
           pass --restore to move them back to the user-level folder.

Options:
  --project-path <path>   Project root. Defaults to the current directory.
  --project-slug <slug>   Override the auto-derived slug.
  --restore               With 'cleanup': move files back to the user-level folder.
  -h, --help              Show this help.
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

KIND="$1"; shift
case "$KIND" in
  memory|todos) ;;
  -h|--help)    usage; exit 0 ;;
  *) echo "Invalid kind: $KIND (must be 'memory' or 'todos')" >&2; usage >&2; exit 2 ;;
esac

ACTION="status"
PROJECT_PATH=""
PROJECT_SLUG=""
RESTORE=0

if [[ $# -gt 0 && "$1" != -* ]]; then
  ACTION="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path) PROJECT_PATH="${2:-}"; shift 2 ;;
    --project-slug) PROJECT_SLUG="${2:-}"; shift 2 ;;
    --restore)      RESTORE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ACTION" in
  setup|status|cleanup) ;;
  *) echo "Invalid action: $ACTION" >&2; usage >&2; exit 2 ;;
esac

if [[ -z "$PROJECT_PATH" ]]; then
  PROJECT_PATH="$(pwd)"
fi

resolve_path() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    echo "Path does not exist: $p" >&2
    return 1
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    (cd "$p" && pwd -P)
  fi
}

PROJECT_PATH="$(resolve_path "$PROJECT_PATH")"
PROJECT_PATH="${PROJECT_PATH%/}"

# Canonicalize path on Windows (Git Bash / MSYS / Cygwin) so the slug matches
# what PowerShell produces from the same physical directory.
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_PATH="$(cygpath -m "$PROJECT_PATH" 2>/dev/null || printf '%s' "$PROJECT_PATH")"
fi

if [[ -z "$PROJECT_SLUG" ]]; then
  PROJECT_SLUG="$(printf '%s' "$PROJECT_PATH" | tr ':/\\' '-')"
fi

USER_DIR="$HOME/.claude/projects/$PROJECT_SLUG/$KIND"
PROJECT_DIR="$PROJECT_PATH/.claude/$KIND"

move_contents() {
  local from="$1" to="$2"
  local count=0
  shopt -s dotglob nullglob
  local items=("$from"/*)
  shopt -u dotglob nullglob
  if [[ ${#items[@]} -eq 0 ]]; then
    echo 0
    return
  fi
  mkdir -p "$to"
  for f in "${items[@]}"; do
    mv -f "$f" "$to/"
    count=$((count+1))
  done
  echo "$count"
}

print_state() {
  local link_type="" link_target=""
  local user_exists="False" project_exists="False"

  if [[ -L "$USER_DIR" || -e "$USER_DIR" ]]; then
    user_exists="True"
    if [[ -L "$USER_DIR" ]]; then
      link_type="SymbolicLink"
      link_target="$(readlink "$USER_DIR")"
    fi
  fi
  if [[ -d "$PROJECT_DIR" ]]; then
    project_exists="True"
  fi

  printf 'ProjectPath   : %s\n' "$PROJECT_PATH"
  printf 'Slug          : %s\n' "$PROJECT_SLUG"
  printf 'Kind          : %s\n' "$KIND"
  printf 'UserDir       : %s\n' "$USER_DIR"
  printf 'ProjectDir    : %s\n' "$PROJECT_DIR"
  printf 'UserExists    : %s\n' "$user_exists"
  printf 'LinkType      : %s\n' "$link_type"
  printf 'LinkTarget    : %s\n' "$link_target"
  printf 'ProjectExists : %s\n' "$project_exists"
}

case "$ACTION" in
  status)
    print_state
    ;;

  setup)
    if [[ -L "$USER_DIR" ]]; then
      current_target="$(readlink "$USER_DIR")"
      if [[ "$current_target" == "$PROJECT_DIR" ]]; then
        echo "Already linked (SymbolicLink): $USER_DIR -> $PROJECT_DIR"
        exit 0
      fi
      echo "User path exists as SymbolicLink -> $current_target. Run 'cleanup' first or remove it manually." >&2
      exit 1
    fi

    mkdir -p "$PROJECT_DIR"

    if [[ -d "$USER_DIR" ]]; then
      moved="$(move_contents "$USER_DIR" "$PROJECT_DIR")"
      if [[ "$moved" -gt 0 ]]; then
        echo "Migrated $moved item(s) -> $PROJECT_DIR"
      fi
      rmdir "$USER_DIR"
    fi

    mkdir -p "$(dirname "$USER_DIR")"
    ln -s "$PROJECT_DIR" "$USER_DIR"
    echo "Linked (SymbolicLink): $USER_DIR -> $PROJECT_DIR"
    ;;

  cleanup)
    if [[ ! -L "$USER_DIR" && ! -e "$USER_DIR" ]]; then
      echo "Nothing to clean: $USER_DIR does not exist."
      if [[ "$RESTORE" -eq 1 && -d "$PROJECT_DIR" ]]; then
        echo "Restoring project files to user-level path..."
        mkdir -p "$(dirname "$USER_DIR")"
        moved="$(move_contents "$PROJECT_DIR" "$USER_DIR")"
        rm -rf "$PROJECT_DIR"
        echo "Restored $moved item(s) -> $USER_DIR"
      fi
      exit 0
    fi

    if [[ ! -L "$USER_DIR" ]]; then
      echo "User path is a real directory, not a symlink. Refusing to delete: $USER_DIR" >&2
      exit 1
    fi

    rm "$USER_DIR"
    echo "Removed SymbolicLink: $USER_DIR"

    if [[ "$RESTORE" -eq 1 ]]; then
      if [[ -d "$PROJECT_DIR" ]]; then
        moved="$(move_contents "$PROJECT_DIR" "$USER_DIR")"
        rm -rf "$PROJECT_DIR"
        echo "Restored $moved item(s) -> $USER_DIR"
      else
        echo "Nothing to restore from $PROJECT_DIR"
      fi
    else
      echo "Project files preserved at: $PROJECT_DIR"
    fi
    ;;
esac
