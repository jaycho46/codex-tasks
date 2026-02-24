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

cat > "$REPO/.codex-tasks/planning/TODO.md" <<'EOF'
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| 101 | main | Legacy owner guard | - | | TODO |
EOF

"$CLI" --repo "$REPO" task init >/dev/null
"$CLI" --repo "$REPO" task scaffold-specs --task 101 --branch main >/dev/null

mkdir -p "$REPO/.codex-tasks/locks" "$REPO/.codex-tasks/orchestrator"
cat > "$REPO/.codex-tasks/locks/task-main--101.lock" <<EOF
owner=AgentA
scope=task-main--101
task_id=101
task_branch=main
task_key=main::101
worktree=$TMP_DIR/legacy-worktree
created_at=2026-01-01T00:00:00Z
heartbeat_at=2026-01-01T00:00:00Z
EOF
cat > "$REPO/.codex-tasks/orchestrator/task-main--101.pid" <<EOF
owner=AgentA
scope=task-main--101
task_id=101
task_branch=main
task_key=main::101
pid=99999999
worktree=$TMP_DIR/legacy-worktree
started_at=2026-01-01T00:00:00Z
launch_backend=tmux
tmux_session=N/A
launch_label=N/A
log_file=/tmp/legacy.log
EOF

set +e
RUN_OUT="$("$CLI" --repo "$REPO" run start --dry-run --trigger smoke-ownerless-guard 2>&1)"
RUN_RC=$?
set -e

if [[ "$RUN_RC" -eq 0 ]]; then
  echo "run start should fail when legacy owner metadata exists"
  exit 1
fi

echo "$RUN_OUT"
echo "$RUN_OUT" | grep -q "Legacy owner metadata detected"

STOP_OUT="$("$CLI" --repo "$REPO" task stop --all --apply --reason "ownerless migration cleanup")"
echo "$STOP_OUT"
echo "$STOP_OUT" | grep -q "Summary: success="

if [[ -f "$REPO/.codex-tasks/locks/task-main--101.lock" ]]; then
  echo "legacy lock file should be removed by stop --all --apply"
  exit 1
fi
if [[ -f "$REPO/.codex-tasks/orchestrator/task-main--101.pid" ]]; then
  echo "legacy pid file should be removed by stop --all --apply"
  exit 1
fi

RUN2_OUT="$("$CLI" --repo "$REPO" run start --dry-run --trigger smoke-ownerless-post-cleanup)"
echo "$RUN2_OUT"
echo "$RUN2_OUT" | grep -q "Started tasks: 1"
echo "$RUN2_OUT" | grep -q "\[DRY-RUN\].*worktree start 101"

echo "ownerless upgrade guard smoke test passed"
