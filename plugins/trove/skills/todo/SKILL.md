---
name: todo
description: Persistent, git-friendly todo backlog across Claude Code sessions. Triggers on requests to add, list, show, complete, reopen, remove, edit, prioritize, tag, set a due date for, or block/unblock tasks; or to check what's on the backlog. Three storage modes - per-project (default, ~/.claude/projects/<slug>/todos/), global (-g), explicit (--dir). Pairs with the localize skill to commit the per-project backlog into a repo. Never Read the underlying .md files; always invoke the dispatcher.
---

# todo

Persistent, git-friendly todo backlog. One markdown file per task. Native shell on each platform.

Sibling: [[localize]] redirects the per-project storage into the repo.

## Storage modes

- **Per-project** (default, no flags) → `~/.claude/projects/<cwd-slug>/todos/`. The everyday case. Use when the user says *"add a todo"*, *"what's left?"*, *"mark X done"*.
- **Global** (`-g` / `--global`) → `~/.claude/todos/`. Use for *"global todo"*, *"personal backlog"*, *"cross-project"*.
- **Explicit** (`--dir <path>`) → that path.

Per-project pairs with `localize todos setup` — the path becomes a junction/symlink into `<project>/.claude/todos/`.

## How to invoke

Bash scripts only (works on Windows via Git Bash, which Git for Windows ships).

Scripts live at:
- **Plugin install** — `$env:CLAUDE_PLUGIN_ROOT/scripts/`
- **Manual install** — `$HOME/.claude/scripts/trove/`

```bash
base="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
base="${base:-$HOME/.claude/scripts/trove}"
bash "$base/todo.sh" <action> [args...]
```

Action scripts can also be invoked directly — same semantics.

### Subcommands

All accept `--dir <path>` and `-g` / `--global`.

| Command | Purpose |
|---|---|
| `add "title" [-p high\|med\|low] [-d DATE] [-t TAG...] [-b ID...]` | Create. Returns new id. |
| `list [-s open\|done\|all] [-p PRIORITY] [-t TAG] [-n N] [--ready\|--blocked] [--due-before DATE] [--due-after DATE]` | One line per task. Default: open only. Tasks without a due date are excluded from `--due-*` filters. |
| `show <id>` | Full markdown + `blocked_by:` / `blocks:` summary. |
| `done <id>` | Mark complete. Prints `now unblocked: #X #Y` if anything became actionable. |
| `reopen <id>` | Mark open again. |
| `rm <id>` | Delete the task file. |
| `edit <id>` | Open in `$EDITOR` (or `$VISUAL`, then `notepad`/`nano`/`vi`). Bumps `updated:` on clean exit. |
| `priority <id> <high\|med\|low>` | Change priority. |
| `tag <id> <add\|remove> <tag>` | Add/remove a single tag. |
| `due <id> <YYYY-MM-DD\|clear>` | Set/clear due date. ISO 8601. |
| `block <id> <blocker-id>` | Add dependency. Refuses cycles. |
| `unblock <id> <blocker-id>` | Remove dependency. |
| `next` | Alias for `list --ready`. |
| `where` | Print the resolved storage directory. |
| `sync [--no-push] [--dry-run]` | For committed backlogs: `git pull --rebase` + `git push`. Refuses if dirty outside `.claude/todos/`. **Auto-renumbers** add/add conflicts on numeric `.md` (local one renamed to next free id, `id:` field updated). |

### Tags on `add`

Space-separated: `-t docs trove`.

### List output format

```
[ ] #  1 ! Bash port                            #infra
[~] #  2 ! Delete .py                           #cleanup  (blocked by #1)
[x] #  3 . Build todo skill wrapper             #feature
```

`[ ]` / `[~]` / `[x]` = open-ready / open-blocked / done · `!` / ` ` / `.` = priority high / med / low.

## Confirmation policy

- `list`, `show`, `where` — read-only, run freely.
- `add`, `done`, `reopen`, `priority`, `tag`, `due`, `block`, `unblock`, `edit` — proceed without confirming.
- `rm`, `sync` — confirm unless the user was explicit. `rm` deletes a file; `sync` pushes commits.

## After running

- `add` / `done` / `reopen` / `rm` / mutators — relay the one-line confirmation, no extra summary.
- `list` — if ≤10 lines, print verbatim. If longer, summarize.
- `show` — relay the title + any open questions in the body; skip the frontmatter unless asked.

## Notes

- The dispatcher prints only the slice you ask for. Don't `Read` the .md files directly.
- Tasks are plain markdown with YAML-ish frontmatter. Hand-editable.
- Task files created before a field landed may lack it (e.g. `blocked_by:`, `due:`). Parsers default missing fields to empty; mutators insert the line if absent.
