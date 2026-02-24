#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
WORKTREE="$TMP_DIR/worker"
STATE_DIR="$REPO/.codex-tasks"
LOCK_FILE="$STATE_DIR/locks/task-main--101.lock"

mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b main

cat > "$REPO/README.md" <<'EOF'
# Task Lock Atomicity
EOF

git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: init"

"$CLI" --repo "$REPO" task init >/dev/null
git -C "$REPO" worktree add -q -b codex/lock-check "$WORKTREE" main

rm -f "$LOCK_FILE"

for i in $(seq 1 20); do
  (
    out_file="$TMP_DIR/lock-$i.out"
    status_file="$TMP_DIR/lock-$i.status"
    if (
      cd "$WORKTREE" &&
      AI_STATE_DIR="$STATE_DIR" \
      "$CLI" --repo "$WORKTREE" --state-dir "$STATE_DIR" task lock "101" --branch "main"
    ) >"$out_file" 2>&1; then
      echo "ok" > "$status_file"
    else
      echo "fail" > "$status_file"
    fi
  ) &
done
wait

successes=0
for i in $(seq 1 20); do
  status_file="$TMP_DIR/lock-$i.status"
  if [[ ! -f "$status_file" ]]; then
    echo "missing status file: $status_file"
    exit 1
  fi
  if [[ "$(cat "$status_file")" == "ok" ]]; then
    successes=$((successes + 1))
  fi
done

if [[ "$successes" -ne 1 ]]; then
  echo "expected exactly one successful lock acquisition, got $successes"
  for i in $(seq 1 20); do
    echo "--- worker $i ($(cat "$TMP_DIR/lock-$i.status")) ---"
    cat "$TMP_DIR/lock-$i.out"
  done
  exit 1
fi

for i in $(seq 1 20); do
  if [[ "$(cat "$TMP_DIR/lock-$i.status")" != "fail" ]]; then
    continue
  fi
  if ! grep -q "Error: Lock exists:" "$TMP_DIR/lock-$i.out"; then
    echo "unexpected failure output for worker $i"
    cat "$TMP_DIR/lock-$i.out"
    exit 1
  fi
done

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "lock file missing: $LOCK_FILE"
  exit 1
fi

scope="$(awk -F'=' '$1=="scope"{print $2; exit}' "$LOCK_FILE")"
task_id="$(awk -F'=' '$1=="task_id"{print $2; exit}' "$LOCK_FILE")"
created_at="$(awk -F'=' '$1=="created_at"{print $2; exit}' "$LOCK_FILE")"

if [[ -z "$scope" ]]; then
  echo "scope field is empty"
  cat "$LOCK_FILE"
  exit 1
fi
if [[ "$task_id" != "101" ]]; then
  echo "unexpected task_id in lock file: $task_id"
  cat "$LOCK_FILE"
  exit 1
fi
if [[ -z "$created_at" ]]; then
  echo "created_at field is empty"
  cat "$LOCK_FILE"
  exit 1
fi

echo "task lock atomicity smoke test passed"
