# Task Authoring with `scaffold-specs`

This workflow turns TODO rows into executable task specs so workers do not run from one-line titles only.

## Quick Checklist

1. Initialize repository state.
2. Create feature-branch tasks with `task new`.
3. Fill required sections and concrete subtasks in each spec.
4. Confirm readiness with a dry-run scheduler check.
5. Start scheduler.

```bash
# 1) initialize
codex-tasks init

# 2) create feature task row + spec template together
codex-tasks task new 101 --branch feature/billing-retry "Billing webhook retry policy"

# optional: same-branch dependency uses 3-digit id
codex-tasks task new 102 --branch feature/billing-retry --deps 101 "Review billing retry policy implementation"

# optional: cross-branch dependency uses <branch>:<id>
codex-tasks task new 103 --branch release/1.0 --deps feature/billing-retry:101 "Release hardening"

# 3) edit generated files in .codex-tasks/planning/specs/<branch>/*.md

# 4) verify scheduler eligibility
codex-tasks run start --dry-run

# 5) run workers
codex-tasks run start
```

## TODO Row Format

Use the standard table shape:

```md
| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| 101 | main | Billing webhook retry policy | - | needs backfill | TODO |
```

## Create Tasks Quickly

Recommended path:

```bash
codex-tasks task new 101 --branch feature/billing-retry "Billing webhook retry policy"
```

What this does:

- appends a `TODO` row to `.codex-tasks/planning/TODO.md`
- records prerequisites in `Deps` when `--deps` is provided (same-branch `101` or cross-branch `<branch>:101`)
- creates `.codex-tasks/planning/specs/<branch>/101.md`
- adds `## Subtasks` template by default

## Generate Specs (Bulk / Existing TODO Rows)

Generate for every `TODO` row:

```bash
codex-tasks task scaffold-specs
```

Preview without writing:

```bash
codex-tasks task scaffold-specs --dry-run
```

Generate a specific task only:

```bash
codex-tasks task scaffold-specs --task 101 --branch main
```

Specs include `## Subtasks` by default:

```bash
codex-tasks task scaffold-specs --task 101 --branch main
```

Overwrite an existing spec:

```bash
codex-tasks task scaffold-specs --task 101 --branch main --force
```

## Required and Recommended Spec Sections

Each `.codex-tasks/planning/specs/<BRANCH>/<TASK_ID>.md` file must include these exact section headings:

- `## Goal`
- `## In Scope`
- `## Acceptance Criteria`

Recommended for worker quality and multi-agent delegation:

- `## Subtasks` with concrete list items

Template:

```md
# Task Spec: 101

Task title: Billing webhook retry policy
Task branch: feature/billing-retry

## Goal
Define the concrete outcome for 101.

## In Scope
- Describe what must be implemented for this task.
- List files, modules, or behaviors that are in scope.

## Acceptance Criteria
- Implementation is complete and testable.
- Relevant tests or validation steps are added or updated.
- Changes are ready to merge with a clear completion summary.

## Subtasks
- Implement billing retry policy
- Review changed files and list risks
- Fix review findings and regressions
- Polish tests/docs/refactors within scope
```

## Strong Migration Warning

Scheduler readiness now enforces task specs.

- If spec file is missing, task is excluded with `reason=missing_task_spec`.
- If required sections are missing/empty, task is excluded with `reason=invalid_task_spec`.

Immediate recovery sequence:

1. Run `codex-tasks task new <task_id> --branch <base_branch> [--deps <task_id[,task_id...]>] <summary>` for new tasks, or `task scaffold-specs` for existing rows.
2. Fill required sections in generated spec files.
3. Re-run `codex-tasks run start --dry-run`.
4. Confirm exclusion reason is gone, then run `codex-tasks run start`.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `reason=missing_task_spec` | `.codex-tasks/planning/specs/<branch>/<task_id>.md` does not exist | Run `codex-tasks task scaffold-specs` |
| `reason=invalid_task_spec` | Missing or empty `Goal`, `In Scope`, or `Acceptance Criteria` | Fill all required sections with non-empty content |
| Task still excluded after spec update | TODO status/deps/runtime rules still block it | Check `deps_not_ready` and active lock/worker reasons |
