import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "py"))

from session_parser import parse_session_structured, read_tail_text, strip_ansi


class SessionParserTests(unittest.TestCase):
    def test_strip_ansi_removes_terminal_escape_sequences(self) -> None:
        raw = "\x1b[31merror\x1b[0m line"
        self.assertEqual(strip_ansi(raw), "error line")

    def test_parse_jsonl_prefers_assistant_output(self) -> None:
        log_tail = "\n".join(
            [
                '{"type":"response.output_text.delta","delta":"Hello"}',
                '{"type":"response.output_text.delta","delta":" world"}',
                '{"type":"response.completed","response":{"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"# Done\\n\\n- item"}]}]}}',
            ]
        )

        parsed = parse_session_structured("", log_tail=log_tail)

        self.assertEqual(parsed.source, "jsonl")
        self.assertGreaterEqual(parsed.parsed_events, 3)
        self.assertGreaterEqual(len(parsed.blocks), 1)
        joined = "\n".join(block.body for block in parsed.blocks)
        self.assertIn("# Done", joined)
        self.assertIn("- item", joined)

    def test_parse_jsonl_builds_chat_code_and_think_blocks(self) -> None:
        log_tail = "\n".join(
            [
                '{"type":"response.reasoning.delta","delta":"plan first"}',
                '{"type":"response.output_item.added","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I will do this.\\n```python\\nprint(123)\\n```"}]}}',
                '{"type":"response.output_item.added","item":{"type":"message","role":"user","content":[{"type":"input_text","text":"please continue"}]}}',
            ]
        )

        parsed = parse_session_structured("", log_tail=log_tail)

        kinds = [block.kind for block in parsed.blocks]
        self.assertIn("think", kinds)
        self.assertIn("chat_codex", kinds)
        self.assertIn("code", kinds)
        self.assertIn("chat_agent", kinds)

    def test_parse_jsonl_merges_consecutive_chat_blocks_and_hides_event_noise(self) -> None:
        log_tail = "\n".join(
            [
                '{"type":"response.output_text.delta","delta":"Hello"}',
                '{"type":"response.output_text.delta","delta":" world"}',
                '{"type":"response.status","status":"running"}',
                '{"type":"response.output_text.delta","delta":"\\nMore"}',
            ]
        )

        parsed = parse_session_structured("", log_tail=log_tail, max_blocks=8)
        self.assertEqual(parsed.source, "jsonl")
        # Should be one merged codex chat block, not separate event/status rows.
        self.assertEqual([b.kind for b in parsed.blocks], ["chat_codex"])
        self.assertIn("Hello world", parsed.blocks[0].body)
        self.assertIn("More", parsed.blocks[0].body)

    def test_parse_transcript_fallback_wraps_clean_text(self) -> None:
        raw_capture = "\x1b[32mRunning step\x1b[0m\r\nNext line\r\n"

        parsed = parse_session_structured(raw_capture)

        self.assertEqual(parsed.source, "transcript")
        self.assertEqual(parsed.parsed_events, 0)
        self.assertEqual(len(parsed.blocks), 1)
        self.assertEqual(parsed.blocks[0].kind, "terminal")
        self.assertIn("Running step", parsed.blocks[0].body)
        self.assertIn("Next line", parsed.blocks[0].body)

    def test_read_tail_text_returns_file_tail(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sample.log"
            path.write_text("line1\nline2\nline3\n", encoding="utf-8")

            tail = read_tail_text(str(path), max_bytes=10)

            self.assertIn("line3", tail)


if __name__ == "__main__":
    unittest.main()
