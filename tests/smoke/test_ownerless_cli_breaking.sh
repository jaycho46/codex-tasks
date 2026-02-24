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

echo "# Ownerless CLI breaking" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: init"

set +e
LOCK_OUT="$("$CLI" --repo "$REPO" task lock AgentA 101 --branch main 2>&1)"
LOCK_RC=$?
set -e
if [[ "$LOCK_RC" -eq 0 ]]; then
  echo "legacy lock signature should fail"
  exit 1
fi
echo "$LOCK_OUT"
echo "$LOCK_OUT" | grep -q "Unknown task lock option: 101"

set +e
UPDATE_OUT="$("$CLI" --repo "$REPO" task update AgentA 101 IN_PROGRESS "legacy signature" 2>&1)"
UPDATE_RC=$?
set -e
if [[ "$UPDATE_RC" -eq 0 ]]; then
  echo "legacy update signature should fail"
  exit 1
fi
echo "$UPDATE_OUT"
echo "$UPDATE_OUT" | grep -q "Invalid status: 101"

set +e
COMPLETE_OUT="$("$CLI" --repo "$REPO" task complete AgentA 101 2>&1)"
COMPLETE_RC=$?
set -e
if [[ "$COMPLETE_RC" -eq 0 ]]; then
  echo "legacy complete signature should fail"
  exit 1
fi
echo "$COMPLETE_OUT"
echo "$COMPLETE_OUT" | grep -q "Unknown task complete option: 101"

echo "ownerless cli breaking smoke test passed"
