#!/usr/bin/env bash
# End-to-end smoke test: exercise every todo action against a tempdir.
# Run from the repo root: bash tests/smoke.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO="$REPO_ROOT/plugins/trove/scripts/todo.sh"
LOCALIZE="$REPO_ROOT/plugins/trove/scripts/localize.sh"

TMP="$(mktemp -d -t trove-smoke-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

TODOS="$TMP/.claude/todos"
mkdir -p "$TODOS"

DIR=("--dir" "$TODOS")

assert() {
    local what="$1" actual="$2" expected="$3"
    if [[ "$actual" != *"$expected"* ]]; then
        echo "FAIL: $what"
        echo "  expected substring: $expected"
        echo "  actual: $actual"
        exit 1
    fi
    echo "  ok: $what"
}

echo "=== empty-backlog add (v1.0.1 regression guard) ==="
out="$(bash "$TODO" add "First task" "${DIR[@]}")"
assert "add into empty backlog" "$out" "#1 added"

echo
echo "=== add with priority + tags ==="
out="$(bash "$TODO" add "High-prio" -p high -t infra docs "${DIR[@]}")"
assert "add high-prio with tags" "$out" "#2 added"

echo
echo "=== add with blocker ==="
out="$(bash "$TODO" add "Third" -b 1 "${DIR[@]}")"
assert "add with -b 1" "$out" "blocked by #1"

echo
echo "=== add with due date ==="
out="$(bash "$TODO" add "Future" -d 2026-12-31 "${DIR[@]}")"
assert "add with --due" "$out" "#4 added"

echo
echo "=== list (default = open) ==="
out="$(bash "$TODO" list "${DIR[@]}")"
assert "list shows #1" "$out" "First task"
assert "list shows #3 as blocked" "$out" "blocked by #1"

echo
echo "=== show #2 ==="
out="$(bash "$TODO" show 2 "${DIR[@]}")"
assert "show has priority" "$out" "priority: high"
assert "show has tags" "$out" "infra"
assert "show has empty due" "$out" "due:"

echo
echo "=== done #1 (should unblock #3) ==="
out="$(bash "$TODO" "done" 1 "${DIR[@]}")"
assert "done #1" "$out" "#1 done"
assert "done reports unblocked #3" "$out" "now unblocked: #3"

echo
echo "=== priority mutation ==="
bash "$TODO" priority 2 low "${DIR[@]}" >/dev/null
out="$(bash "$TODO" show 2 "${DIR[@]}")"
assert "priority -> low" "$out" "priority: low"

echo
echo "=== tag add / remove ==="
bash "$TODO" tag 2 add validate "${DIR[@]}" >/dev/null
out="$(bash "$TODO" show 2 "${DIR[@]}")"
assert "tag add" "$out" "validate"
bash "$TODO" tag 2 remove infra "${DIR[@]}" >/dev/null
out="$(bash "$TODO" show 2 "${DIR[@]}")"
if [[ "$out" == *"infra"* ]]; then echo "FAIL: tag remove"; exit 1; fi
echo "  ok: tag remove"

echo
echo "=== due set / clear ==="
bash "$TODO" due 2 2026-06-01 "${DIR[@]}" >/dev/null
out="$(bash "$TODO" show 2 "${DIR[@]}")"
assert "due set" "$out" "due: 2026-06-01"
bash "$TODO" due 2 clear "${DIR[@]}" >/dev/null

echo
echo "=== list --due-before filter ==="
out="$(bash "$TODO" list --due-before 2027-01-01 "${DIR[@]}")"
assert "due-before matches #4" "$out" "Future"

echo
echo "=== block / unblock ==="
bash "$TODO" block 3 2 "${DIR[@]}" >/dev/null
out="$(bash "$TODO" list "${DIR[@]}")"
assert "block adds dependency" "$out" "blocked by #2"
bash "$TODO" unblock 3 2 "${DIR[@]}" >/dev/null

echo
echo "=== reopen ==="
bash "$TODO" reopen 1 "${DIR[@]}" >/dev/null
out="$(bash "$TODO" list -s open "${DIR[@]}")"
assert "reopen restores #1 to open" "$out" "First task"

echo
echo "=== rm ==="
bash "$TODO" rm 1 "${DIR[@]}" >/dev/null
out="$(bash "$TODO" list -s all "${DIR[@]}")"
if [[ "$out" == *"First task"* ]]; then echo "FAIL: rm did not delete"; exit 1; fi
echo "  ok: rm removes #1"

echo
echo "=== verify --fix ==="
bash "$TODO" verify --fix "${DIR[@]}" >/dev/null
echo "  ok: verify ran"

echo
echo "=== where ==="
out="$(bash "$TODO" where "${DIR[@]}")"
assert "where prints dir" "$out" ".claude/todos"

echo
echo "=== localize status (no project — read-only path) ==="
bash "$LOCALIZE" todos status --project-path "$TMP" >/dev/null
echo "  ok: localize status"

echo
echo "All smoke tests passed."
