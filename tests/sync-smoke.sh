#!/usr/bin/env bash
# Sync smoke test: simulate two clones racing on the same todo id,
# verify that `todo sync` auto-renumbers the local one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO="$REPO_ROOT/plugins/trove/scripts/todo.sh"
SYNC="$REPO_ROOT/plugins/trove/scripts/sync.sh"

TMP="$(mktemp -d -t trove-sync-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/alice"
git clone -q "$TMP/origin.git" "$TMP/bob"

for clone in alice bob; do
    git -C "$TMP/$clone" config user.email "$clone@test"
    git -C "$TMP/$clone" config user.name "$clone"
done

# Seed: alice creates a todo and pushes.
mkdir -p "$TMP/alice/.claude/todos"
bash "$TODO" add "Alice's task" --dir "$TMP/alice/.claude/todos" >/dev/null
git -C "$TMP/alice" add .
git -C "$TMP/alice" commit -qm "alice #1"
git -C "$TMP/alice" push -q origin HEAD:master 2>&1 | tail -1

# Pull master ref into bob.
git -C "$TMP/bob" fetch -q origin master:master 2>/dev/null || true

# Bob creates a todo locally on his master (same id as alice's, by coincidence).
mkdir -p "$TMP/bob/.claude/todos"
bash "$TODO" add "Bob's task" --dir "$TMP/bob/.claude/todos" >/dev/null
git -C "$TMP/bob" checkout -q -B master 2>/dev/null || git -C "$TMP/bob" checkout -q master
git -C "$TMP/bob" add .
git -C "$TMP/bob" commit -qm "bob #1"

# Bob syncs — should auto-renumber his local #1 to #2.
echo "=== Bob runs sync (expect renumber) ==="
(
    cd "$TMP/bob"
    bash "$SYNC" --no-push 2>&1 | tail -10
)

# Verify:
[[ -f "$TMP/bob/.claude/todos/1.md" ]] || { echo "FAIL: 1.md missing"; exit 1; }
[[ -f "$TMP/bob/.claude/todos/2.md" ]] || { echo "FAIL: 2.md missing (renumber didn't happen)"; exit 1; }

# #1 should be Alice's task (upstream won).
grep -q "Alice's task" "$TMP/bob/.claude/todos/1.md" || { echo "FAIL: #1 should be Alice's"; exit 1; }
echo "  ok: #1 retained Alice's content"

# #2 should be Bob's task with id field updated.
grep -q "Bob's task" "$TMP/bob/.claude/todos/2.md" || { echo "FAIL: #2 should be Bob's"; exit 1; }
grep -q "^id: 2$" "$TMP/bob/.claude/todos/2.md" || { echo "FAIL: #2 id field not updated"; exit 1; }
echo "  ok: #2 has Bob's content with id: 2"

echo
echo "Sync auto-renumber smoke passed."
