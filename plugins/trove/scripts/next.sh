#!/usr/bin/env bash
# Thin alias: `next` == `list --ready` (open tasks with no remaining open blockers).
# Forwards all flags through unchanged.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/list.sh" --ready "$@"
