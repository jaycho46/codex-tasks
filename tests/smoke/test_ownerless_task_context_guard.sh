#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
STATE_DIR="$REPO/.codex-tasks"
WT_ROOT="$TMP_DIR/repo-worktrees"
LOCK_101="$STATE_DIR/locks/task-101.lock"

mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b main
mkdir -p "$REPO/.codex-tasks/planning/specs"

echo "# Ownerless context guard" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: init"

"$CLI" --repo "$REPO" task init >/dev/null

cat > "$REPO/.codex-tasks/planning/TODO.md" <<'EOF'
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| 101 |  | Context guard task A | - | | TODO |
| 102 |  | Context guard task B | - | | TODO |
EOF

"$CLI" --repo "$REPO" task scaffold-specs >/dev/null

RUN_OUT="$("$CLI" --repo "$REPO" run start --no-launch --max-start 2 --trigger smoke-ownerless-context-guard)"
echo "$RUN_OUT"
echo "$RUN_OUT" | grep -q "Started tasks: 2"

WT_101="$WT_ROOT/repo-101"
WT_102="$WT_ROOT/repo-102"
if [[ ! -d "$WT_101" || ! -d "$WT_102" ]]; then
  echo "missing task worktrees: $WT_101 $WT_102"
  exit 1
fi
if [[ ! -f "$LOCK_101" ]]; then
  echo "missing lock file for task 101: $LOCK_101"
  exit 1
fi

set +e
BAD_OUT="$("$CLI" --repo "$WT_102" --state-dir "$STATE_DIR" task heartbeat 101 2>&1)"
BAD_RC=$?
set -e
if [[ "$BAD_RC" -eq 0 ]]; then
  echo "cross-worktree heartbeat should fail"
  exit 1
fi
echo "$BAD_OUT"
echo "$BAD_OUT" | grep -q "lock worktree mismatch"

if [[ ! -f "$LOCK_101" ]]; then
  echo "lock should remain after rejected cross-worktree heartbeat"
  exit 1
fi

GOOD_OUT="$("$CLI" --repo "$WT_101" --state-dir "$STATE_DIR" task heartbeat 101)"
echo "$GOOD_OUT"
echo "$GOOD_OUT" | grep -q "Heartbeat updated: task=101"

echo "ownerless task context guard smoke test passed"
