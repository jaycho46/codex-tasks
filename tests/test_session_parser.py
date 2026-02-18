import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "py"))

from session_parser import parse_session_markdown, read_tail_text, strip_ansi


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

        parsed = parse_session_markdown("", log_tail=log_tail)

        self.assertEqual(parsed.source, "jsonl")
        self.assertGreaterEqual(parsed.parsed_events, 3)
        self.assertIn("# Done", parsed.markdown)
        self.assertIn("- item", parsed.markdown)

    def test_parse_transcript_fallback_wraps_clean_text(self) -> None:
        raw_capture = "\x1b[32mRunning step\x1b[0m\r\nNext line\r\n"

        parsed = parse_session_markdown(raw_capture)

        self.assertEqual(parsed.source, "transcript")
        self.assertEqual(parsed.parsed_events, 0)
        self.assertIn("```text", parsed.markdown)
        self.assertIn("Running step", parsed.markdown)
        self.assertIn("Next line", parsed.markdown)

    def test_read_tail_text_returns_file_tail(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sample.log"
            path.write_text("line1\nline2\nline3\n", encoding="utf-8")

            tail = read_tail_text(str(path), max_bytes=10)

            self.assertIn("line3", tail)


if __name__ == "__main__":
    unittest.main()
