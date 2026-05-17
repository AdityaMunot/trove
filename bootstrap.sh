#!/usr/bin/env bash
# trove bootstrap (macOS / Linux / bash). Handles install and uninstall.
#
# Walks plugins/<name>/ to know what to copy (install) or remove (uninstall)
# under ~/.claude/. By default acts on every plugin; use --no-<plugin> to skip
# individual ones, e.g. --no-todo or --no-localize.
#
# Usage (remote one-liner, install both plugins):
#   curl -fsSL https://raw.githubusercontent.com/AdityaMunot/trove/master/bootstrap.sh | bash
#
# Usage (remote one-liner, uninstall — `bash -s --` passes args through the pipe):
#   curl -fsSL .../bootstrap.sh | bash -s -- uninstall
#   curl -fsSL .../bootstrap.sh | bash -s -- uninstall --no-todo   # keep todo
#
# Usage (local clone — dev sync after editing files in the repo):
#   ./bootstrap.sh                          # install/refresh both
#   ./bootstrap.sh --no-localize            # install only todo
#   ./bootstrap.sh uninstall --dry-run      # preview uninstall
#   ./bootstrap.sh uninstall                # remove both plugins
#
# IMPORTANT: uninstall does NOT touch (they live outside the plugin's domain):
#   - .git/hooks/post-commit / post-rewrite in any project where you ran install-hooks
#   - .claude/{memory,todos}/ symlinks in projects where you ran `localize <kind> setup`
#     (run `localize <kind> cleanup --project-path <path>` BEFORE uninstall if you want them gone)
#   - .claude/todos/*.md backlog files (plain text in your repo)

set -euo pipefail

# --- Arg parsing ---
ACTION="install"
case "${1:-}" in
    install|uninstall) ACTION="$1"; shift ;;
esac

SKIP=()
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-*) SKIP+=("${1#--no-}"); shift ;;
        --dry-run|-n) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

is_skipped() {
    local name="$1"
    for s in "${SKIP[@]:-}"; do [[ "$s" == "$name" ]] && return 0; done
    return 1
}

CLAUDE_ROOT="$HOME/.claude"

# --- Resolve source: local clone if running from inside trove, else clone fresh ---
TROVE_ROOT=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/.claude-plugin/marketplace.json" && -d "$SCRIPT_DIR/plugins" ]]; then
        TROVE_ROOT="$SCRIPT_DIR"
        echo "Using local trove clone at $TROVE_ROOT"
    fi
fi
if [[ -z "$TROVE_ROOT" ]]; then
    REPO="https://github.com/AdityaMunot/trove.git"
    TROVE_ROOT="$(mktemp -d -t trove-bootstrap-XXXXXX)"
    trap 'rm -rf "$TROVE_ROOT"' EXIT
    echo "Cloning $REPO into $TROVE_ROOT ..."
    git clone --depth 1 "$REPO" "$TROVE_ROOT"
fi

# --- Copy helpers (install) ---
copy_tree() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    (cd "$src" && find . -type f -print0) | while IFS= read -r -d '' f; do
        local rel="${f#./}"
        local target="$dst/$rel"
        mkdir -p "$(dirname "$target")"
        cp -f "$src/$rel" "$target"
        echo "  -> $target"
    done
}

# Copy only top-level .ps1/.sh from a plugin's hooks/ dir (skip hooks.json — plugin-only metadata).
copy_hook_scripts() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    (cd "$src" && find . -maxdepth 1 -type f \( -name "*.ps1" -o -name "*.sh" \) -print0) | while IFS= read -r -d '' f; do
        local rel="${f#./}"
        cp -f "$src/$rel" "$dst/$rel"
        echo "  -> $dst/$rel"
    done
}

# --- Remove helper (uninstall) ---
remove_path() {
    local target="$1"
    [[ -e "$target" || -L "$target" ]] || return 0
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would remove: $target"
    else
        rm -rf "$target"
        echo "  removed: $target"
    fi
}

# --- Per-plugin action ---
install_plugin() {
    local plugin_dir="$1" plugin_name="$2"
    copy_tree         "${plugin_dir}scripts"   "$CLAUDE_ROOT/scripts/$plugin_name"
    copy_tree         "${plugin_dir}skills"    "$CLAUDE_ROOT/skills"
    copy_tree         "${plugin_dir}git-hooks" "$CLAUDE_ROOT/scripts/$plugin_name/git-hooks"
    copy_hook_scripts "${plugin_dir}hooks"     "$CLAUDE_ROOT/scripts/hooks"
}

uninstall_plugin() {
    local plugin_dir="$1" plugin_name="$2"

    # Remove the whole namespaced scripts dir (includes copied scripts/ + git-hooks/).
    remove_path "$CLAUDE_ROOT/scripts/$plugin_name"

    # Remove the skill dirs this plugin owned.
    if [[ -d "${plugin_dir}skills" ]]; then
        for skill_dir in "${plugin_dir}skills"/*/; do
            [[ -d "$skill_dir" ]] || continue
            remove_path "$CLAUDE_ROOT/skills/$(basename "$skill_dir")"
        done
    fi

    # Remove the hook scripts (.ps1/.sh) this plugin contributed to ~/.claude/scripts/hooks/.
    if [[ -d "${plugin_dir}hooks" ]]; then
        (cd "${plugin_dir}hooks" && find . -maxdepth 1 -type f \( -name "*.ps1" -o -name "*.sh" \) -print0) \
            | while IFS= read -r -d '' f; do
                remove_path "$CLAUDE_ROOT/scripts/hooks/${f#./}"
            done
    fi
}

# --- Walk plugins/<name>/ ---
case "$ACTION" in
    install)   echo "Installing into $CLAUDE_ROOT ..." ;;
    uninstall) echo "Uninstalling from $CLAUDE_ROOT ..." ;;
esac
acted=()
for plugin_dir in "$TROVE_ROOT/plugins"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    plugin_name="$(basename "$plugin_dir")"
    if is_skipped "$plugin_name"; then
        echo "  (skipping plugin: $plugin_name)"
        continue
    fi
    case "$ACTION" in
        install)   install_plugin   "$plugin_dir" "$plugin_name" ;;
        uninstall) uninstall_plugin "$plugin_dir" "$plugin_name" ;;
    esac
    acted+=("$plugin_name")
done

# Mark installed bash scripts executable.
if [[ "$ACTION" == "install" ]]; then
    find "$CLAUDE_ROOT/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
fi

# --- Final output ---
echo
case "$ACTION" in
    install)
        echo "trove installed (${acted[*]:-none}). Restart Claude Code so new skills are picked up."
        if [[ " ${acted[*]:-} " == *" trove "* ]]; then
            echo
            echo "Per-project setup (run inside a git repo as needed):"
            echo "  bash ~/.claude/scripts/trove/git-hooks/install-hooks.sh    # auto-close todos on commit"
            echo "  bash ~/.claude/scripts/hooks/install-session-hook.sh       # SessionStart per project (manual installs only)"
            echo "  bash ~/.claude/scripts/trove/localize.sh todos  setup      # keep .claude/todos in the repo"
            echo "  bash ~/.claude/scripts/trove/localize.sh memory setup      # keep .claude/memory in the repo"
        fi
        ;;
    uninstall)
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "Dry-run complete. Re-run without --dry-run to apply."
        else
            echo "trove uninstalled (${acted[*]:-none})."
            echo
            echo "Reminder — things outside the plugin's domain were NOT removed:"
            echo "  * .git/hooks/post-commit / post-rewrite in projects (manual)"
            echo "  * .claude/{memory,todos}/ symlinks (run localize cleanup BEFORE uninstall)"
            echo "  * .claude/todos/*.md backlog files (plain text in your repo)"
        fi
        ;;
esac
