#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b main

cat > "$REPO/README.md" <<'EOF'
# Base Branch Sticky Repo
EOF
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: initial"

"$CLI" --repo "$REPO" task init

# Keep orchestration config in local .state (untracked), which is common in real runs.
cat > "$REPO/.state/orchestrator.toml" <<'EOF'
[repo]
base_branch = "release"
EOF

cat > "$REPO/TODO.md" <<'EOF'
# TODO Board

| ID | Title | Deps | Notes | Status |
|---|---|---|---|---|
| T1-001 | Respect configured base branch | - | seed | TODO |
EOF
git -C "$REPO" add TODO.md
git -C "$REPO" commit -q -m "chore: seed todo"
"$CLI" --repo "$REPO" task scaffold-specs
git -C "$REPO" add tasks/specs
git -C "$REPO" commit -q -m "chore: scaffold task specs"

git -C "$REPO" checkout -q -b release
echo "release baseline" > "$REPO/release-baseline.txt"
git -C "$REPO" add release-baseline.txt
git -C "$REPO" commit -q -m "chore: release baseline"

# Simulate user moving primary repo HEAD away from configured base branch.
git -C "$REPO" checkout -q main

RUN_OUT="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-base-branch-sticky --max-start 1)"
echo "$RUN_OUT"
echo "$RUN_OUT" | grep -q "Started tasks: 1"

WT="$TMP_DIR/repo-worktrees/repo-agenta-t1-001"
if [[ ! -d "$WT" ]]; then
  echo "missing worktree: $WT"
  exit 1
fi

BRANCH_NAME="codex/agenta-t1-001"
TASK_TIP="$(git -C "$REPO" rev-parse "$BRANCH_NAME")"
RELEASE_SHA="$(git -C "$REPO" rev-parse release)"
BRANCH_BASE_SHA="$(git -C "$REPO" merge-base "$BRANCH_NAME" release)"
if [[ "$BRANCH_BASE_SHA" != "$RELEASE_SHA" ]]; then
  echo "worktree branch should be created from configured base branch release"
  exit 1
fi

echo "task deliverable" > "$WT/task-output.txt"
git -C "$WT" add task-output.txt
git -C "$WT" commit -q -m "feat: deliver T1-001"
"$CLI" --repo "$WT" --state-dir "$REPO/.state" task update AgentA T1-001 DONE "done on release flow"
git -C "$WT" add TODO.md
git -C "$WT" commit -q -m "chore: mark T1-001 done"

# User can still switch away before completion; completion must honor configured base branch.
git -C "$REPO" checkout -q main

COMPLETE_OUT="$("$CLI" --repo "$WT" --state-dir "$REPO/.state" task complete AgentA task-t1-001 T1-001 --summary "done on release flow" --no-run-start)"
echo "$COMPLETE_OUT"
if ! echo "$COMPLETE_OUT" | grep -q -- "-> release"; then
  echo "task complete should merge into configured base branch release"
  exit 1
fi

if ! git -C "$REPO" merge-base --is-ancestor "$TASK_TIP" release; then
  echo "completion tip should be merged into release"
  exit 1
fi
if git -C "$REPO" merge-base --is-ancestor "$TASK_TIP" main; then
  echo "completion tip should not be merged into main when base branch is release"
  exit 1
fi

if [[ -d "$WT" ]]; then
  echo "completed worktree should be removed: $WT"
  exit 1
fi

echo "task complete respects configured base branch smoke test passed"
