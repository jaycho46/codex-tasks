#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize() {
  local value="${1:-}"
  echo "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

normalize_scope() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    echo ""
    return
  fi
  echo "$raw" | sed -E 's/[^A-Za-z0-9._-]+/_/g'
}

read_field() {
  local file="${1:-}"
  local key="${2:-}"
  awk -F'=' -v k="$key" '$1 == k {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$file"
}

normalize_agent_name() {
  local agent="${1:-}"
  echo "$agent" | sed -E 's/[[:space:]]+//g'
}

ensure_updates_file() {
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$UPDATES_FILE" ]]; then
    cat > "$UPDATES_FILE" <<'EOF'
# Latest Updates

| Timestamp (UTC) | Agent | Task | Status | Summary |
|---|---|---|---|---|
EOF
  fi
}

append_update_log() {
  local agent="${1:-}"
  local task_id="${2:-}"
  local status="${3:-}"
  local summary="${4:-}"
  local esc_summary

  ensure_updates_file
  esc_summary="$(echo "$summary" | sed 's/|/\\|/g')"
  echo "| $(timestamp_utc) | $agent | $task_id | $status | $esc_summary |" >> "$UPDATES_FILE"
}

is_valid_status() {
  local status="${1:-}"
  case "$status" in
    TODO|IN_PROGRESS|BLOCKED|DONE) return 0 ;;
    *) return 1 ;;
  esac
}
