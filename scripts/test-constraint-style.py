#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CLEAN_ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}

SPEC = importlib.util.spec_from_file_location(
    "constraint_style", Path(__file__).resolve().parent / "check-constraint-style.py",
)
STYLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STYLE)


class ConstraintStyleTests(unittest.TestCase):
    def test_counts_code_but_not_comments_or_strings(self):
        code = """
        NSLayoutConstraint.activate([c])
        NSLayoutConstraint.deactivate([c])
        buildLayout(activate:
            false)
        // NSLayoutConstraint.activate([c])
        /* outer /* activate: false */ comment */
        let s = "NSLayoutConstraint.activate("
        let raw = #"activate: false"#
        view.snp.makeConstraints { $0.edges.equalToSuperview() }
        """
        self.assertEqual(STYLE.file_counts(code), {"activate-false": 1, "activate-block": 1})

    def test_counts_may_only_decrease(self):
        base = {"a.swift": {"activate-block": 2}}
        self.assertEqual(STYLE.increases({"a.swift": {"activate-block": 1}}, base), [])
        for counts in ({"a.swift": {"activate-block": 3}}, {"b.swift": {"activate-block": 2}},
                       {"a.swift": {"activate-block": 2, "activate-false": 1}}):
            with self.subTest(counts=counts):
                self.assertTrue(STYLE.increases(counts, base))

    def test_scans_production_and_test_targets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ("Sources/AnyDock", "Sources/AnyDockCore", "Tests/AnyDockTests", "Other"):
                path = root / name / "Fixture.swift"
                path.parent.mkdir(parents=True)
                path.write_text("NSLayoutConstraint.activate([])")
            self.assertEqual(set(STYLE.current_counts(root)), {
                "Sources/AnyDock/Fixture.swift", "Sources/AnyDockCore/Fixture.swift",
                "Tests/AnyDockTests/Fixture.swift",
            })

    def test_cli_initial_base_decrease_mismatch_and_growth(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Sources/Fixture.swift"
            source.parent.mkdir()
            source.write_text("NSLayoutConstraint.activate([])")
            test = root / "Tests/Fixture.swift"
            test.parent.mkdir()
            test.write_text("view.snp.makeConstraints { $0.edges.equalToSuperview() }")
            self.git(root, "init", "-q", "--initial-branch=main")
            self.git(root, "add", "Sources", "Tests")
            self.git(root, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "-qm", "fixture")
            baseline = root / STYLE.BASELINE
            baseline.parent.mkdir()
            baseline.write_text(json.dumps(STYLE.current_counts(root)))
            result = self.run_check(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            test.write_text("buildLayout(activate: false)")
            self.assertNotEqual(self.run_check(root).returncode, 0)
            self.assertNotEqual(self.run_check(root, "--write-baseline").returncode, 0)
            source.write_text("")
            test.write_text("")
            result = self.run_check(root, "--write-baseline")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(baseline.read_text()), {})

    def run_check(self, root, *args):
        return subprocess.run(
            [sys.executable, "-B", str(STYLE.SCRIPTS / "check-constraint-style.py"),
             "--root", str(root), "--base-ref", "HEAD", *args],
            capture_output=True, text=True, env=CLEAN_ENV,
        )

    def git(self, root, *args):
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, env=CLEAN_ENV)


if __name__ == "__main__":
    unittest.main()
