#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
GITDIR="$TMP_DIR/repo.git"

git init -q --separate-git-dir "$GITDIR" "$REPO"
git -C "$REPO" checkout -q -b main
# Mirror absorbed-gitdir/submodule style setup where gitdir knows its worktree.
git -C "$GITDIR" config core.worktree ../repo

cat > "$REPO/README.md" <<'EOF'
# Shared GitDir Complete Flow Repo
EOF
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: init"

cp -R "$ROOT/scripts" "$REPO/"
rm -rf "$REPO/scripts/py/__pycache__"
git -C "$REPO" add scripts
git -C "$REPO" commit -q -m "chore: add codex-tasks scripts"

"$CLI" --repo "$REPO" task init

cat > "$REPO/TODO.md" <<'EOF'
# TODO Board

| ID | Title | Deps | Notes | Status |
|---|---|---|---|---|
| T8-002 | Shared gitdir complete flow | - | primary repo resolution regression | TODO |
EOF
git -C "$REPO" add TODO.md
git -C "$REPO" commit -q -m "chore: seed todo"
"$CLI" --repo "$REPO" task scaffold-specs
git -C "$REPO" add tasks/specs
git -C "$REPO" commit -q -m "chore: scaffold task specs"

RUN_OUT="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-shared-gitdir --max-start 1)"
echo "$RUN_OUT"
echo "$RUN_OUT" | grep -q "Started tasks: 1"

WT="$TMP_DIR/repo-worktrees/repo-agenta-t8-002"
if [[ ! -d "$WT" ]]; then
  echo "missing worktree: $WT"
  exit 1
fi

echo "deliverable" > "$WT/task-output.txt"
git -C "$WT" add task-output.txt
git -C "$WT" commit -q -m "feat: deliver T8-002"
"$CLI" --repo "$WT" --state-dir "$REPO/.state" task update AgentA T8-002 DONE "shared gitdir complete flow"
git -C "$WT" add TODO.md
git -C "$WT" commit -q -m "chore: mark T8-002 done"

COMPLETE_OUT="$("$CLI" --repo "$WT" --state-dir "$REPO/.state" task complete AgentA task-t8-002 T8-002 --summary "shared gitdir complete flow" --no-run-start)"
echo "$COMPLETE_OUT"
echo "$COMPLETE_OUT" | grep -q "Completion prerequisites satisfied"
echo "$COMPLETE_OUT" | grep -q "Merged branch into primary"
echo "$COMPLETE_OUT" | grep -q "Task completion flow finished: task=T8-002"

if echo "$COMPLETE_OUT" | grep -q "already used by worktree"; then
  echo "unexpected branch-lock failure in task complete output"
  exit 1
fi
if echo "$COMPLETE_OUT" | grep -q "Refusing cleanup: worktree path points to primary repo"; then
  echo "primary/worktree self-alias regression detected"
  exit 1
fi

if [[ -d "$WT" ]]; then
  echo "completed worktree should be removed: $WT"
  exit 1
fi

grep -q "| T8-002 | Shared gitdir complete flow | - | primary repo resolution regression | DONE |" "$REPO/TODO.md"

LAST_SUBJECT="$(git -C "$REPO" log -1 --pretty=%s)"
echo "$LAST_SUBJECT" | grep -q "chore: mark T8-002 done"
if git -C "$REPO" log --pretty=%s | grep -q '^task(T8-002):'; then
  echo "task complete should not create auto-commit subject: task(T8-002): ..."
  exit 1
fi

echo "task complete shared-gitdir primary resolution smoke test passed"
