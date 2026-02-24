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
git -C "$REPO" checkout -q -b main

echo "# Scenario Repo" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: initial"

$CLI --repo "$REPO" task init

cat > "$REPO/.codex-tasks/planning/TODO.md" <<'EOF'
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| T1-001 |  | App shell bootstrap | - | seed | TODO |
| T1-002 |  | Domain core service | T1-001 | wait T1-001 | TODO |
EOF

git -C "$REPO" add -f .codex-tasks/planning/TODO.md
git -C "$REPO" commit -q -m "chore: seed todo"
"$CLI" --repo "$REPO" task scaffold-specs
git -C "$REPO" add -f .codex-tasks/planning/specs
git -C "$REPO" commit -q -m "chore: scaffold task specs"

# First scheduler run: only T1-001 should start.
RUN1="$($CLI --repo "$REPO" run start --no-launch --trigger smoke-after-done-initial)"
echo "$RUN1"

echo "$RUN1" | grep -q "Started tasks: 1"
echo "$RUN1" | grep -q "T1-002 .*reason=deps_not_ready"

WT_A="$TMP_DIR/repo-worktrees/repo-t1-001"
if [[ ! -d "$WT_A" ]]; then
  echo "missing task worktree: $WT_A"
  exit 1
fi

# Simulate task completion from agent worktree context.
$CLI --repo "$WT_A" --state-dir "$REPO/.codex-tasks" task update T1-001 DONE "done in smoke"
$CLI --repo "$WT_A" --state-dir "$REPO/.codex-tasks" task unlock T1-001

# Source-of-truth for scheduler is the primary repo TODO board.
# Simulate merge/finish by reflecting T1-001 DONE on main TODO.
TMP_TODO="$TMP_DIR/TODO.main.tmp"
awk -F'|' '
  BEGIN { OFS="|" }
  {
    if ($0 ~ /^\|/) {
      id=$2
      gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id == "T1-001") {
        $(NF-1) = " DONE "
      }
    }
    print
  }
' "$REPO/.codex-tasks/planning/TODO.md" > "$TMP_TODO"
mv "$TMP_TODO" "$REPO/.codex-tasks/planning/TODO.md"

# Second scheduler run: dependent T1-002 should start now.
RUN2="$($CLI --repo "$REPO" run start --no-launch --trigger smoke-after-done-second)"
echo "$RUN2"

echo "$RUN2" | grep -q "Started tasks: 1"
echo "$RUN2" | grep -q "T1-002"

grep -q "| T1-001 |  | App shell bootstrap | - | seed | DONE |" "$REPO/.codex-tasks/planning/TODO.md"
grep -q "| T1-002 |  | Domain core service | T1-001 | wait T1-001 | IN_PROGRESS |" "$REPO/.codex-tasks/planning/TODO.md"

STATUS_OUT="$($CLI --repo "$REPO" status --trigger smoke-after-done-second)"
echo "$STATUS_OUT"

echo "$STATUS_OUT" | grep -q "Runtime: total=1 active=1 stale=0"
echo "$STATUS_OUT" | grep -q "\[LOCK\] scope=task-t1-002 task=T1-002"

echo "run start after done smoke test passed"
