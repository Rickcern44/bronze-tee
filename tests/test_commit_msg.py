"""Offline tests for tools/check-commit-msg.sh (Conventional Commits gate)."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "check-commit-msg.sh"


def check(message, *, strict=False, as_file=False):
    args = ["bash", str(SCRIPT)]
    if strict:
        args.append("--strict")
    if as_file:
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            handle.write(message)
            path = handle.name
        try:
            return subprocess.run(args + [path], capture_output=True, text=True)
        finally:
            Path(path).unlink()
    return subprocess.run(args + ["-m", message], capture_output=True, text=True)


class CommitMessageTests(unittest.TestCase):
    VALID = [
        "feat(course): RCE-169 x",
        "feat(infra): RCE-180 GitVersion and git-cliff versioning",
        "fix(physics): RCE-181 clamp spin decay",
        "fix(physics)!: RCE-181 change spin units to rpm",
        "feat!: drop the legacy course format",
        "docs: update the release guide",
        "chore: bump GitVersion.Tool",
        "ci: RCE-180 pin git-cliff 2.14.2",
        "refactor(ui): split hud theme",
        "perf: cache surface lookups",
        "test(physics): cover roll-out on slopes",
        "build: pin dotnet tools",
        "style: format main.gd",
        "revert: feat(course): RCE-169 x",
    ]

    INVALID = [
        "RCE-169: Baked surface maps for arbitrary course features (#7)",
        "Add opencode Linear MCP config",
        "Fix Mac export template and texture settings",
        "feature(course): RCE-169 x",
        "Feat(course): RCE-169 x",
        "feat(Course): RCE-169 x",
        "feat(course):RCE-169 x",
        "feat(course): ",
        "feat: ",
        "feat (course): x",
        "wip: something",
        "",
        "feat: " + "x" * 100,
    ]

    def test_valid_subjects_pass(self):
        for message in self.VALID:
            with self.subTest(message=message):
                result = check(message)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(check(message, strict=True).returncode, 0)

    def test_invalid_subjects_fail_with_an_example(self):
        for message in self.INVALID:
            with self.subTest(message=message):
                result = check(message)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("ERROR:", result.stderr)
                self.assertIn("type(scope): RCE-nnn subject", result.stderr)

    def test_legacy_linear_prefix_gets_a_specific_hint(self):
        result = check("RCE-169: Baked surface maps")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Linear key goes after the type", result.stderr)

    def test_git_generated_subjects_pass_locally_but_not_strict(self):
        for message in [
            "Merge branch 'main' into feat/rce-180-versioning",
            "Merge pull request #1 from Rickcern44/add-game-icon",
            'Revert "feat(course): RCE-169 x"',
            "fixup! feat(course): RCE-169 x",
            "squash! docs: update the release guide",
        ]:
            with self.subTest(message=message):
                self.assertEqual(check(message).returncode, 0)
                self.assertEqual(check(message, strict=True).returncode, 1)

    def test_message_file_with_body_footer_and_git_comments(self):
        message = (
            "# Please enter the commit message for your changes.\n"
            "feat(course)!: RCE-169 bake surface maps\n"
            "\n"
            "Holes with a baked map use it for lie lookups.\n"
            "\n"
            "BREAKING CHANGE: course.tres needs a surface_map entry.\n"
            "Refs: RCE-169\n"
            "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n"
            "# Lines starting with '#' will be ignored.\n"
            "# ------------------------ >8 ------------------------\n"
            "diff --git a/x b/x\n"
        )
        result = check(message, as_file=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_body_needs_a_blank_line(self):
        result = check("feat(course): RCE-169 x\nbody without a blank line", as_file=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("blank line", result.stderr)

    def test_usage_errors_exit_2(self):
        self.assertEqual(subprocess.run(["bash", str(SCRIPT)], capture_output=True).returncode, 2)
        missing = subprocess.run(["bash", str(SCRIPT), "/nonexistent/msg"], capture_output=True)
        self.assertEqual(missing.returncode, 2)


if __name__ == "__main__":
    unittest.main()
