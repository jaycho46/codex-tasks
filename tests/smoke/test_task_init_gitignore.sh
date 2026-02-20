#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-tasks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_YES="$TMP_DIR/repo-yes"
mkdir -p "$REPO_YES"
git -C "$REPO_YES" init -q
mkdir -p "$REPO_YES/.codex-tasks/planning/specs"

OUT_YES="$("$CLI" --repo "$REPO_YES" init --gitignore yes)"
echo "$OUT_YES"
echo "$OUT_YES" | grep -q "Added state path to .gitignore: .codex-tasks/"
grep -q '^.codex-tasks/$' "$REPO_YES/.gitignore"

# Re-run should not duplicate entry.
OUT_YES2="$("$CLI" --repo "$REPO_YES" task init --gitignore yes)"
echo "$OUT_YES2"
echo "$OUT_YES2" | grep -q ".gitignore already contains state path: .codex-tasks/"
COUNT="$(grep -c '^.codex-tasks/$' "$REPO_YES/.gitignore" || true)"
if [[ "$COUNT" != "1" ]]; then
  echo "expected one .codex-tasks/ entry, got $COUNT"
  exit 1
fi

REPO_NO="$TMP_DIR/repo-no"
mkdir -p "$REPO_NO"
git -C "$REPO_NO" init -q
mkdir -p "$REPO_NO/.codex-tasks/planning/specs"

OUT_NO="$("$CLI" --repo "$REPO_NO" task init --gitignore no)"
echo "$OUT_NO"
echo "$OUT_NO" | grep -q "Skipped .gitignore update for state path: .codex-tasks/"
if [[ -f "$REPO_NO/.gitignore" ]]; then
  echo ".gitignore should not be created for --gitignore no"
  exit 1
fi

REPO_ASK="$TMP_DIR/repo-ask"
mkdir -p "$REPO_ASK"
git -C "$REPO_ASK" init -q
mkdir -p "$REPO_ASK/.codex-tasks/planning/specs"

# In non-interactive shell, ask mode should not block and should print hint.
OUT_ASK="$("$CLI" --repo "$REPO_ASK" task init)"
echo "$OUT_ASK"
echo "$OUT_ASK" | grep -q "State path missing in .gitignore: .codex-tasks/"
echo "$OUT_ASK" | grep -q "Tip: run 'codex-tasks init --gitignore yes'"

echo "task init gitignore smoke test passed"
