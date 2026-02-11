#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/scripts/codex-teams"

TMP_DIR="$(mktemp -d)"
REPO="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/fake-bin"

cleanup() {
  if [[ -d "$REPO" ]]; then
    PATH="$FAKE_BIN:$PATH" \
      "$CLI" --repo "$REPO" task stop --all --apply --reason "smoke launch cleanup" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$REPO" "$FAKE_BIN"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b main

cat > "$REPO/README.md" <<'EOF'
# Launch Smoke Repo
EOF
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "chore: init"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "exec" ]] || exit 2
while true; do sleep 5; done
EOF
chmod +x "$FAKE_BIN/codex"

"$CLI" --repo "$REPO" task init

cat > "$REPO/TODO.md" <<'EOF'
# TODO Board

| ID | Title | Owner | Deps | Notes | Status |
|---|---|---|---|---|---|
| T8-001 | Launch worker | AgentA | - | launch smoke | TODO |
EOF
git -C "$REPO" add TODO.md
git -C "$REPO" commit -q -m "chore: seed todo"

RUN_OUT="$(PATH="$FAKE_BIN:$PATH" "$CLI" --repo "$REPO" run start --launch --trigger smoke-launch --max-start 1)"
echo "$RUN_OUT"

echo "$RUN_OUT" | grep -q "Started tasks: 1"
echo "$RUN_OUT" | grep -q "Launched codex worker: task=T8-001"

PID_META="$REPO/.state/orchestrator/t8-001.pid"
if [[ ! -f "$PID_META" ]]; then
  echo "missing pid metadata: $PID_META"
  exit 1
fi

PID="$(awk -F'=' '$1=="pid"{print $2}' "$PID_META" | tr -d '[:space:]')"
if [[ ! "$PID" =~ ^[0-9]+$ ]]; then
  echo "invalid pid in metadata: $PID"
  exit 1
fi

if ! kill -0 "$PID" >/dev/null 2>&1; then
  echo "worker pid is not alive: $PID"
  exit 1
fi

grep -q '^launch_backend=codex_exec$' "$PID_META"
grep -q '^task_id=T8-001$' "$PID_META"

LOG_FILE="$(awk -F'=' '$1=="log_file"{print $2}' "$PID_META" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
  echo "missing launch log file: $LOG_FILE"
  exit 1
fi

PS_CMD="$(ps -p "$PID" -o command= | tr -d '\n')"
echo "$PS_CMD" | grep -q "$FAKE_BIN/codex"

PATH="$FAKE_BIN:$PATH" \
  "$CLI" --repo "$REPO" task stop --all --apply --reason "smoke launch cleanup"

sleep 1
if kill -0 "$PID" >/dev/null 2>&1; then
  echo "worker pid still alive after stop: $PID"
  exit 1
fi

echo "run start launch codex exec smoke test passed"
