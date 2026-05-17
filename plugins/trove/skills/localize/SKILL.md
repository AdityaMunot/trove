---
name: localize
description: Redirect Claude Code's per-project state from ~/.claude/projects/<slug>/<kind>/ into <project>/.claude/<kind>/ via a Windows junction or POSIX symlink. Triggers on requests to localize memory or todos into a project, undo such localization, or check whether memory/todos are localized. Pass memory or todos as the kind. Three actions - setup (auto-migrates existing files), status, cleanup (with --restore to move files back into the user-level folder).
---

# localize

Redirect `~/.claude/projects/<slug>/<kind>/` into `<project>/.claude/<kind>/`. Junction on Windows, symlink on macOS/Linux. The underlying tools (Claude Code for memory; the [[todo]] tool for todos) keep writing to their default paths — the link transparently sends writes into the project.

## Two kinds

| Kind | Localizes | User-level path | After setup |
|---|---|---|---|
| `memory` | Claude Code auto-memory | `~/.claude/projects/<slug>/memory/` | `<project>/.claude/memory/` |
| `todos` | The [[todo]] tool's per-project storage | `~/.claude/projects/<slug>/todos/` | `<project>/.claude/todos/` |

If the user says *"localize this project"* without specifying which, ask whether they mean memory, todos, or both.

## How to invoke

Bash script only (works on Windows via Git Bash). Always pass `--project-path` with the absolute path.

Script lives at:
- **Plugin install** — `$env:CLAUDE_PLUGIN_ROOT/scripts/localize.sh`
- **Manual install** — `$HOME/.claude/scripts/trove/localize.sh`

```bash
base="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
base="${base:-$HOME/.claude/scripts/trove}"
bash "$base/localize.sh" <kind> <setup|status|cleanup> --project-path <abs-path> [--restore]
```

### Actions

- **`status`** — Read-only. Run first if unsure of state.
- **`setup`** — Create the link. Auto-migrates existing files if the user-level folder has contents. Idempotent.
- **`cleanup`** — Remove the link. Project-local files preserved by default. `--restore` moves them back into the user-level folder and deletes the project-local one.

## Confirmation policy

- `status` — read-only, run freely.
- `setup` — proceed if no link / no project-local folder. Otherwise report state and ask.
- `cleanup` — always confirm; state-changing. Mention whether `--restore` will be used.

## After running

Report: action + kind, resolved user-level path, project-local path, and migration count if any.

## Notes

- Windows uses a directory junction (no admin / Developer Mode needed). Unix uses a symbolic link.
- Slug rule: `:` and path separators (`\` / `/`) → `-`. On Windows under Git Bash, paths are canonicalized via `cygpath -m` first so bash and PowerShell agree. Override with `--project-slug` if needed.
- If the project folder is deleted or moved, the link breaks. Re-run `setup` from the new location.
- `.gitignore` guidance: both `.claude/memory/` and `.claude/todos/` are typically personal/per-machine — ignore the contents and `.gitkeep` the folders, or ignore the folders entirely.
