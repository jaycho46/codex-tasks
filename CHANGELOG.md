# Changelog

All notable changes to this project are documented in this file.

## v0.1.2 (unreleased)

### Highlights

- Running Agents overlay now opens live session details from the TUI.
  - Enter/click on a Running Agents row opens a read-only modal.
  - tmux-backed workers show live pane capture (0.33s refresh).
  - Legacy non-tmux sessions are shown with an unsupported message.
- Worker launch backend default changed to `tmux`.
  - `runtime.launch_backend` now defaults to `tmux`.
  - launch mode requires a usable tmux binary; `--no-launch` remains available.
- Added worker-exit auto-cleanup flow.
  - New internal command: `task auto-cleanup-exit <task_id> <expected_pid>`.
  - tmux worker launcher starts a detached watcher to clean up on worker exit.
  - Auto-cleanup removes tmux/pid/lock/worktree/branch.
  - TODO rollback is skipped when task status is already `DONE`.
- Planning artifacts can now be stored outside the repository.
  - New config key: `repo.spec_dir` (default: `.codex-tasks/planning/specs`).
  - Scheduler/spec validation/scaffolding now read from configured `todo_file` + `spec_dir`.
  - Worker prompts now reference the resolved spec path instead of a fixed in-repo path.
- Init/default planning layout moved under `.codex-tasks/planning`.
  - Default `repo.todo_file`: `.codex-tasks/planning/TODO.md`
  - Default `repo.spec_dir`: `.codex-tasks/planning/specs`
- Runtime/CLI ownership model is now ownerless (breaking, internal-only rollout).
  - `task lock/unlock/heartbeat/update/complete` no longer accept `<agent>`.
  - `worktree create/start` no longer accept `<agent>`.
  - codex branch/worktree naming now uses task identity only (`codex/<task>` or `codex/<taskBranch>-<task>`).
  - lock/pid metadata removed `owner` key and validates by `task_key` + current worktree context.
  - ready/inventory payloads and TSV contracts removed `owner`; updates log column is now `Source`.
  - Added upgrade guard: commands reject legacy `owner=` metadata and instruct pre-clean (`task stop --all --apply`, `task cleanup-stale --apply`).

### Tests

- Added status payload and state-model coverage for `launch_backend`/`log_file` fields.
- Added smoke tests for tmux policy, worker-exit auto-cleanup, and DONE-guard behavior.
- Added ownerless smoke coverage for CLI-breaking signatures, lock context validation across worktrees, and legacy-owner upgrade guard.

## v0.1.1 (compared to v0.1.0)

### Highlights

- Added a task-spec-first workflow for TODO execution.
  - New command: `codex-tasks task scaffold-specs [--task <id>] [--dry-run] [--force]`
  - New module: `scripts/py/task_spec.py` for task spec validation and summaries
  - New guide: `docs/task-authoring-with-scaffold-specs.md`
- Added `task new` automation to create both TODO rows and task spec templates in one flow.
  - Command: `codex-tasks task new <task_id> [--deps <task_id[,task_id...]>] <summary>`
  - Supports dependency registration via `--deps`
- Improved TUI dashboard and modal UX in `status --tui`.
  - Better dashboard composition and status visualization
  - Confirmation modals for Run Start / Emergency Stop
  - Task-spec modal viewer from Task table row selection (`Enter`)

### Behavior Changes

- Scheduler readiness now requires task specs.
  - Tasks without a spec are excluded with `reason=missing_task_spec`
  - Tasks with incomplete required sections are excluded with `reason=invalid_task_spec`
- Ready-task payload now includes spec-derived fields (`goal_summary`, `in_scope_summary`, `acceptance_summary`).

### Documentation and Guidance

- README task workflow updated for task specs and dependency-aware task creation.
- Curated codex-tasks skill guidance updated to enforce spec-complete authoring before scheduling.

### Tests

- Added unit coverage for task spec evaluation (`tests/test_task_spec.py`).
- Added scheduler readiness tests for required task specs (`tests/test_engine_ready.py`, `tests/smoke/test_run_start_requires_task_spec.sh`).
- Added/expanded smoke tests for task creation + spec generation (`tests/smoke/test_task_new_creates_todo_and_spec.sh`).

### Repo Operations

- Updated CODEOWNERS coverage for runtime/release-related paths.
