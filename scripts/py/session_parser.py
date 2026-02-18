from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ANSI_ESCAPE_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


@dataclass
class SessionRender:
    markdown: str
    source: str
    parsed_events: int


def strip_ansi(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text.replace("\r", ""))


def read_tail_text(file_path: str, max_bytes: int = 180_000) -> str:
    path = Path(file_path)
    if not file_path or not path.exists() or not path.is_file():
        return ""

    try:
        with path.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            start = max(0, size - max_bytes)
            handle.seek(start)
            raw = handle.read()
    except OSError:
        return ""

    return raw.decode("utf-8", errors="replace")


def _iter_json_objects(text: str) -> list[dict[str, Any]]:
    parsed: list[dict[str, Any]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict):
            parsed.append(item)
    return parsed


def _normalize_fragment(text: str) -> str:
    cleaned = strip_ansi(text).strip()
    if not cleaned:
        return ""
    return cleaned


def _collect_role_text(node: Any, role_filter: str | None, inherited_role: str = "") -> list[str]:
    fragments: list[str] = []

    if isinstance(node, str):
        if role_filter is None or inherited_role == role_filter:
            fragments.append(node)
        return fragments

    if isinstance(node, list):
        for item in node:
            fragments.extend(_collect_role_text(item, role_filter, inherited_role))
        return fragments

    if not isinstance(node, dict):
        return fragments

    current_role = inherited_role
    role_value = node.get("role")
    if isinstance(role_value, str) and role_value.strip():
        current_role = role_value.strip().lower()

    for key in ("text", "output_text"):
        value = node.get(key)
        if isinstance(value, str):
            if role_filter is None or current_role == role_filter:
                fragments.append(value)

    content = node.get("content")
    if isinstance(content, (dict, list)):
        fragments.extend(_collect_role_text(content, role_filter, current_role))

    for key, value in node.items():
        if key in {"role", "text", "output_text", "content"}:
            continue
        if isinstance(value, (dict, list)):
            fragments.extend(_collect_role_text(value, role_filter, current_role))

    return fragments


def _extract_event_fragments(event: dict[str, Any]) -> list[str]:
    event_type = str(event.get("type") or event.get("event") or "").lower()
    fragments: list[str] = []

    assistant_fragments = _collect_role_text(event, "assistant")
    if assistant_fragments:
        fragments.extend(assistant_fragments)
    elif "assistant" in event_type or "output_text" in event_type or "message" in event_type:
        fragments.extend(_collect_role_text(event, None))

    normalized: list[str] = []
    for fragment in fragments:
        cleaned = _normalize_fragment(fragment)
        if not cleaned:
            continue
        if normalized and cleaned == normalized[-1]:
            continue
        if normalized and cleaned.startswith(normalized[-1]) and len(cleaned) > len(normalized[-1]) and len(normalized[-1]) > 24:
            normalized[-1] = cleaned
            continue
        normalized.append(cleaned)

    return normalized


def _render_from_json_events(events: list[dict[str, Any]], max_blocks: int) -> str:
    blocks: list[str] = []
    delta_buffer = ""
    for event in events:
        event_type = str(event.get("type") or event.get("event") or "").lower()
        delta = event.get("delta")
        if isinstance(delta, str) and ("assistant" in event_type or "output_text" in event_type):
            delta_buffer += delta
            continue

        flushed_delta = _normalize_fragment(delta_buffer)
        if flushed_delta:
            if not blocks or flushed_delta != blocks[-1]:
                blocks.append(flushed_delta)
        delta_buffer = ""

        for fragment in _extract_event_fragments(event):
            if blocks and fragment == blocks[-1]:
                continue
            blocks.append(fragment)

    flushed_delta = _normalize_fragment(delta_buffer)
    if flushed_delta:
        if not blocks or flushed_delta != blocks[-1]:
            blocks.append(flushed_delta)

    if not blocks:
        return ""

    tail_blocks = blocks[-max_blocks:]
    return "\n\n---\n\n".join(tail_blocks)


def _render_transcript(text: str, max_lines: int) -> str:
    cleaned = strip_ansi(text)
    lines = cleaned.splitlines()
    if max_lines > 0:
        lines = lines[-max_lines:]

    compact: list[str] = []
    blank_seen = 0
    for line in lines:
        if line.strip():
            compact.append(line.rstrip())
            blank_seen = 0
            continue
        blank_seen += 1
        if blank_seen <= 2:
            compact.append("")

    body = "\n".join(compact).strip()
    if not body:
        return "(No output yet)"
    return f"```text\n{body}\n```"


def parse_session_markdown(raw_capture: str, log_tail: str = "", max_blocks: int = 6, max_lines: int = 260) -> SessionRender:
    source_text = log_tail if log_tail.strip() else raw_capture
    events = _iter_json_objects(source_text)
    if events:
        rendered = _render_from_json_events(events, max_blocks=max_blocks)
        if rendered.strip():
            return SessionRender(markdown=rendered, source="jsonl", parsed_events=len(events))

    fallback = source_text if source_text.strip() else raw_capture
    return SessionRender(
        markdown=_render_transcript(fallback, max_lines=max_lines),
        source="transcript",
        parsed_events=0,
    )
