#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name "Codex Test"
git -C "$REPO" config user.email "codex-test@example.com"
git -C "$REPO" checkout -q -b main

cat > "$REPO/README.md" <<'EOF'
# Merge Worktree Cleanup Repo
EOF
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: initial"

"$CLI" --repo "$REPO" task init >/dev/null

cat > "$REPO/.codex-tasks/planning/TODO.md" <<'EOF'
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| T1-001 | release | First release task | - | keep merge worktree | TODO |
| T1-002 | release | Second release task | - | remove merge worktree | TODO |
EOF

"$CLI" --repo "$REPO" task scaffold-specs >/dev/null

git -C "$REPO" checkout -q -b release
echo "release baseline" > "$REPO/release.txt"
git -C "$REPO" add release.txt
git -C "$REPO" commit -q -m "chore: release baseline"
git -C "$REPO" checkout -q main

MERGE_WT="$TMP_DIR/repo-worktrees/.repo-merge-release"

RUN1="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-merge-worktree-keep --max-start 1)"
echo "$RUN1"
echo "$RUN1" | grep -q "Started tasks: 1"

WT1="$TMP_DIR/repo-worktrees/repo-release-t1-001"
if [[ ! -d "$WT1" ]]; then
  echo "missing first worktree: $WT1"
  exit 1
fi

echo "task 1 deliverable" > "$WT1/task-1.txt"
git -C "$WT1" add task-1.txt
git -C "$WT1" commit -q -m "feat: deliver T1-001"
"$CLI" --repo "$WT1" --state-dir "$REPO/.codex-tasks" task update T1-001 DONE "done t1"

COMPLETE1="$("$CLI" --repo "$WT1" --state-dir "$REPO/.codex-tasks" task complete T1-001 --summary "done t1" --no-run-start)"
echo "$COMPLETE1"
echo "$COMPLETE1" | grep -q "Keeping merge worktree for continuing ready tasks on branch: release"

if [[ ! -d "$MERGE_WT" ]]; then
  echo "merge worktree should be kept while same-branch ready task exists: $MERGE_WT"
  exit 1
fi

if [[ -d "$WT1" ]]; then
  echo "first completed worktree should be removed: $WT1"
  exit 1
fi

RUN2="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-merge-worktree-cleanup --max-start 1)"
echo "$RUN2"
echo "$RUN2" | grep -q "Started tasks: 1"

WT2="$TMP_DIR/repo-worktrees/repo-release-t1-002"
if [[ ! -d "$WT2" ]]; then
  echo "missing second worktree: $WT2"
  exit 1
fi

echo "task 2 deliverable" > "$WT2/task-2.txt"
git -C "$WT2" add task-2.txt
git -C "$WT2" commit -q -m "feat: deliver T1-002"
"$CLI" --repo "$WT2" --state-dir "$REPO/.codex-tasks" task update T1-002 DONE "done t2"

COMPLETE2="$("$CLI" --repo "$WT2" --state-dir "$REPO/.codex-tasks" task complete T1-002 --summary "done t2" --no-run-start)"
echo "$COMPLETE2"
echo "$COMPLETE2" | grep -q "Removed temporary merge worktree:"

if [[ -d "$MERGE_WT" ]]; then
  echo "merge worktree should be removed when same-branch ready task is absent: $MERGE_WT"
  exit 1
fi

if [[ -d "$WT2" ]]; then
  echo "second completed worktree should be removed: $WT2"
  exit 1
fi

echo "task complete merge worktree branch-idle cleanup smoke test passed"
