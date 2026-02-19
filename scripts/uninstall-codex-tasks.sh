#!/usr/bin/env bash
set -euo pipefail

DEFAULT_INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/codex-tasks"
DEFAULT_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

INSTALL_ROOT="${CODEX_TASKS_INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT}"
BIN_DIR="${CODEX_TASKS_BIN_DIR:-$DEFAULT_BIN_DIR}"
REMOVE_VERSION=""
REMOVE_ALL=0
DRY_RUN=0
FORCE=0

usage() {
  cat <<'USAGE'
Uninstall codex-tasks.

Usage:
  uninstall-codex-tasks.sh [OPTIONS]

Options:
  --all                 Remove the entire install root (all versions)
  --version <vX.Y.Z>   Remove only the specified version
  --install-root <path> Override the install root directory
  --bin-dir <path>      Override the bin directory for the launcher
  --dry-run             Show what would be removed without deleting anything
  --force               Skip confirmation prompts
  -h, --help            Show this help

Examples:
  uninstall-codex-tasks.sh --all
  uninstall-codex-tasks.sh --version v0.1.1
  uninstall-codex-tasks.sh --all --dry-run

Environment overrides:
  CODEX_TASKS_INSTALL_ROOT
  CODEX_TASKS_BIN_DIR
USAGE
}

log() {
  echo "[uninstall] $*"
}

warn() {
  echo "[uninstall] WARNING: $*" >&2
}

die() {
  echo "[uninstall] ERROR: $*" >&2
  exit 1
}

confirm() {
  if [[ "$FORCE" -eq 1 ]]; then
    return 0
  fi
  local prompt="${1:-Continue?}"
  printf "[uninstall] %s [y/N] " "$prompt"
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

is_semver_tag() {
  [[ "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

remove_path() {
  local target="${1:-}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "(dry-run) Would remove: ${target}"
  else
    rm -rf "$target"
    log "Removed: ${target}"
  fi
}

remove_file() {
  local target="${1:-}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "(dry-run) Would remove: ${target}"
  else
    rm -f "$target"
    log "Removed: ${target}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      REMOVE_ALL=1
      ;;
    --version)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --version"
      REMOVE_VERSION="$1"
      ;;
    --install-root)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --install-root"
      INSTALL_ROOT="$1"
      ;;
    --bin-dir)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --bin-dir"
      BIN_DIR="$1"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift || true
done

if [[ "$REMOVE_ALL" -eq 0 && -z "$REMOVE_VERSION" ]]; then
  die "Specify --all to remove everything, or --version <vX.Y.Z> to remove a single version."
fi

if [[ -n "$REMOVE_VERSION" && "$REMOVE_VERSION" != v* ]]; then
  REMOVE_VERSION="v${REMOVE_VERSION}"
fi

if [[ -n "$REMOVE_VERSION" ]]; then
  is_semver_tag "$REMOVE_VERSION" || die "Invalid --version value: ${REMOVE_VERSION}"
fi

# --- Single version removal ---
if [[ -n "$REMOVE_VERSION" && "$REMOVE_ALL" -eq 0 ]]; then
  version_dir="${INSTALL_ROOT}/${REMOVE_VERSION}"
  if [[ ! -d "$version_dir" ]]; then
    die "Version not found: ${version_dir}"
  fi

  log "Will remove version ${REMOVE_VERSION} from ${INSTALL_ROOT}"
  confirm "Remove ${version_dir}?" || { log "Aborted."; exit 0; }

  remove_path "$version_dir"

  current_link="${INSTALL_ROOT}/current"
  if [[ -L "$current_link" ]]; then
    current_target="$(readlink "$current_link")"
    if [[ "$current_target" == "$version_dir" || "$current_target" == "${version_dir}/" ]]; then
      remove_file "$current_link"
      warn "'current' symlink pointed to the removed version and has been removed."
      warn "The launcher at ${BIN_DIR}/codex-tasks may no longer work."

      remaining=()
      for d in "${INSTALL_ROOT}"/v*/; do
        [[ -d "$d" ]] && remaining+=("$d")
      done
      if [[ ${#remaining[@]} -gt 0 ]]; then
        latest="${remaining[-1]}"
        latest="${latest%/}"
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "(dry-run) Would re-link current -> ${latest}"
        else
          ln -sfn "$latest" "$current_link"
          log "Re-linked current -> ${latest}"
        fi
      fi
    fi
  fi

  remaining_count=0
  for d in "${INSTALL_ROOT}"/v*/; do
    [[ -d "$d" ]] && ((remaining_count++)) || true
  done

  if [[ "$remaining_count" -eq 0 ]]; then
    log "No versions remain. Consider running with --all to clean up completely."
  else
    log "${remaining_count} version(s) still installed."
  fi

  exit 0
fi

# --- Full removal ---
launcher_path="${BIN_DIR}/codex-tasks"

log "This will remove:"
[[ -d "$INSTALL_ROOT" ]] && log "  Install root: ${INSTALL_ROOT}"
[[ -e "$launcher_path" ]] && log "  Launcher:     ${launcher_path}"

if [[ ! -d "$INSTALL_ROOT" && ! -e "$launcher_path" ]]; then
  log "Nothing to remove. codex-tasks does not appear to be installed."
  exit 0
fi

confirm "Remove all codex-tasks files?" || { log "Aborted."; exit 0; }

if [[ -d "$INSTALL_ROOT" ]]; then
  remove_path "$INSTALL_ROOT"
fi

if [[ -e "$launcher_path" ]]; then
  remove_file "$launcher_path"
fi

log "codex-tasks has been uninstalled."
