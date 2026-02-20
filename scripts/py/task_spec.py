from __future__ import annotations

import re
from pathlib import Path
from typing import Any

REQUIRED_SECTIONS = ("Goal", "In Scope", "Acceptance Criteria")

_HEADING_RE = re.compile(r"^\s{0,3}#{2,6}\s+(.+?)\s*$")
_CHECKBOX_RE = re.compile(r"^[-*+]\s+\[[ xX]\]\s*(.+)$")
_LIST_ITEM_RE = re.compile(r"^(?:[-*+]\s+|\d+\.\s+)(.+)$")


def task_spec_rel_path(task_id: str, spec_dir: str = ".codex-tasks/planning/specs") -> str:
    base = Path(spec_dir).expanduser()
    target = base / f"{task_id}.md"
    if target.is_absolute():
        return str(target)
    return target.as_posix()


def task_spec_rel_path_for_branch(
    task_id: str,
    task_branch: str = "",
    spec_dir: str = ".codex-tasks/planning/specs",
) -> str:
    base = Path(spec_dir).expanduser()
    branch = (task_branch or "").strip()
    if branch:
        target = base / Path(branch) / f"{task_id}.md"
    else:
        target = base / f"{task_id}.md"
    if target.is_absolute():
        return str(target)
    return target.as_posix()


def task_spec_abs_path(
    repo_root: str | Path,
    task_id: str,
    spec_dir: str = ".codex-tasks/planning/specs",
    task_branch: str = "",
) -> Path:
    spec_ref = Path(task_spec_rel_path_for_branch(task_id, task_branch, spec_dir)).expanduser()
    if spec_ref.is_absolute():
        return spec_ref
    return Path(repo_root) / spec_ref


def _normalize_summary_text(text: str) -> str:
    return " ".join(text.replace("\t", " ").replace("\n", " ").split())


def _strip_item_prefix(line: str) -> str:
    raw = line.strip()
    checkbox = _CHECKBOX_RE.match(raw)
    if checkbox:
        return checkbox.group(1).strip()
    list_item = _LIST_ITEM_RE.match(raw)
    if list_item:
        return list_item.group(1).strip()
    return raw


def _extract_sections(text: str) -> tuple[dict[str, str], set[str]]:
    buckets: dict[str, list[str]] = {name: [] for name in REQUIRED_SECTIONS}
    present: set[str] = set()
    current: str | None = None

    for line in text.splitlines():
        heading = _HEADING_RE.match(line)
        if heading:
            title = heading.group(1).strip()
            if title in buckets:
                current = title
                present.add(title)
            else:
                current = None
            continue

        if current is not None:
            buckets[current].append(line.rstrip())

    return {name: "\n".join(lines).strip() for name, lines in buckets.items()}, present


def _first_nonempty_line(section: str) -> str:
    for line in section.splitlines():
        cleaned = _strip_item_prefix(line)
        if cleaned:
            return _normalize_summary_text(cleaned)
    return ""


def _acceptance_summary(section: str) -> str:
    items: list[str] = []
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        cleaned = _strip_item_prefix(stripped)
        if not cleaned:
            continue

        if _CHECKBOX_RE.match(stripped) or _LIST_ITEM_RE.match(stripped):
            items.append(cleaned)
            if len(items) >= 3:
                break

    if items:
        return _normalize_summary_text("; ".join(items))
    return _first_nonempty_line(section)


def evaluate_task_spec(
    repo_root: str | Path,
    task_id: str,
    spec_dir: str = ".codex-tasks/planning/specs",
    task_branch: str = "",
) -> dict[str, Any]:
    rel_path = task_spec_rel_path_for_branch(task_id, task_branch, spec_dir)
    spec_path = task_spec_abs_path(repo_root, task_id, spec_dir, task_branch)

    result: dict[str, Any] = {
        "task_id": task_id,
        "task_branch": task_branch,
        "spec_rel_path": rel_path,
        "spec_path": str(spec_path),
        "exists": False,
        "valid": False,
        "errors": [],
        "goal_summary": "",
        "in_scope_summary": "",
        "acceptance_summary": "",
    }

    if not spec_path.exists():
        return result

    result["exists"] = True

    try:
        text = spec_path.read_text(encoding="utf-8")
    except OSError as exc:
        result["errors"] = [f"spec_read_error: {exc}"]
        return result

    sections, present = _extract_sections(text)
    missing_sections: list[str] = []
    empty_sections: list[str] = []

    for section_name in REQUIRED_SECTIONS:
        if section_name not in present:
            missing_sections.append(section_name)
            continue
        if not _first_nonempty_line(sections.get(section_name, "")):
            empty_sections.append(section_name)

    if missing_sections:
        result["errors"].append(
            "missing_sections: " + ", ".join(missing_sections)
        )
    if empty_sections:
        result["errors"].append(
            "empty_sections: " + ", ".join(empty_sections)
        )
    if result["errors"]:
        return result

    result["goal_summary"] = _first_nonempty_line(sections.get("Goal", ""))
    result["in_scope_summary"] = _first_nonempty_line(sections.get("In Scope", ""))
    result["acceptance_summary"] = _acceptance_summary(
        sections.get("Acceptance Criteria", "")
    )
    result["valid"] = True
    return result
