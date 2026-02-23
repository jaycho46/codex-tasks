#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="jaycho46/codex-tasks"
DEFAULT_VERSION="latest"
DEFAULT_INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/codex-tasks"
DEFAULT_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DEFAULT_VERIFY_CHECKSUM="1"
DEFAULT_VERIFY_SIGNATURE="0"
DEFAULT_AUTO_UPDATE="1"
DEFAULT_AUTO_UPDATE_INTERVAL_SECONDS="86400"
DEFAULT_AUTO_UPDATE_SKILL="1"

REPO="${CODEX_TASKS_REPO:-$DEFAULT_REPO}"
VERSION="${CODEX_TASKS_VERSION:-$DEFAULT_VERSION}"
INSTALL_ROOT="${CODEX_TASKS_INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT}"
BIN_DIR="${CODEX_TASKS_BIN_DIR:-$DEFAULT_BIN_DIR}"
VERIFY_CHECKSUM="${CODEX_TASKS_VERIFY_CHECKSUM:-$DEFAULT_VERIFY_CHECKSUM}"
VERIFY_SIGNATURE="${CODEX_TASKS_VERIFY_SIGNATURE:-$DEFAULT_VERIFY_SIGNATURE}"
AUTO_UPDATE_ENABLED="${CODEX_TASKS_AUTO_UPDATE:-$DEFAULT_AUTO_UPDATE}"
AUTO_UPDATE_INTERVAL_SECONDS="${CODEX_TASKS_AUTO_UPDATE_INTERVAL_SECONDS:-$DEFAULT_AUTO_UPDATE_INTERVAL_SECONDS}"
AUTO_UPDATE_SKILL_ENABLED="${CODEX_TASKS_AUTO_UPDATE_SKILL:-$DEFAULT_AUTO_UPDATE_SKILL}"
FORCE=0

usage() {
  cat <<'USAGE'
Install codex-tasks from GitHub releases.

Usage:
  install-codex-tasks.sh [--repo <owner/repo>] [--version <vX.Y.Z|latest>] [--install-root <path>] [--bin-dir <path>] [--force] [--skip-checksum] [--verify-signature] [--auto-update <on|off>] [--auto-update-interval <seconds>] [--auto-update-skill <on|off>]

Examples:
  install-codex-tasks.sh
  install-codex-tasks.sh --version v0.1.1
  install-codex-tasks.sh --version v0.1.1 --verify-signature
  install-codex-tasks.sh --repo acme/codex-tasks --bin-dir "$HOME/.local/bin"

Environment overrides:
  CODEX_TASKS_REPO
  CODEX_TASKS_VERSION
  CODEX_TASKS_INSTALL_ROOT
  CODEX_TASKS_BIN_DIR
  CODEX_TASKS_VERIFY_CHECKSUM (1/0, true/false)
  CODEX_TASKS_VERIFY_SIGNATURE (1/0, true/false)
  CODEX_TASKS_AUTO_UPDATE (1/0, true/false)
  CODEX_TASKS_AUTO_UPDATE_INTERVAL_SECONDS
  CODEX_TASKS_AUTO_UPDATE_SKILL (1/0, true/false)
USAGE
}

log() {
  echo "[install] $*"
}

warn() {
  echo "[install] WARNING: $*" >&2
}

die() {
  echo "[install] ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

to_lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

normalize_bool() {
  local raw="${1:-}"
  local lower
  lower="$(to_lower "$raw")"
  case "$lower" in
    1|true|yes|on) echo 1 ;;
    0|false|no|off) echo 0 ;;
    *)
      die "Invalid boolean value: ${raw}"
      ;;
  esac
}

require_positive_int() {
  local name="${1:-value}"
  local raw="${2:-}"
  [[ "$raw" =~ ^[0-9]+$ ]] || die "Invalid ${name}: ${raw}"
  [[ "$raw" -gt 0 ]] || die "Invalid ${name}: ${raw}"
}

is_semver_tag() {
  [[ "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

sha256_of_file() {
  local file_path="${1:-}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file_path" | awk '{print $2}'
    return 0
  fi
  die "Unable to compute sha256. Install sha256sum, shasum, or openssl."
}

resolve_latest_tag() {
  local repo="${1:-}"
  local latest_url tag

  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")" \
    || die "Unable to resolve latest release for ${repo}"

  tag="${latest_url##*/}"
  is_semver_tag "$tag" || die "Invalid latest release tag: ${tag}"
  echo "$tag"
}

download_file() {
  local url="${1:-}"
  local output_path="${2:-}"
  log "Downloading ${url}"
  curl -fsSL "$url" -o "$output_path" || die "Failed to download: ${url}"
}

release_asset_url() {
  local repo="${1:-}"
  local tag="${2:-}"
  local asset="${3:-}"
  echo "https://github.com/${repo}/releases/download/${tag}/${asset}"
}

verify_tarball_checksum() {
  local checksum_file="${1:-}"
  local tarball_url="${2:-}"
  local archive_path="${3:-}"
  local expected actual

  expected="$(awk -v target="$tarball_url" '$2 == target {print $1; exit}' "$checksum_file")"
  if [[ -z "$expected" ]]; then
    expected="$(awk '$2 == "source.tar.gz" {print $1; exit}' "$checksum_file")"
  fi
  [[ -n "$expected" ]] || die "No matching checksum entry found for source tarball."

  actual="$(sha256_of_file "$archive_path")"
  [[ "$actual" == "$expected" ]] || die "Checksum mismatch for source tarball. expected=${expected} actual=${actual}"
}

verify_checksums_signature() {
  local repo="${1:-}"
  local checksum_file="${2:-}"
  local sig_file="${3:-}"
  local cert_file="${4:-}"
  local identity_regex

  need_cmd cosign
  identity_regex="^https://github.com/${repo}/\\.github/workflows/release\\.yml@.*$"

  cosign verify-blob \
    --certificate "$cert_file" \
    --signature "$sig_file" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    --certificate-identity-regexp "$identity_regex" \
    "$checksum_file" >/dev/null \
    || die "Cosign signature verification failed for SHA256SUMS."
}

sync_curated_skill() {
  local source_dir="${1:-}"
  [[ "$AUTO_UPDATE_SKILL_ENABLED" == "1" ]] || return 0

  if [[ ! -f "${source_dir}/SKILL.md" ]]; then
    warn "Skill payload not found in release. Skipping skill sync."
    return 0
  fi

  local codex_home target_dir temp_dir
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  target_dir="${codex_home}/skills/codex-tasks"
  temp_dir="${target_dir}.tmp.$$"

  if ! mkdir -p "$(dirname "$target_dir")"; then
    warn "Cannot create skill directory parent: $(dirname "$target_dir")"
    return 0
  fi

  rm -rf "$temp_dir" >/dev/null 2>&1 || true
  if ! mkdir -p "$temp_dir"; then
    warn "Cannot prepare temporary skill directory: $temp_dir"
    return 0
  fi

  if ! cp -R "${source_dir}/." "$temp_dir/"; then
    rm -rf "$temp_dir" >/dev/null 2>&1 || true
    warn "Failed to copy skill payload from ${source_dir}"
    return 0
  fi

  rm -rf "$target_dir" >/dev/null 2>&1 || true
  if ! mv "$temp_dir" "$target_dir"; then
    rm -rf "$temp_dir" >/dev/null 2>&1 || true
    warn "Failed to activate skill at ${target_dir}"
    return 0
  fi

  log "Skill synced: ${target_dir}"
}

write_launcher() {
  local launcher="${1:-}"
  local install_root="${2:-}"
  local repo="${3:-}"
  local bin_dir="${4:-}"
  local auto_update_enabled="${5:-1}"
  local auto_update_interval_seconds="${6:-86400}"
  local auto_update_skill_enabled="${7:-1}"

  mkdir -p "$(dirname "$launcher")"
  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    printf "INSTALL_ROOT=%q\n" "$install_root"
    printf "REPO_DEFAULT=%q\n" "$repo"
    printf "BIN_DIR_DEFAULT=%q\n" "$bin_dir"
    printf "AUTO_UPDATE_DEFAULT=%q\n" "$auto_update_enabled"
    printf "AUTO_UPDATE_INTERVAL_DEFAULT=%q\n" "$auto_update_interval_seconds"
    printf "AUTO_UPDATE_SKILL_DEFAULT=%q\n" "$auto_update_skill_enabled"
    cat <<'LAUNCHER_BODY'
to_lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

normalize_bool() {
  local raw="${1:-}"
  local lower
  lower="$(to_lower "$raw")"
  case "$lower" in
    1|true|yes|on) echo 1 ;;
    0|false|no|off) echo 0 ;;
    *) echo "$AUTO_UPDATE_DEFAULT" ;;
  esac
}

REPO="${CODEX_TASKS_REPO:-$REPO_DEFAULT}"
BIN_DIR="${CODEX_TASKS_BIN_DIR:-$BIN_DIR_DEFAULT}"
AUTO_UPDATE_ENABLED="$(normalize_bool "${CODEX_TASKS_AUTO_UPDATE:-$AUTO_UPDATE_DEFAULT}")"
AUTO_UPDATE_INTERVAL_SECONDS="${CODEX_TASKS_AUTO_UPDATE_INTERVAL_SECONDS:-$AUTO_UPDATE_INTERVAL_DEFAULT}"
if [[ ! "$AUTO_UPDATE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$AUTO_UPDATE_INTERVAL_SECONDS" -le 0 ]]; then
  AUTO_UPDATE_INTERVAL_SECONDS="$AUTO_UPDATE_INTERVAL_DEFAULT"
fi
AUTO_UPDATE_SKILL_ENABLED="$(normalize_bool "${CODEX_TASKS_AUTO_UPDATE_SKILL:-$AUTO_UPDATE_SKILL_DEFAULT}")"

INSTALL_SCRIPT="${INSTALL_ROOT}/current/scripts/install-codex-tasks.sh"
MAIN_CLI="${INSTALL_ROOT}/current/scripts/codex-tasks"
UPDATE_STAMP="${INSTALL_ROOT}/.auto_update_last_check"
UPDATE_LOCK_DIR="${INSTALL_ROOT}/.auto_update_lock"
SKILL_SOURCE_DIR="${INSTALL_ROOT}/current/skills/codex-tasks"
SKILL_LOCK_DIR="${INSTALL_ROOT}/.auto_update_skill_lock"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILL_TARGET_DIR="${CODEX_HOME_DIR}/skills/codex-tasks"

maybe_auto_update() {
  [[ "$AUTO_UPDATE_ENABLED" == "1" ]] || return 0
  [[ -x "$INSTALL_SCRIPT" ]] || return 0
  [[ -n "$REPO" ]] || return 0
  [[ -n "$BIN_DIR" ]] || return 0

  local now last
  now="$(date +%s 2>/dev/null || printf '0')"
  [[ "$now" =~ ^[0-9]+$ ]] || return 0

  last=0
  if [[ -f "$UPDATE_STAMP" ]]; then
    last="$(tr -d '[:space:]' < "$UPDATE_STAMP" 2>/dev/null || printf '0')"
  fi
  [[ "$last" =~ ^[0-9]+$ ]] || last=0

  if (( now - last < AUTO_UPDATE_INTERVAL_SECONDS )); then
    return 0
  fi

  mkdir -p "$INSTALL_ROOT" >/dev/null 2>&1 || return 0
  if ! mkdir "$UPDATE_LOCK_DIR" >/dev/null 2>&1; then
    return 0
  fi

  printf '%s\n' "$now" > "$UPDATE_STAMP" 2>/dev/null || true

  (
    trap 'rmdir "$UPDATE_LOCK_DIR" >/dev/null 2>&1 || true' EXIT
    "$INSTALL_SCRIPT" \
      --repo "$REPO" \
      --version latest \
      --install-root "$INSTALL_ROOT" \
      --bin-dir "$BIN_DIR" \
      >/dev/null 2>&1 || true
  ) &
}

sync_skill_payload() {
  [[ "$AUTO_UPDATE_SKILL_ENABLED" == "1" ]] || return 0
  [[ -f "$SKILL_SOURCE_DIR/SKILL.md" ]] || return 0
  mkdir -p "$(dirname "$SKILL_TARGET_DIR")" >/dev/null 2>&1 || return 0

  local tmp_dir
  tmp_dir="${SKILL_TARGET_DIR}.tmp.$$"
  rm -rf "$tmp_dir" >/dev/null 2>&1 || true
  mkdir -p "$tmp_dir" >/dev/null 2>&1 || return 0
  cp -R "${SKILL_SOURCE_DIR}/." "$tmp_dir/" >/dev/null 2>&1 || {
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 0
  }
  rm -rf "$SKILL_TARGET_DIR" >/dev/null 2>&1 || true
  mv "$tmp_dir" "$SKILL_TARGET_DIR" >/dev/null 2>&1 || {
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 0
  }
}

maybe_sync_skill() {
  [[ "$AUTO_UPDATE_SKILL_ENABLED" == "1" ]] || return 0
  if ! mkdir "$SKILL_LOCK_DIR" >/dev/null 2>&1; then
    return 0
  fi
  (
    trap 'rmdir "$SKILL_LOCK_DIR" >/dev/null 2>&1 || true' EXIT
    sync_skill_payload
  ) &
}

maybe_auto_update
maybe_sync_skill
exec "$MAIN_CLI" "$@"
LAUNCHER_BODY
  } > "$launcher"
  chmod +x "$launcher"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --repo"
      REPO="$1"
      ;;
    --version)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --version"
      VERSION="$1"
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
    --force)
      FORCE=1
      ;;
    --skip-checksum)
      VERIFY_CHECKSUM=0
      ;;
    --verify-signature)
      VERIFY_SIGNATURE=1
      ;;
    --auto-update)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --auto-update"
      AUTO_UPDATE_ENABLED="$1"
      ;;
    --auto-update=*)
      AUTO_UPDATE_ENABLED="${1#--auto-update=}"
      [[ -n "$AUTO_UPDATE_ENABLED" ]] || die "Missing value for --auto-update"
      ;;
    --auto-update-interval)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --auto-update-interval"
      AUTO_UPDATE_INTERVAL_SECONDS="$1"
      ;;
    --auto-update-interval=*)
      AUTO_UPDATE_INTERVAL_SECONDS="${1#--auto-update-interval=}"
      [[ -n "$AUTO_UPDATE_INTERVAL_SECONDS" ]] || die "Missing value for --auto-update-interval"
      ;;
    --auto-update-skill)
      shift || true
      [[ $# -gt 0 ]] || die "Missing value for --auto-update-skill"
      AUTO_UPDATE_SKILL_ENABLED="$1"
      ;;
    --auto-update-skill=*)
      AUTO_UPDATE_SKILL_ENABLED="${1#--auto-update-skill=}"
      [[ -n "$AUTO_UPDATE_SKILL_ENABLED" ]] || die "Missing value for --auto-update-skill"
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

[[ "$REPO" == */* ]] || die "--repo must be in owner/repo format"
VERIFY_CHECKSUM="$(normalize_bool "$VERIFY_CHECKSUM")"
VERIFY_SIGNATURE="$(normalize_bool "$VERIFY_SIGNATURE")"
AUTO_UPDATE_ENABLED="$(normalize_bool "$AUTO_UPDATE_ENABLED")"
AUTO_UPDATE_SKILL_ENABLED="$(normalize_bool "$AUTO_UPDATE_SKILL_ENABLED")"
require_positive_int "auto-update interval" "$AUTO_UPDATE_INTERVAL_SECONDS"

if [[ "$VERIFY_SIGNATURE" -eq 1 ]]; then
  VERIFY_CHECKSUM=1
fi

need_cmd curl
need_cmd tar
need_cmd mktemp

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(resolve_latest_tag "$REPO")"
elif [[ "$VERSION" != v* ]]; then
  VERSION="v${VERSION}"
fi

is_semver_tag "$VERSION" || die "Invalid --version value: ${VERSION}"

target_dir="${INSTALL_ROOT}/${VERSION}"
if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
  die "Install target exists but is not a directory: ${target_dir}"
fi

already_installed=0
if [[ -d "$target_dir" && "$FORCE" -ne 1 ]]; then
  already_installed=1
  log "Version already installed at ${target_dir}. Skipping payload download."
  if [[ "$AUTO_UPDATE_SKILL_ENABLED" == "1" ]] && [[ ! -f "${target_dir}/skills/codex-tasks/SKILL.md" ]]; then
    already_installed=0
    log "Installed payload is missing bundled skill. Refreshing ${VERSION}."
  fi
fi

if [[ "$already_installed" -eq 0 ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  archive_path="${tmp_dir}/source.tar.gz"
  tarball_url="$(release_asset_url "$REPO" "$VERSION" "source.tar.gz")"
  download_file "$tarball_url" "$archive_path"

  if [[ "$VERIFY_CHECKSUM" -eq 1 ]]; then
    checksums_path="${tmp_dir}/SHA256SUMS"
    download_file "$(release_asset_url "$REPO" "$VERSION" "SHA256SUMS")" "$checksums_path"

    if [[ "$VERIFY_SIGNATURE" -eq 1 ]]; then
      checksum_sig_path="${tmp_dir}/SHA256SUMS.sig"
      checksum_cert_path="${tmp_dir}/SHA256SUMS.pem"
      download_file "$(release_asset_url "$REPO" "$VERSION" "SHA256SUMS.sig")" "$checksum_sig_path"
      download_file "$(release_asset_url "$REPO" "$VERSION" "SHA256SUMS.pem")" "$checksum_cert_path"
      verify_checksums_signature "$REPO" "$checksums_path" "$checksum_sig_path" "$checksum_cert_path"
      log "Signature verification passed."
    fi

    verify_tarball_checksum "$checksums_path" "$tarball_url" "$archive_path"
    log "Checksum verification passed."
  fi

  tar -xzf "$archive_path" -C "$tmp_dir" || die "Failed to extract tarball"
  source_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$source_dir" ]] || die "Unable to resolve extracted source directory"
  [[ -x "${source_dir}/scripts/codex-tasks" ]] || die "Release payload missing scripts/codex-tasks"

  mkdir -p "$INSTALL_ROOT"
  rm -rf "${target_dir}.tmp"
  mkdir -p "${target_dir}.tmp"
  cp -R "${source_dir}/scripts" "${target_dir}.tmp/" || die "Failed to copy scripts payload"
  if [[ -d "${source_dir}/skills/.curated/codex-tasks" ]]; then
    mkdir -p "${target_dir}.tmp/skills"
    cp -R "${source_dir}/skills/.curated/codex-tasks" "${target_dir}.tmp/skills/codex-tasks" \
      || die "Failed to copy curated skill payload"
  else
    warn "Release payload missing curated codex-tasks skill."
  fi
  echo "${VERSION#v}" > "${target_dir}.tmp/scripts/VERSION"
  rm -rf "$target_dir"
  mv "${target_dir}.tmp" "$target_dir"
fi

mkdir -p "$INSTALL_ROOT"
ln -sfn "$target_dir" "${INSTALL_ROOT}/current"

launcher_path="${BIN_DIR}/codex-tasks"
write_launcher "$launcher_path" "$INSTALL_ROOT" "$REPO" "$BIN_DIR" "$AUTO_UPDATE_ENABLED" "$AUTO_UPDATE_INTERVAL_SECONDS" "$AUTO_UPDATE_SKILL_ENABLED"
sync_curated_skill "${INSTALL_ROOT}/current/skills/codex-tasks"

if [[ "$already_installed" -eq 1 ]]; then
  log "Installed version unchanged: ${VERSION}"
else
  log "Installed version: ${VERSION}"
fi
log "Install root: ${target_dir}"
log "Launcher: ${launcher_path}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
  log "PATH does not include ${BIN_DIR}"
  log "Add this line to your shell profile:"
  log "  export PATH=\"${BIN_DIR}:\$PATH\""
fi

log "Run: codex-tasks --help"
