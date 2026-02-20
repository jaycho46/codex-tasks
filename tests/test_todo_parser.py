import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "py"))

from todo_parser import TodoError, build_indexes, deps_ready, parse_todo


SCHEMA = {
    "id_col": 2,
    "title_col": 3,
    "deps_col": 4,
    "status_col": 6,
    "gate_regex": r"`(G[0-9]+ \([^)]+\))`",
    "done_keywords": ["DONE", "완료", "Complete", "complete"],
}


class TodoParserTests(unittest.TestCase):
    def test_parse_todo_and_deps(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            todo_path = Path(td) / "TODO.md"
            todo_path.write_text(
                """
# TODO Board

| ID | Title | Deps | Notes | Status |
|---|---|---|---|---|
| T1-001 | First | - | note | DONE |
| T1-002 | Second | T1-001,G1 | note | TODO |
| T1-003 | Third | G2 | note | TODO |

Gate state: `G1 (DONE)`
Gate state: `G2 (PENDING)`
""".strip()
                + "\n",
                encoding="utf-8",
            )

            tasks, gates = parse_todo(todo_path, SCHEMA)
            task_status = build_indexes(tasks)

            self.assertEqual([t["id"] for t in tasks], ["T1-001", "T1-002", "T1-003"])
            self.assertEqual(gates["G1"], "DONE")
            self.assertEqual(gates["G2"], "PENDING")

            self.assertTrue(deps_ready("T1-001,G1", task_status, gates))
            self.assertFalse(deps_ready("G2", task_status, gates))
            self.assertFalse(deps_ready("UNKNOWN", task_status, gates))
            self.assertTrue(deps_ready("-", task_status, gates))

    def test_missing_todo_file_raises(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            missing = Path(td) / "TODO.md"
            with self.assertRaises(TodoError):
                parse_todo(missing, SCHEMA)

    def test_parse_todo_supports_escaped_pipe_cells(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            todo_path = Path(td) / "TODO.md"
            todo_path.write_text(
                """
# TODO Board

| ID | Title | Deps | Notes | Status |
|---|---|---|---|---|
| T2-001 | Title with \\| pipe | - | note with \\| pipe | TODO |
""".strip()
                + "\n",
                encoding="utf-8",
            )

            tasks, _ = parse_todo(todo_path, SCHEMA)
            self.assertEqual(len(tasks), 1)
            self.assertEqual(tasks[0]["id"], "T2-001")
            self.assertEqual(tasks[0]["title"], "Title with | pipe")
            self.assertEqual(tasks[0]["deps"], "-")
            self.assertEqual(tasks[0]["status"], "TODO")

    def test_branch_scoped_ids_and_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            todo_path = Path(td) / "TODO.md"
            todo_path.write_text(
                """
# TODO Board

| ID | Branch | Title | Deps | Notes | Status |
|---|---|---|---|---|---|
| 001 | main | First | - | note | DONE |
| 001 | release/1.0 | Second | main:001 | note | TODO |
| 002 | release/1.0 | Third | 001 | note | TODO |
""".strip()
                + "\n",
                encoding="utf-8",
            )

            schema = dict(SCHEMA)
            schema.update(
                {
                    "branch_col": 3,
                    "title_col": 4,
                    "deps_col": 5,
                    "status_col": 7,
                }
            )

            tasks, gates = parse_todo(todo_path, schema)
            task_status = build_indexes(tasks)

            self.assertEqual(len(tasks), 3)
            self.assertEqual(tasks[0]["branch"], "main")
            self.assertEqual(tasks[1]["branch"], "release/1.0")
            self.assertEqual(task_status["main::001"], "DONE")
            self.assertEqual(task_status["release/1.0::001"], "TODO")

            self.assertTrue(
                deps_ready("main:001", task_status, gates, task_branch="release/1.0")
            )
            self.assertFalse(
                deps_ready("001", task_status, gates, task_branch="release/1.0")
            )
            self.assertTrue(deps_ready("001", task_status, gates, task_branch="main"))


if __name__ == "__main__":
    unittest.main()
