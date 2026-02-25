<h1>codex-tasks</h1>

<p align="center">
  <img src="./docs/logo.svg" alt="codex-tasks logo" width="540" />
</p>

<p align="center">
  <strong>Orchestration SKILL and CLI for parallel Codex workers</strong>
</p>

<p align="center">
  <a href="#installation">Installation</a> |
  <a href="#usage">Usage</a> |
  <a href="#how-it-works">How It Works</a> |
</p>

<p align="center">
  <img alt="codex skill" src="https://img.shields.io/badge/Codex%20Skill-0f766e?style=for-the-badge">
  <img alt="codex skill" src="https://img.shields.io/badge/macOS-000000?logoColor=F0F0F0&style=for-the-badge">
  <img alt="license" src="https://img.shields.io/github/license/jaycho46/codex-tasks?style=for-the-badge">
  <img alt="version" src="https://img.shields.io/github/v/release/jaycho46/codex-tasks?style=for-the-badge">
  <img alt="tests" src="https://img.shields.io/github/actions/workflow/status/jaycho46/codex-tasks/ci.yml?branch=main&style=for-the-badge&label=tests">
</p>

## Why this repository exists

This repository is intentionally split:

- Humans create and standardize plans in Codex App through interactive back-and-forth with the `codex-tasks` skill.
- `codex-tasks` CLI executes that plan in a deterministic, repeatable way.

Planning is always done through this interactive exchange; files are not edited directly.

The skill is the source of intent. The CLI is the repeatable executor.

## Installation

### 1. Install CLI

```bash
curl -fsSL https://raw.githubusercontent.com/jaycho46/codex-tasks/main/scripts/install-codex-tasks.sh | bash
```

### 2. Install dependencies

Required:

- `git`
- `python3`
- `codex` CLI
- `tmux` (default worker backend)
- `textual` 


```bash
brew install tmux
python3 -m pip install textual
```

### 3. Install Skill in Codex App

```text
$skill-installer Install skill from GitHub:
- repo: jaycho46/codex-tasks
- path: skills/.curated/codex-tasks
```

## Usage

### 0. Initialize

Run initialization once per repository before planning starts.

Prompt examples are marked with the `prompt` code fence so they are clearly separated from shell commands.

You can do this through the prompt flow:

```prompt
$codex-tasks
Initialize first.
```

### 1. Conversation-Based Task Planning

Use the skill for planning tasks through interactive turns. The CLI is not for manually composing planning strategy.

The detailed spec is intentionally drafted through conversation. Use follow-up prompts to refine and expand each task spec until it is detailed enough for reliable execution.

Planning and execution can continue in parallel. Even while orchestration is running, you can keep creating, refining, and validating tasks through prompt turns.

`initialize` must be done before writing tasks.

### Recommended prompt pattern

1) Create initial tasks (first turn)

```prompt
$codex-tasks
Create tasks for [AAA].
These tasks will be completed on the [feat/AAA] branch.
.
.
.
```

2) Refine specs after review (+second turn)

```prompt
Please change the generated task list and spec files
.
.
.
```

3) Promote to executable queue (last turn)

```prompt
Promote tasks in this conversation to TODO so they are ready for orchestration.
Run a readiness check after promotion.
```

After the skill runs, it creates/updates:

- `.codex-tasks/planning/TODO.md`
- `.codex-tasks/planning/specs/<branch>/<task_id>.md`

### 2) Orchestration with Dashboard (CLI)

`codex-tasks` provides a built-in TUI dashboard for monitoring and managing live orchestration.

The dashboard is the control surface for the project queue:

- Tasks/Logs (all current task rows and status)
- Ready Tasks (executable tasks currently eligible to run)
- Running Agents (active worker sessions and live output)

You can keep planning and refining tasks through prompts while orchestration is in progress.

Open dashboard:

```bash
codex-tasks
```

- `Ctrl+R`: start orchestration (`run start`)
- `Ctrl+E`: emergency stop all in-progress tasks (rollback included)
- `Tasks`: open a row to view and inspect TODO specs
- `Running Agents`: open a row to inspect each active agent, current step, and live logs

## How It Works

```mermaid
flowchart LR
  A["Start planning request in Codex App"] --> B["Create PLAN task rows"]
  B <--> C["Refine PLAN/spec through prompt turns"]
  C --> D["Validate spec and promote PLAN → TODO (`task promote`)"]
  D --> E["Optional readiness check: `codex-tasks run start --dry-run`"]
  E --> F["Open dashboard and start orchestration (`Ctrl+R`, `run start`)"]
  F --> G{"Ready TODO found?"}
  G -->|no| H["Orchestration waits on dashboard"]
  G -->|yes| I["Task enters Ready list after deps/spec/lock checks"]
  I --> J["Create worktree + lock + set IN_PROGRESS"]
  J --> K["Launch worker with task spec"]
  K --> L{"Worker exits"}
  L -->|done| M["task complete: merge + cleanup + unlock"]
  L -->|failed/crashed| N["task auto-cleanup-exit: rollback status to TODO"]
  M --> O["Complete path auto-triggers next run start"]
  O --> P{"Ready TODO exists?"}
  N --> H
  P -->|yes| F
  P -->|no| H
``` 

## License

MIT. See `LICENSE`.
