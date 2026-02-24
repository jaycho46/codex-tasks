#!/usr/bin/env bash
set -euo pipefail

branch_exists_local() {
  local repo_root="${1:-}"
  local branch="${2:-}"
  [[ -n "$repo_root" && -n "$branch" ]] || return 1
  git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"
}

resolve_branch_ref() {
  local repo_root="${1:-}"
  local branch="${2:-}"
  local remote_ref
  [[ -n "$repo_root" && -n "$branch" ]] || return 1

  if branch_exists_local "$repo_root" "$branch"; then
    echo "$branch"
    return 0
  fi

  remote_ref="$(
    git -C "$repo_root" for-each-ref --format='%(refname)' "refs/remotes/*/$branch" \
      | head -n1
  )"
  if [[ -n "$remote_ref" ]]; then
    echo "$remote_ref"
    return 0
  fi

  return 1
}

ensure_local_branch_from_ref() {
  local repo_root="${1:-}"
  local branch="${2:-}"
  local start_ref="${3:-}"
  [[ -n "$repo_root" && -n "$branch" && -n "$start_ref" ]] || return 1

  if branch_exists_local "$repo_root" "$branch"; then
    return 0
  fi
  if git -C "$repo_root" branch "$branch" "$start_ref" >/dev/null 2>&1; then
    return 0
  fi
  branch_exists_local "$repo_root" "$branch"
}

branch_name_for() {
  local task_id="${1:-}"
  local task_branch="${2:-}"
  local task_slug branch_slug

  [[ -n "$task_id" ]] || return 1
  task_slug="$(sanitize "$task_id")"
  branch_slug="$(sanitize "$task_branch")"
  [[ -n "$task_slug" ]] || return 1

  if [[ -n "$branch_slug" ]]; then
    echo "codex/${branch_slug}-${task_slug}"
    return 0
  fi
  echo "codex/${task_slug}"
}

default_worktree_path_for() {
  local repo_name="${1:-}"
  local task_id="${2:-}"
  local parent_dir="${3:-}"
  local task_branch="${4:-}"
  local task_slug branch_slug

  task_slug="$(sanitize "$task_id")"
  branch_slug="$(sanitize "$task_branch")"
  if [[ -n "$branch_slug" ]]; then
    echo "${parent_dir}/${repo_name}-${branch_slug}-${task_slug}"
    return 0
  fi
  echo "${parent_dir}/${repo_name}-${task_slug}"
}

shared_state_dir_for() {
  local parent_dir="${1:-}"
  echo "${parent_dir}/.codex-tasks-shared"
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

ensure_task_worktree() {
  local repo_root="${1:-}"
  local repo_name="${2:-}"
  local task_id="${3:-}"
  local base_branch="${4:-main}"
  local parent_dir="${5:-}"
  local task_branch="${6:-}"

  local branch_name worktree_path existing_path base_ref
  branch_name="$(branch_name_for "$task_id" "$task_branch")"
  worktree_path="$(default_worktree_path_for "$repo_name" "$task_id" "$parent_dir" "$task_branch")"
  existing_path="$(find_worktree_for_branch "$repo_root" "$branch_name" || true)"

  mkdir -p "$parent_dir"

  if [[ -n "$existing_path" ]]; then
    echo "$existing_path"
    return 0
  fi

  if [[ -e "$worktree_path" ]]; then
    quarantine_orphan_worktree_path "$repo_root" "$worktree_path" "$branch_name"
  fi

  # Branch-column tasks can target a branch that does not exist yet.
  # Bootstrap it from the configured base branch before creating the
  # per-task codex/* work branch.
  if [[ -n "$task_branch" && "$base_branch" == "$task_branch" ]]; then
    if ! resolve_branch_ref "$repo_root" "$task_branch" >/dev/null 2>&1; then
      local fallback_base seed_ref
      fallback_base="${BASE_BRANCH:-main}"
      [[ -n "$fallback_base" ]] || fallback_base="main"
      [[ "$fallback_base" != "$task_branch" ]] || die "Missing task branch and fallback base is identical: $task_branch"

      seed_ref="$(resolve_branch_ref "$repo_root" "$fallback_base" || true)"
      [[ -n "$seed_ref" ]] || die "Configured base branch not found for bootstrap: $fallback_base"

      if ! ensure_local_branch_from_ref "$repo_root" "$task_branch" "$seed_ref"; then
        die "Failed to create missing task base branch: $task_branch (from $fallback_base)"
      fi
      echo "Created missing task base branch: $task_branch (from $fallback_base)" >&2
    fi
  fi

  base_ref="$(resolve_branch_ref "$repo_root" "$base_branch" || true)"
  [[ -n "$base_ref" ]] || die "Base branch not found in local/remote refs: $base_branch"

  if git -C "$repo_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
    git -C "$repo_root" worktree add --quiet "$worktree_path" "$branch_name" >/dev/null
  else
    git -C "$repo_root" worktree add --quiet -b "$branch_name" "$worktree_path" "$base_ref" >/dev/null
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
  local common_dir top_level resolved_from_common

  common_dir="$(git_common_dir_for "$repo_path" || true)"
  if [[ -n "$common_dir" ]]; then
    # Some repositories (e.g. submodules / absorbed gitdirs) expose the primary
    # worktree via git-common-dir + core.worktree. Resolve that first to avoid
    # mistaking the current agent worktree for the primary repository.
    resolved_from_common="$(git -C "$common_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$resolved_from_common" && -d "$resolved_from_common" ]]; then
      (cd "$resolved_from_common" && pwd)
      return 0
    fi

    if [[ "$(basename "$common_dir")" == ".git" ]]; then
      (cd "$common_dir/.." && pwd)
      return 0
    fi
  fi

  top_level="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null)" || return 1
  (cd "$top_level" && pwd)
}
