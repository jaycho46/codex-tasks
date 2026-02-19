from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ANSI_ESCAPE_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
CODE_FENCE_RE = re.compile(r"```([^\n`]*)\n(.*?)```", re.DOTALL)
MAX_PREVIEW_CHARS = 1200


@dataclass
class SessionRender:
    markdown: str
    source: str
    parsed_events: int


@dataclass
class SessionBlock:
    kind: str
    label: str
    body: str
    event_type: str = ""
    timestamp: str = ""


@dataclass
class SessionView:
    source: str
    parsed_events: int
    blocks: list[SessionBlock]


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


def _truncate(text: str, limit: int = MAX_PREVIEW_CHARS) -> str:
    if len(text) <= limit:
        return text
    return f"{text[:limit]}..."


def _format_payload(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return _truncate(_normalize_fragment(value))

    try:
        rendered = json.dumps(value, ensure_ascii=False, indent=2)
    except TypeError:
        rendered = str(value)
    return _truncate(strip_ansi(rendered).strip())


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


def _normalize_fragments(fragments: list[str]) -> list[str]:
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


def _extract_role_fragments(event: dict[str, Any], role: str) -> list[str]:
    return _normalize_fragments(_collect_role_text(event, role))


def _event_type(event: dict[str, Any]) -> str:
    return str(event.get("type") or event.get("event") or "").strip().lower()


def _pick_nested(node: dict[str, Any], *path: str) -> Any:
    current: Any = node
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _first_nonempty(*values: Any) -> str:
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _event_timestamp(event: dict[str, Any]) -> str:
    return _first_nonempty(
        event.get("timestamp"),
        event.get("time"),
        event.get("created_at"),
        event.get("ts"),
        _pick_nested(event, "response", "created_at"),
    )


def _tool_name_from_event(event: dict[str, Any]) -> str:
    return _first_nonempty(
        event.get("tool_name"),
        _pick_nested(event, "tool", "name"),
        _pick_nested(event, "tool_call", "name"),
        _pick_nested(event, "call", "name"),
        _pick_nested(event, "function", "name"),
        _pick_nested(event, "function_call", "name"),
    )


def _split_chat_and_code_blocks(
    text: str,
    chat_kind: str,
    chat_label: str,
    event_type: str,
    timestamp: str,
) -> list[SessionBlock]:
    blocks: list[SessionBlock] = []
    cursor = 0

    for match in CODE_FENCE_RE.finditer(text):
        before = _normalize_fragment(text[cursor:match.start()])
        if before:
            blocks.append(
                SessionBlock(
                    kind=chat_kind,
                    label=chat_label,
                    body=_truncate(before),
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )

        language = (match.group(1) or "").strip()
        code_body = _normalize_fragment(match.group(2) or "")
        if code_body:
            label = "Code"
            if language:
                label = f"Code · {language}"
            blocks.append(
                SessionBlock(
                    kind="code",
                    label=label,
                    body=_truncate(code_body),
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )
        cursor = match.end()

    tail = _normalize_fragment(text[cursor:])
    if tail:
        blocks.append(
            SessionBlock(
                kind=chat_kind,
                label=chat_label,
                body=_truncate(tail),
                event_type=event_type,
                timestamp=timestamp,
            )
        )

    if not blocks:
        body = _normalize_fragment(text)
        if body:
            blocks.append(
                SessionBlock(
                    kind=chat_kind,
                    label=chat_label,
                    body=_truncate(body),
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )

    return blocks


def _extract_reasoning_fragments(event: dict[str, Any], event_type: str) -> list[str]:
    fragments: list[str] = []
    if isinstance(event.get("delta"), str):
        fragments.append(str(event.get("delta") or ""))
    for key in ("summary", "reasoning", "analysis", "thought", "text"):
        value = event.get(key)
        if isinstance(value, str):
            fragments.append(value)
    if any(token in event_type for token in ("reasoning", "thinking", "thought", "analysis")):
        fragments.extend(_collect_role_text(event, "assistant"))
    return _normalize_fragments(fragments)


def _event_detail(event: dict[str, Any]) -> str:
    for key in ("message", "status", "summary", "detail", "error", "reason"):
        if key in event:
            detail = _format_payload(event.get(key))
            if detail:
                return detail

    preview: dict[str, Any] = {}
    for key in ("id", "model", "role", "finish_reason"):
        if key in event:
            preview[key] = event[key]
    if preview:
        detail = _format_payload(preview)
        if detail:
            return detail

    return _format_payload(event)


def _event_to_blocks(event: dict[str, Any]) -> list[SessionBlock]:
    blocks: list[SessionBlock] = []
    event_type = _event_type(event)
    timestamp = _event_timestamp(event)

    if any(token in event_type for token in ("reasoning", "thinking", "thought", "analysis")):
        reasoning_fragments = _extract_reasoning_fragments(event, event_type)
        for fragment in reasoning_fragments:
            blocks.append(
                SessionBlock(
                    kind="think",
                    label="Think",
                    body=fragment,
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )
        if blocks:
            return blocks

    agent_fragments: list[str] = []
    agent_fragments.extend(_extract_role_fragments(event, "user"))
    agent_fragments.extend(_extract_role_fragments(event, "system"))
    if agent_fragments:
        for fragment in _normalize_fragments(agent_fragments):
            blocks.extend(
                _split_chat_and_code_blocks(
                    fragment,
                    chat_kind="chat_agent",
                    chat_label="Agent",
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )

    assistant_fragments = _extract_role_fragments(event, "assistant")
    if assistant_fragments:
        for fragment in assistant_fragments:
            blocks.extend(
                _split_chat_and_code_blocks(
                    fragment,
                    chat_kind="chat_codex",
                    chat_label="Codex",
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )

    if blocks:
        return blocks

    has_tool_signal = (
        "tool" in event_type
        or "function_call" in event_type
        or _tool_name_from_event(event) != ""
        or "tool" in event
        or "tool_call" in event
    )
    if has_tool_signal:
        tool_name = _tool_name_from_event(event)
        if "result" in event_type or "output" in event_type:
            kind = "tool_result"
            label = "Tool Result"
        elif "error" in event_type or "fail" in event_type:
            kind = "error"
            label = "Tool Error"
        else:
            kind = "tool_call"
            label = "Tool Call"
        if tool_name:
            label = f"{label} · {tool_name}"

        payload = None
        for key in ("arguments", "input", "result", "output", "content", "message", "error"):
            if key in event:
                payload = event[key]
                break
        body = _format_payload(payload) if payload is not None else _event_detail(event)
        blocks.append(
            SessionBlock(
                kind=kind,
                label=label,
                body=body or "(no payload)",
                event_type=event_type,
                timestamp=timestamp,
            )
        )

        command_value = _pick_nested(event, "arguments", "command") or _pick_nested(event, "input", "command") or event.get("command")
        if isinstance(command_value, str) and command_value.strip():
            blocks.append(
                SessionBlock(
                    kind="code",
                    label="Code · command",
                    body=_truncate(_normalize_fragment(command_value)),
                    event_type=event_type,
                    timestamp=timestamp,
                )
            )
        return blocks

    if "error" in event_type or "fail" in event_type or "exception" in event_type or "error" in event:
        body = _format_payload(event.get("error") or event.get("message") or _event_detail(event))
        return [
            SessionBlock(
                kind="error",
                label="Error",
                body=body or "(unknown error)",
                event_type=event_type,
                timestamp=timestamp,
            )
        ]

    if (
        "response." in event_type
        or "session" in event_type
        or "status" in event_type
        or event_type in {"started", "completed"}
    ):
        detail = _event_detail(event)
        return [
            SessionBlock(
                kind="status",
                label="Status",
                body=detail or event_type or "status",
                event_type=event_type,
                timestamp=timestamp,
            )
        ]

    if not event_type:
        return []

    detail = _event_detail(event)
    return [
        SessionBlock(
            kind="event",
            label="Event",
            body=detail or event_type,
            event_type=event_type,
            timestamp=timestamp,
        )
    ]


def _append_unique(blocks: list[SessionBlock], block: SessionBlock) -> None:
    if (
        blocks
        and block.kind == blocks[-1].kind
        and block.body == blocks[-1].body
        and block.event_type == blocks[-1].event_type
    ):
        return
    blocks.append(block)


def _flush_delta_buffers(blocks: list[SessionBlock], text_delta: str, think_delta: str, timestamp: str) -> tuple[str, str]:
    flushed_text = _normalize_fragment(text_delta)
    if flushed_text:
        for block in _split_chat_and_code_blocks(
            flushed_text,
            chat_kind="chat_codex",
            chat_label="Codex",
            event_type="response.output_text.delta",
            timestamp=timestamp,
        ):
            _append_unique(blocks, block)

    flushed_think = _normalize_fragment(think_delta)
    if flushed_think:
        _append_unique(
            blocks,
            SessionBlock(
                kind="think",
                label="Think",
                body=flushed_think,
                event_type="response.reasoning.delta",
                timestamp=timestamp,
            ),
        )

    return "", ""


def _render_from_json_events(events: list[dict[str, Any]], max_blocks: int) -> list[SessionBlock]:
    blocks: list[SessionBlock] = []
    text_delta_buffer = ""
    think_delta_buffer = ""

    for event in events:
        event_type = _event_type(event)
        delta = event.get("delta")
        if isinstance(delta, str) and ("assistant" in event_type or "output_text" in event_type):
            text_delta_buffer += delta
            continue
        if isinstance(delta, str) and any(token in event_type for token in ("reasoning", "thinking", "thought", "analysis")):
            think_delta_buffer += delta
            continue

        text_delta_buffer, think_delta_buffer = _flush_delta_buffers(
            blocks,
            text_delta_buffer,
            think_delta_buffer,
            timestamp=_event_timestamp(event),
        )

        for block in _event_to_blocks(event):
            _append_unique(blocks, block)

    text_delta_buffer, think_delta_buffer = _flush_delta_buffers(
        blocks,
        text_delta_buffer,
        think_delta_buffer,
        timestamp="",
    )

    if not blocks:
        return []

    return blocks[-max_blocks:]


def _normalize_cli_view_blocks(blocks: list[SessionBlock], max_blocks: int) -> list[SessionBlock]:
    if not blocks:
        return []

    # Keep the high-level conversational surface and hide low-level transport noise.
    allowed_kinds = {"chat_agent", "chat_codex", "think", "code", "error", "terminal"}
    merged: list[SessionBlock] = []

    for block in blocks:
        if block.kind not in allowed_kinds:
            continue
        body = _normalize_fragment(block.body)
        if not body:
            continue

        if (
            merged
            and merged[-1].kind == block.kind
            and merged[-1].label == block.label
        ):
            merged[-1].body = _truncate(f"{merged[-1].body}\n\n{body}")
            if not merged[-1].timestamp and block.timestamp:
                merged[-1].timestamp = block.timestamp
            continue

        merged.append(
            SessionBlock(
                kind=block.kind,
                label=block.label,
                body=_truncate(body),
                event_type="",
                timestamp=block.timestamp,
            )
        )

    if not merged:
        # Fallback: if everything was filtered out, show the latest meaningful raw block.
        tail = blocks[-1]
        return [
            SessionBlock(
                kind="terminal",
                label="Terminal",
                body=_truncate(_normalize_fragment(tail.body) or "(No output yet)"),
                event_type="",
                timestamp=tail.timestamp,
            )
        ]

    return merged[-max_blocks:]


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
    return body or "(No output yet)"


def parse_session_structured(raw_capture: str, log_tail: str = "", max_blocks: int = 12, max_lines: int = 260) -> SessionView:
    source_text = log_tail if log_tail.strip() else raw_capture
    events = _iter_json_objects(source_text)
    if events:
        raw_blocks = _render_from_json_events(events, max_blocks=max(64, max_blocks * 4))
        if raw_blocks:
            cli_blocks = _normalize_cli_view_blocks(raw_blocks, max_blocks=max_blocks)
            return SessionView(source="jsonl", parsed_events=len(events), blocks=cli_blocks)

    fallback = source_text if source_text.strip() else raw_capture
    fallback_body = _render_transcript(fallback, max_lines=max_lines)
    fallback_blocks = _split_chat_and_code_blocks(
        fallback_body,
        chat_kind="terminal",
        chat_label="Terminal",
        event_type="capture",
        timestamp="",
    )
    if not fallback_blocks:
        fallback_blocks = [
            SessionBlock(
                kind="terminal",
                label="Terminal",
                body="(No output yet)",
                event_type="capture",
            )
        ]

    return SessionView(
        source="transcript",
        parsed_events=0,
        blocks=fallback_blocks,
    )


def _blocks_to_markdown(blocks: list[SessionBlock]) -> str:
    if not blocks:
        return "(No output yet)"

    lines: list[str] = []
    for block in blocks:
        lines.append(f"### {block.label}")
        if block.event_type:
            lines.append(f"`{block.event_type}`")
        if block.timestamp:
            lines.append(f"_time: {block.timestamp}_")
        lines.append("")
        lines.append(block.body or "(no content)")
        lines.append("")
    return "\n".join(lines).strip()


def parse_session_markdown(raw_capture: str, log_tail: str = "", max_blocks: int = 6, max_lines: int = 260) -> SessionRender:
    view = parse_session_structured(
        raw_capture,
        log_tail=log_tail,
        max_blocks=max_blocks,
        max_lines=max_lines,
    )
    return SessionRender(
        markdown=_blocks_to_markdown(view.blocks),
        source=view.source,
        parsed_events=view.parsed_events,
    )
