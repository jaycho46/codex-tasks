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

echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"

"$CLI" --repo "$REPO" task init >/dev/null
"$CLI" --repo "$REPO" task new 111 --branch release/9.9 "Create missing branch from base" >/dev/null

if git -C "$REPO" rev-parse --verify release/9.9 >/dev/null 2>&1; then
  echo "release/9.9 must not exist before scheduler start"
  exit 1
fi

OUTPUT="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-missing-branch)"
echo "$OUTPUT"

echo "$OUTPUT" | grep -q "Created missing task base branch: release/9.9 (from main)"
echo "$OUTPUT" | grep -q "Started tasks: 1"
git -C "$REPO" rev-parse --verify release/9.9 >/dev/null

MAIN_HEAD="$(git -C "$REPO" rev-parse main)"
RELEASE_HEAD="$(git -C "$REPO" rev-parse release/9.9)"
if [[ "$MAIN_HEAD" != "$RELEASE_HEAD" ]]; then
  echo "release/9.9 must be created from main"
  exit 1
fi

echo "run start creates missing task branch smoke test passed"
