import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "py"))

from task_spec import evaluate_task_spec, task_spec_rel_path, task_spec_rel_path_for_branch


class TaskSpecTests(unittest.TestCase):
    def test_missing_spec_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            result = evaluate_task_spec(repo_root, "T1-001")
            self.assertFalse(result["exists"])
            self.assertFalse(result["valid"])
            self.assertEqual(result["spec_rel_path"], ".codex-tasks/planning/specs/T1-001.md")

    def test_valid_spec_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            spec_path = repo_root / task_spec_rel_path("T2-001")
            spec_path.parent.mkdir(parents=True, exist_ok=True)
            spec_path.write_text(
                "\n".join(
                    [
                        "# Task Spec: T2-001",
                        "",
                        "## Goal",
                        "Ship API endpoint for widgets.",
                        "",
                        "## In Scope",
                        "- endpoint implementation",
                        "",
                        "## Acceptance Criteria",
                        "- [ ] endpoint handles auth",
                        "- [ ] endpoint validates body",
                        "- [ ] tests are added",
                        "- [ ] rollout notes are documented",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = evaluate_task_spec(repo_root, "T2-001")
            self.assertTrue(result["exists"])
            self.assertTrue(result["valid"])
            self.assertEqual(result["goal_summary"], "Ship API endpoint for widgets.")
            self.assertEqual(result["in_scope_summary"], "endpoint implementation")
            self.assertEqual(
                result["acceptance_summary"],
                "endpoint handles auth; endpoint validates body; tests are added",
            )

    def test_invalid_spec_missing_required_section(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            spec_path = repo_root / task_spec_rel_path("T3-001")
            spec_path.parent.mkdir(parents=True, exist_ok=True)
            spec_path.write_text(
                "\n".join(
                    [
                        "# Task Spec: T3-001",
                        "",
                        "## Goal",
                        "Goal text",
                        "",
                        "## In Scope",
                        "in scope text",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = evaluate_task_spec(repo_root, "T3-001")
            self.assertTrue(result["exists"])
            self.assertFalse(result["valid"])
            self.assertTrue(any("missing_sections" in err for err in result["errors"]))

    def test_invalid_spec_empty_section(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            spec_path = repo_root / task_spec_rel_path("T4-001")
            spec_path.parent.mkdir(parents=True, exist_ok=True)
            spec_path.write_text(
                "\n".join(
                    [
                        "# Task Spec: T4-001",
                        "",
                        "## Goal",
                        "Goal text",
                        "",
                        "## In Scope",
                        "",
                        "## Acceptance Criteria",
                        "- [ ] done",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = evaluate_task_spec(repo_root, "T4-001")
            self.assertTrue(result["exists"])
            self.assertFalse(result["valid"])
            self.assertTrue(any("empty_sections" in err for err in result["errors"]))

    def test_custom_spec_dir_absolute_path(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td) / "repo"
            repo_root.mkdir(parents=True, exist_ok=True)
            spec_root = Path(td) / "planning" / "specs"
            spec_root.mkdir(parents=True, exist_ok=True)
            spec_path = spec_root / "T7-001.md"
            spec_path.write_text(
                "\n".join(
                    [
                        "# Task Spec: T7-001",
                        "",
                        "## Goal",
                        "Goal text",
                        "",
                        "## In Scope",
                        "- scope item",
                        "",
                        "## Acceptance Criteria",
                        "- [ ] done",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = evaluate_task_spec(repo_root, "T7-001", spec_dir=str(spec_root))
            self.assertTrue(result["exists"])
            self.assertTrue(result["valid"])
            self.assertEqual(result["spec_path"], str(spec_path))
            self.assertEqual(result["spec_rel_path"], str(spec_path))

    def test_branch_scoped_spec_path(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo_root = Path(td)
            spec_rel = task_spec_rel_path_for_branch("001", "release/1.0")
            spec_path = repo_root / spec_rel
            spec_path.parent.mkdir(parents=True, exist_ok=True)
            spec_path.write_text(
                "\n".join(
                    [
                        "# Task Spec: 001",
                        "",
                        "## Goal",
                        "Goal text",
                        "",
                        "## In Scope",
                        "- scope item",
                        "",
                        "## Acceptance Criteria",
                        "- [ ] done",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = evaluate_task_spec(repo_root, "001", task_branch="release/1.0")
            self.assertTrue(result["exists"])
            self.assertTrue(result["valid"])
            self.assertEqual(
                result["spec_rel_path"], ".codex-tasks/planning/specs/release/1.0/001.md"
            )


if __name__ == "__main__":
    unittest.main()
