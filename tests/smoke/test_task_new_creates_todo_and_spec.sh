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
OTHER_BRANCH="feature/x"

OUT_BASE="$("$CLI" --repo "$REPO" task new 320 --branch "$BASE_BRANCH" "Dependency task summary")"
echo "$OUT_BASE"
echo "$OUT_BASE" | grep -q "Added task to TODO board: 320"

TMP_TODO="$TMP_DIR/TODO.done.tmp"
awk -F'|' '
  BEGIN { OFS="|" }
  {
    if ($0 ~ /^\|/) {
      id=$2
      gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id == "320") {
        $(NF-1) = " DONE "
      }
    }
    print
  }
' "$REPO/.codex-tasks/planning/TODO.md" > "$TMP_TODO"
mv "$TMP_TODO" "$REPO/.codex-tasks/planning/TODO.md"

OUT_NEW="$("$CLI" --repo "$REPO" task new 321 --branch "$BASE_BRANCH" --deps 320 "New task summary")"
echo "$OUT_NEW"

echo "$OUT_NEW" | grep -q "Added task to TODO board: 321"
echo "$OUT_NEW" | grep -q "Created task: branch=$BASE_BRANCH id=321"

grep -q "| 321 | $BASE_BRANCH | New task summary | 320 |  | TODO |" "$REPO/.codex-tasks/planning/TODO.md"
test -f "$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/321.md"
grep -q "^## Goal$" "$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/321.md"
grep -q "^## In Scope$" "$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/321.md"
grep -q "^## Acceptance Criteria$" "$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/321.md"
grep -q "^## Subtasks$" "$REPO/.codex-tasks/planning/specs/$BASE_BRANCH/321.md"

OUT_READY="$("$CLI" --repo "$REPO" run start --dry-run --trigger smoke-task-new --max-start 0)"
echo "$OUT_READY"
echo "$OUT_READY" | grep -q "\[DRY-RUN\].*321"
echo "$OUT_READY" | grep -q "Started tasks: 1"

BAD_DEPS_OUT="$TMP_DIR/task-new-bad-deps.out"
if "$CLI" --repo "$REPO" task new 322 --branch "$BASE_BRANCH" --deps invalid-dep "bad deps" >"$BAD_DEPS_OUT" 2>&1; then
  echo "invalid deps task creation should fail"
  cat "$BAD_DEPS_OUT"
  exit 1
fi
grep -q "invalid dependency id" "$BAD_DEPS_OUT"

DUP_OUT="$TMP_DIR/task-new-dup.out"
if "$CLI" --repo "$REPO" task new 321 --branch "$BASE_BRANCH" --deps 320 "duplicate id" >"$DUP_OUT" 2>&1; then
  echo "duplicate task creation should fail"
  cat "$DUP_OUT"
  exit 1
fi
grep -q "Task already exists in TODO board: $BASE_BRANCH:321" "$DUP_OUT"

OUT_DUP_OK="$("$CLI" --repo "$REPO" task new 321 --branch "$OTHER_BRANCH" --deps "$BASE_BRANCH:320" "Same id on another branch")"
echo "$OUT_DUP_OK"
echo "$OUT_DUP_OK" | grep -q "Added task to TODO board: 321"
echo "$OUT_DUP_OK" | grep -q "Created task: branch=$OTHER_BRANCH id=321"
grep -q "| 321 | $OTHER_BRANCH | Same id on another branch | $BASE_BRANCH:320 |  | TODO |" "$REPO/.codex-tasks/planning/TODO.md"
test -f "$REPO/.codex-tasks/planning/specs/$OTHER_BRANCH/321.md"
if grep -q "^owner=" "$REPO/.codex-tasks/planning/specs/$OTHER_BRANCH/321.md"; then
  echo "owner metadata should not be present in scaffolded specs"
  exit 1
fi

echo "task new creates todo and spec smoke test passed"
