#!/usr/bin/env bash
set -euo pipefail

branch_name_for() {
  local agent="${1:-}"
  local task_id="${2:-}"
  local agent_slug task_slug

  [[ -n "$agent" && -n "$task_id" ]] || return 1
  agent_slug="$(sanitize "$agent")"
  task_slug="$(sanitize "$task_id")"
  [[ -n "$agent_slug" && -n "$task_slug" ]] || return 1

  echo "codex/${agent_slug}-${task_slug}"
}

default_worktree_path_for() {
  local repo_name="${1:-}"
  local agent="${2:-}"
  local task_id="${3:-}"
  local parent_dir="${4:-}"
  local agent_slug task_slug

  agent_slug="$(sanitize "$agent")"
  task_slug="$(sanitize "$task_id")"
  echo "${parent_dir}/${repo_name}-${agent_slug}-${task_slug}"
}

shared_state_dir_for() {
  local parent_dir="${1:-}"
  echo "${parent_dir}/.state-shared"
}

find_worktree_for_branch() {
  local repo_root="${1:-}"
  local branch="${2:-}"
  local line current_path current_branch

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        current_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        if [[ "$current_branch" == "$branch" ]]; then
          echo "$current_path"
          return 0
        fi
        ;;
    esac
  done < <(git -C "$repo_root" worktree list --porcelain)

  return 1
}

find_branch_for_worktree_path() {
  local repo_root="${1:-}"
  local target_path="${2:-}"
  local line current_path current_branch

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        current_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        if [[ "$current_path" == "$target_path" ]]; then
          echo "$current_branch"
          return 0
        fi
        ;;
      detached)
        if [[ "$current_path" == "$target_path" ]]; then
          echo "DETACHED"
          return 0
        fi
        ;;
    esac
  done < <(git -C "$repo_root" worktree list --porcelain)

  return 1
}

quarantine_orphan_worktree_path() {
  local repo_root="${1:-}"
  local worktree_path="${2:-}"
  local expected_branch="${3:-}"
  [[ -e "$worktree_path" ]] || return 0

  local attached_branch
  attached_branch="$(find_branch_for_worktree_path "$repo_root" "$worktree_path" || true)"
  if [[ -n "$attached_branch" ]]; then
    die "Worktree path already exists and is attached to $attached_branch (expected $expected_branch): $worktree_path"
  fi

  local timestamp quarantine_path attempt
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  quarantine_path="${worktree_path}.orphan-${timestamp}"
  attempt=0
  while [[ -e "$quarantine_path" ]]; do
    attempt=$((attempt + 1))
    quarantine_path="${worktree_path}.orphan-${timestamp}-${attempt}"
  done

  if ! mv "$worktree_path" "$quarantine_path"; then
    die "Failed to quarantine stale worktree path: $worktree_path"
  fi

  echo "[WARN] quarantined stale worktree path: $worktree_path -> $quarantine_path" >&2
}

ensure_agent_worktree() {
  local repo_root="${1:-}"
  local repo_name="${2:-}"
  local agent="${3:-}"
  local task_id="${4:-}"
  local base_branch="${5:-main}"
  local parent_dir="${6:-}"

  local branch_name worktree_path existing_path
  branch_name="$(branch_name_for "$agent" "$task_id")"
  worktree_path="$(default_worktree_path_for "$repo_name" "$agent" "$task_id" "$parent_dir")"
  existing_path="$(find_worktree_for_branch "$repo_root" "$branch_name" || true)"

  mkdir -p "$parent_dir"

  if [[ -n "$existing_path" ]]; then
    echo "$existing_path"
    return 0
  fi

  if [[ -e "$worktree_path" ]]; then
    quarantine_orphan_worktree_path "$repo_root" "$worktree_path" "$branch_name"
  fi

  if git -C "$repo_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
    git -C "$repo_root" worktree add --quiet "$worktree_path" "$branch_name" >/dev/null
  else
    git -C "$repo_root" worktree add --quiet -b "$branch_name" "$worktree_path" "$base_branch" >/dev/null
  fi

  echo "$worktree_path"
}

current_branch() {
  local repo_path="${1:-}"
  git -C "$repo_path" rev-parse --abbrev-ref HEAD
}

ensure_clean_repo() {
  local repo_path="${1:-}"
  local label="${2:-repo}"
  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    die "$label has uncommitted changes: $repo_path"
  fi
}

git_common_dir_for() {
  local repo_path="${1:-}"
  local common
  common="$(git -C "$repo_path" rev-parse --git-common-dir 2>/dev/null)" || return 1
  if [[ "$common" != /* ]]; then
    common="$repo_path/$common"
  fi
  (cd "$common" && pwd)
}

primary_repo_root_for() {
  local repo_path="${1:-}"
  local common_dir top_level

  common_dir="$(git_common_dir_for "$repo_path" || true)"
  if [[ -n "$common_dir" && "$(basename "$common_dir")" == ".git" ]]; then
    (cd "$common_dir/.." && pwd)
    return 0
  fi

  top_level="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null)" || return 1
  (cd "$top_level" && pwd)
}
