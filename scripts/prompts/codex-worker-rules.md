Required guardrail skill:
- Use $codex-tasks.
- If the skill is unavailable, follow the fallback rules below exactly.

CLI preflight:
- Use this command path for all codex-tasks commands in this task: __CODEX_TASKS_CMD__
- If command execution fails because codex-tasks is missing, run:
  REPO="${CODEX_TASKS_REPO:-jaycho46/codex-tasks}"; curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/scripts/install-codex-tasks.sh" | bash -s -- --repo "$REPO" --version "${CODEX_TASKS_VERSION:-latest}" --force
- Then rerun the same command.

Execution rules:
- Task lifecycle contract: this task was started by run start, and must end via task complete.
- Do not self-start work using task lock/task update/worktree start.
- Planning gate reminder: newly authored follow-up tasks default to `PLAN` and are not schedulable until explicitly promoted to `TODO` after spec validation.
- Read and follow the task spec file at `__TASK_SPEC_PATH__` before implementing.
- If `## Subtasks` exists in the spec, use it as the execution plan for multi-agent delegation.
- For delegation, use this instruction style to trigger automatic multi-agent behavior:
  - "Spawn one agent per point/subtask, wait for all of them, and summarize the result for each point/subtask."
- In that mode:
  - spawn at least one subagent per concrete subtask
  - assign explicit ownership (files/responsibility) in each subagent prompt
  - wait for subagent results, review outputs, and integrate only valid changes
  - if a subtask is unclear, refine it first in the spec context, then delegate
- Subtask summary from spec: __SUBTASKS_SUMMARY__
- Do not mark DONE unless task deliverable files were actually added or updated.
- Do not finish with generic summaries such as "task complete" or "done".
- Keep work scoped to the assigned task title and task scope.
- Do not manually edit lock/pid metadata files.
- Report progress with a specific summary:
  __CODEX_TASKS_CMD__ --repo "__WORKTREE_PATH__" --state-dir "__STATE_DIR__" task update "__TASK_ID__" IN_PROGRESS "progress update"__TASK_BRANCH_FLAG__
- After final verification, mark the task DONE with a specific summary:
  __CODEX_TASKS_CMD__ --repo "__WORKTREE_PATH__" --state-dir "__STATE_DIR__" task update "__TASK_ID__" DONE "what was delivered"__TASK_BRANCH_FLAG__
- Commit message rules:
  - Deliverable commits: <type>: <summary> where <type> is one of feat|fix|refactor|docs|test|chore
  - A single task may include multiple deliverable commits; keep each commit focused and meaningful.
- Commit tracked deliverable changes before task complete (if any):
  git add <changed-files> && git commit -m "<type>: <summary>"
- Do not create empty marker commits just to signal DONE.
- Use task complete as the final command to perform merge and worktree cleanup.
- When complete, finish with a meaningful summary (or omit --summary to use the default completion log text):
  __CODEX_TASKS_CMD__ --repo "__WORKTREE_PATH__" --state-dir "__STATE_DIR__" task complete "__TASK_ID__" --summary "what was delivered"__TASK_BRANCH_FLAG__
- If task complete hits merge/rebase conflicts, resolve them as much as possible and rerun task complete.
- Only if it still fails after resolution attempts, report BLOCKED:
  __CODEX_TASKS_CMD__ --repo "__WORKTREE_PATH__" --state-dir "__STATE_DIR__" task update "__TASK_ID__" BLOCKED "merge conflict: <reason>"__TASK_BRANCH_FLAG__
