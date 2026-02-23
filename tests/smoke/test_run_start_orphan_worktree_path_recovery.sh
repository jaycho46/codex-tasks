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

cat > "$REPO/README.md" <<'EOF'
# Orphan Worktree Recovery Repo
EOF

git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: initial"

"$CLI" --repo "$REPO" task init

cat > "$REPO/.codex-tasks/planning/TODO.md" <<'EOF'
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| T9-101 |  | Recover orphan worktree path | - | stale dir exists | TODO |
EOF

git -C "$REPO" add -f .codex-tasks/planning/TODO.md
git -C "$REPO" commit -q -m "chore: seed todo"
"$CLI" --repo "$REPO" task scaffold-specs
git -C "$REPO" add -f .codex-tasks/planning/specs
git -C "$REPO" commit -q -m "chore: scaffold task specs"

WT_PARENT="$TMP_DIR/repo-worktrees"
STALE_WT="$WT_PARENT/repo-agenta-t9-101"
mkdir -p "$STALE_WT/.build"
echo "stale" > "$STALE_WT/.build/stale-marker.txt"

RUN_OUT="$("$CLI" --repo "$REPO" run start --no-launch --trigger smoke-orphan-path)"
echo "$RUN_OUT"

echo "$RUN_OUT" | grep -q "Started tasks: 1"
echo "$RUN_OUT" | grep -q "quarantined stale worktree path"

if [[ ! -e "$STALE_WT/.git" ]]; then
  echo "expected fresh worktree at original path after quarantine: $STALE_WT"
  exit 1
fi

ORPHAN_PATH="$(ls -d "${STALE_WT}.orphan-"* 2>/dev/null | head -n1 || true)"
if [[ -z "$ORPHAN_PATH" ]]; then
  echo "expected quarantined orphan path for stale directory"
  exit 1
fi

if [[ ! -f "$ORPHAN_PATH/.build/stale-marker.txt" ]]; then
  echo "expected stale marker in quarantined path: $ORPHAN_PATH"
  exit 1
fi

echo "run start orphan worktree path recovery smoke test passed"
