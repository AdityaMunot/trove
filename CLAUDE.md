# Trove — project guide for Claude

Personal Claude Code tooling. Single plugin (`trove`) bundling two skills (`todo`, `localize`), installed via `bootstrap.sh` (PowerShell trampoline `bootstrap.ps1` shells out to it). Bash-only runtime; Windows uses Git Bash. Also structured as a Claude Code plugin marketplace — ready for submission, not yet submitted.

## Layout

```
plugins/trove/
├── .claude-plugin/plugin.json
├── skills/
│   ├── todo/SKILL.md
│   └── localize/SKILL.md
├── hooks/                         SessionStart: hooks.json + session-start.sh + install-session-hook.sh
├── git-hooks/                     post-commit + post-rewrite + install-hooks.sh
└── scripts/                       todo.sh dispatcher + per-action scripts + localize.sh
bootstrap.sh                       install + uninstall (auto-detects local clone)
bootstrap.ps1                      thin trampoline for PowerShell one-liner; shells out to bootstrap.sh
.claude/{memory,todos}/            gitkeep only; contents per-machine
```

`bootstrap` walks `plugins/<name>/` and copies into `~/.claude/scripts/<name>/`, `~/.claude/skills/`, etc. Skills detect plugin vs. manual install via `$env:CLAUDE_PLUGIN_ROOT`.

## Backlog

Dogfoods its own todo tool at `.claude/todos/*.md` (gitignored, per-machine).

- **Use the dispatcher**, never `Read` the .md files directly: `todo list`, `todo show <id>`, `todo done <id>`.
- Commits with `closes #N` / `fixes #N` / `done #N` auto-close those todos (case-insensitive, multiple per commit OK). `post-rewrite` reopens if the closing commit becomes unreachable; manual `git update-ref` won't fire it — reopen by hand.

## Rules

- Don't commit unless explicitly asked.
- After editing under `plugins/*/`, run `./bootstrap.sh` to sync changes to `~/.claude/`. Skip if you only use the marketplace install — Claude Code reloads plugin files on session start.
- Lint runs in CI (`.github/workflows/lint.yml`).
