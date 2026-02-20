from __future__ import annotations

import re
from pathlib import Path
from typing import Any


class TodoError(RuntimeError):
    pass


_GATE_DEP_RE = re.compile(r"G\d+")
_LEGACY_TASK_DEP_RE = re.compile(r"T\d+-\d+")
_NUMERIC_TASK_DEP_RE = re.compile(r"\d{3}")
_QUALIFIED_TASK_DEP_RE = re.compile(r"([^:\s]+):(\d{3})")


def _field(cols: list[str], col_no: int) -> str:
    idx = col_no - 1
    if idx < 0 or idx >= len(cols):
        return ""
    return cols[idx].strip()


def _parse_markdown_row(line: str) -> list[str] | None:
    text = line.strip()
    if not text.startswith("|") or not text.endswith("|"):
        return None

    cells: list[str] = []
    buf: list[str] = []
    escaped = False
    for ch in text[1:-1]:
        if escaped:
            if ch == "|":
                buf.append("|")
            else:
                buf.append("\\")
                buf.append(ch)
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == "|":
            cells.append("".join(buf).strip())
            buf = []
            continue
        buf.append(ch)

    if escaped:
        buf.append("\\")
    cells.append("".join(buf).strip())
    # Preserve split("|") indexing used by schema column numbers.
    return ["", *cells, ""]


def _resolve_columns(lines: list[str], schema: dict[str, Any]) -> dict[str, int]:
    resolved = {
        "id_col": int(schema["id_col"]),
        "branch_col": int(schema.get("branch_col", 0) or 0),
        "title_col": int(schema["title_col"]),
        "deps_col": int(schema["deps_col"]),
        "status_col": int(schema["status_col"]),
    }

    for line in lines:
        cols = _parse_markdown_row(line)
        if cols is None:
            continue

        header_map: dict[str, int] = {}
        for col_no in range(1, len(cols) + 1):
            label = _field(cols, col_no).strip().lower()
            if not label:
                continue
            if label not in header_map:
                header_map[label] = col_no

        if "id" not in header_map or "status" not in header_map:
            continue

        if "title" in header_map:
            resolved["title_col"] = header_map["title"]
        if "deps" in header_map:
            resolved["deps_col"] = header_map["deps"]
        if "branch" in header_map:
            resolved["branch_col"] = header_map["branch"]
        else:
            resolved["branch_col"] = 0
        resolved["id_col"] = header_map["id"]
        resolved["status_col"] = header_map["status"]
        break

    return resolved


def make_task_key(task_id: str, task_branch: str = "") -> str:
    tid = (task_id or "").strip()
    branch = (task_branch or "").strip()
    if branch:
        return f"{branch}::{tid}"
    return tid


def parse_todo(todo_file: str | Path, schema: dict[str, Any]) -> tuple[list[dict[str, str]], dict[str, str]]:
    path = Path(todo_file)
    if not path.exists():
        raise TodoError(f"TODO file not found: {path}")

    lines = path.read_text(encoding="utf-8").splitlines()
    tasks: list[dict[str, str]] = []

    cols = _resolve_columns(lines, schema)
    id_col = int(cols["id_col"])
    branch_col = int(cols["branch_col"])
    title_col = int(cols["title_col"])
    deps_col = int(cols["deps_col"])
    status_col = int(cols["status_col"])

    for line in lines:
        cols = _parse_markdown_row(line)
        if cols is None:
            continue

        task_id = _field(cols, id_col)
        task_branch = _field(cols, branch_col) if branch_col > 0 else ""
        title = _field(cols, title_col)
        deps = _field(cols, deps_col)
        status = _field(cols, status_col)

        if not task_id or task_id == "ID" or set(task_id) == {"-"}:
            continue

        tasks.append(
            {
                "id": task_id,
                "branch": task_branch,
                "title": title,
                "deps": deps,
                "status": status,
            }
        )

    gate_regex = re.compile(str(schema["gate_regex"]))
    done_keywords = {str(x).lower() for x in schema.get("done_keywords", [])}
    gates: dict[str, str] = {}

    for line in lines:
        m = gate_regex.search(line)
        if not m:
            continue

        token = m.group(1)
        gate_id = token.split(" ", 1)[0]

        state_m = re.search(r"\(([^)]*)\)", token)
        state = (state_m.group(1) if state_m else "").strip().lower()
        gates[gate_id] = "DONE" if state in done_keywords else "PENDING"

    return tasks, gates


def build_indexes(tasks: list[dict[str, str]]) -> dict[str, str]:
    return {
        make_task_key(task.get("id", ""), task.get("branch", "")): task.get("status", "")
        for task in tasks
    }


def deps_ready(
    deps: str,
    task_status: dict[str, str],
    gate_status: dict[str, str],
    task_branch: str = "",
) -> bool:
    raw = (deps or "").strip()
    if not raw or raw == "-":
        return True

    for dep_raw in raw.split(","):
        dep = dep_raw.strip()
        if not dep:
            continue

        if _GATE_DEP_RE.fullmatch(dep):
            if gate_status.get(dep, "") != "DONE":
                return False
            continue

        dep_key = ""
        if _LEGACY_TASK_DEP_RE.fullmatch(dep):
            dep_key = make_task_key(dep, "")
        elif _NUMERIC_TASK_DEP_RE.fullmatch(dep):
            dep_key = make_task_key(dep, task_branch)
        else:
            qualified = _QUALIFIED_TASK_DEP_RE.fullmatch(dep)
            if qualified:
                dep_key = make_task_key(qualified.group(2), qualified.group(1))
            else:
                return False

        if task_status.get(dep_key, "") != "DONE":
            # Backward compatibility: if branch-qualified lookup misses,
            # allow plain-id lookup for legacy boards without branch metadata.
            if task_status.get(dep, "") != "DONE":
                return False

    return True
