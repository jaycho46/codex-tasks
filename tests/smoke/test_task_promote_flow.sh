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

"$CLI" --repo "$REPO" task init >/dev/null

BASE_BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD)"

OUT_NEW="$("$CLI" --repo "$REPO" task new 701 --branch "$BASE_BRANCH" "Promote happy path")"
echo "$OUT_NEW"
echo "$OUT_NEW" | grep -q "Added task to TODO board: 701"
grep -q "| 701 | $BASE_BRANCH | Promote happy path | - |  | PLAN |" "$REPO/.codex-tasks/planning/TODO.md"

OUT_READY_PLAN="$("$CLI" --repo "$REPO" run start --dry-run --trigger smoke-promote-plan --max-start 0)"
echo "$OUT_READY_PLAN"
echo "$OUT_READY_PLAN" | grep -q "Started tasks: 0"
if echo "$OUT_READY_PLAN" | grep -q "\[DRY-RUN\].*701"; then
  echo "PLAN task must not be scheduled before promote"
  exit 1
fi

OUT_PROMOTE="$("$CLI" --repo "$REPO" task promote 701 --branch "$BASE_BRANCH")"
echo "$OUT_PROMOTE"
echo "$OUT_PROMOTE" | grep -q "Promoted task: task=701 branch=$BASE_BRANCH status=TODO"
grep -q "| 701 | $BASE_BRANCH | Promote happy path | - |  | TODO |" "$REPO/.codex-tasks/planning/TODO.md"

OUT_READY_TODO="$("$CLI" --repo "$REPO" run start --dry-run --trigger smoke-promote-ready --max-start 0)"
echo "$OUT_READY_TODO"
echo "$OUT_READY_TODO" | grep -q "\[DRY-RUN\].*701"
echo "$OUT_READY_TODO" | grep -q "Started tasks: 1"

OUT_NEW_INVALID="$("$CLI" --repo "$REPO" task new 702 --branch "$BASE_BRANCH" "Promote invalid spec path")"
echo "$OUT_NEW_INVALID"
echo "$OUT_NEW_INVALID" | grep -q "Added task to TODO board: 702"

SPEC_FILE="$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/702.md"
cat > "$SPEC_FILE" <<'EOF'
# Task Spec: 702

## Goal
Goal text

## In Scope
- scope item
EOF

PROMOTE_BAD_OUT="$TMP_DIR/promote-invalid.out"
if "$CLI" --repo "$REPO" task promote 702 --branch "$BASE_BRANCH" >"$PROMOTE_BAD_OUT" 2>&1; then
  echo "promote must fail when spec is invalid"
  cat "$PROMOTE_BAD_OUT"
  exit 1
fi
cat "$PROMOTE_BAD_OUT"
grep -q "invalid_task_spec" "$PROMOTE_BAD_OUT"
grep -q "| 702 | $BASE_BRANCH | Promote invalid spec path | - |  | PLAN |" "$REPO/.codex-tasks/planning/TODO.md"

echo "task promote flow smoke test passed"
