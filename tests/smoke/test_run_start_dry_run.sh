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
| T1-001 |  | Active task | - | | TODO |
| T1-002 |  | Depends on active | T1-001 | | TODO |
| T1-003 |  | Ready task | - | | TODO |
EOF

mkdir -p "$REPO/.codex-tasks/locks" "$REPO/.codex-tasks/orchestrator"
cat > "$REPO/.codex-tasks/locks/app-shell.lock" <<EOF
owner=AgentA
scope=app-shell
task_id=T1-001
worktree=$REPO
EOF
cat > "$REPO/.codex-tasks/orchestrator/worker.pid" <<EOF
owner=AgentA
scope=app-shell
task_id=T1-001
pid=$$
worktree=$REPO
EOF

"$CLI" --repo "$REPO" task scaffold-specs >/dev/null

OUTPUT="$($CLI --repo "$REPO" run start --dry-run --trigger smoke)"

echo "$OUTPUT"

echo "$OUTPUT" | grep -q "Excluded tasks: 2"
echo "$OUTPUT" | grep -q "reason=active_worker"
echo "$OUTPUT" | grep -q "reason=deps_not_ready"
echo "$OUTPUT" | grep -q "\[DRY-RUN\].*T1-003"

echo "smoke test passed"
