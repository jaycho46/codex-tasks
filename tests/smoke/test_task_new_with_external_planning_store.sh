#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
mkdir -p "$REPO/.codex-tasks/planning/specs"

PLANNING_ROOT="$TMP_DIR/planning-store"
TODO_FILE="$PLANNING_ROOT/TODO.md"
SPEC_DIR="$PLANNING_ROOT/specs"
STATE_DIR="$PLANNING_ROOT/state"
WORKTREE_PARENT="$PLANNING_ROOT/worktrees"
CONFIG_FILE="$TMP_DIR/orchestrator.toml"

cat > "$CONFIG_FILE" <<EOF
[repo]
todo_file = "$TODO_FILE"
spec_dir = "$SPEC_DIR"
state_dir = "$STATE_DIR"
worktree_parent = "$WORKTREE_PARENT"
EOF

OUT_INIT="$("$CLI" --repo "$REPO" --config "$CONFIG_FILE" task init --gitignore no)"
echo "$OUT_INIT"
echo "$OUT_INIT" | grep -q "State dir is outside repository; skip .gitignore update:"

BASE_BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD)"
OUT_NEW="$("$CLI" --repo "$REPO" --config "$CONFIG_FILE" task new 901 --branch "$BASE_BRANCH" --multi-agent "External planning task")"
echo "$OUT_NEW"
echo "$OUT_NEW" | grep -q "Added task to TODO board: 901"
echo "$OUT_NEW" | grep -q "Created task: branch=$BASE_BRANCH id=901"

test -f "$TODO_FILE"
grep -q "| 901 | $BASE_BRANCH | External planning task | - |  | TODO |" "$TODO_FILE"

SPEC_FILE="$SPEC_DIR/$BASE_BRANCH/901.md"
test -f "$SPEC_FILE"
grep -q "^## Goal$" "$SPEC_FILE"
grep -q "^## In Scope$" "$SPEC_FILE"
grep -q "^## Acceptance Criteria$" "$SPEC_FILE"
grep -q "^## Subtasks$" "$SPEC_FILE"
if grep -q "^owner=" "$SPEC_FILE"; then
  echo "owner metadata should not be present in scaffolded spec"
  exit 1
fi

OUT_READY="$("$CLI" --repo "$REPO" --config "$CONFIG_FILE" run start --dry-run --trigger smoke-external-planning --max-start 0)"
echo "$OUT_READY"
echo "$OUT_READY" | grep -q "\[DRY-RUN\].*901"
echo "$OUT_READY" | grep -q "Started tasks: 1"

if [[ -f "$REPO/TODO.md" ]]; then
  echo "repo-local TODO.md should not be created when todo_file is external"
  exit 1
fi

if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "repository should remain clean for external planning store"
  git -C "$REPO" status --short
  exit 1
fi

echo "task new external planning store smoke test passed"
