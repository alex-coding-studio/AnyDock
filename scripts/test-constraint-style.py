#!/usr/bin/env python3
import importlib.util
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
        code = '''
        NSLayoutConstraint.activate([c])
        NSLayoutConstraint.deactivate([c])
        buildLayout(activate:
            false)
        let gap = PKYLayout.Space.s4
        // NSLayoutConstraint.activate([c]); PKYLayout.Space.s4
        /* outer /* activate: false; PKYLayout.Space.s4 */ comment */
        let s = "NSLayoutConstraint.activate("
        let raw = #"PKYLayout.Space.s4"#
        let multiline = """
        activate: false
        PKYLayout.Space.s4
        """
        view.snp.makeConstraints { $0.edges.equalToSuperview() }
        '''
        self.assertEqual(STYLE.file_counts("Sources/AnyDock/View.swift", code), {
            "primitive-space": 1, "activate-false": 1, "activate-block": 1,
        })

    def test_primitive_spacing_scope(self):
        code = "let gap = PKYLayout \n . Space \n .s4"
        for name in ("Sources/AnyDock/Tray/View.swift", "Sources/AnyDock/Metrics/View.swift",
                     "Sources/AnyDock/ViewMetricsHelper.swift"):
            with self.subTest(name=name):
                self.assertEqual(STYLE.counts([(name, code)]), {name: {"primitive-space": 1}})
        for name in ("Sources/AnyDock/Tray/TrayMetrics.swift", "Sources/AnyDock/OtherMetrics.swift",
                     "Sources/AnyDockCore/Value.swift", "Tests/AnyDockTests/Fixture.swift",
                     "Sources/AnyDockExtra/Value.swift"):
            with self.subTest(name=name):
                self.assertEqual(STYLE.counts([(name, code)]), {})

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

    def test_cli_checks_sources_without_git(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Sources/AnyDock/Fixture.swift"
            source.parent.mkdir(parents=True)
            source.write_text("view.snp.makeConstraints { $0.edges.equalToSuperview() }")
            test = root / "Tests/AnyDockTests/Fixture.swift"
            test.parent.mkdir(parents=True)
            test.write_text("view.snp.makeConstraints { $0.edges.equalToSuperview() }")
            metrics = source.with_name("ViewMetrics.swift")
            metrics.write_text("let geometry = PKYLayout.Space.s4")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / ".git").exists())
            self.assertFalse((root / "scripts/constraint-style-baseline.json").exists())
            source.write_text("let gap = PKYLayout.Space.s4")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("primitive-space", result.stderr)
            source.write_text("")
            test.write_text("NSLayoutConstraint.activate([])")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Tests/AnyDockTests/Fixture.swift [activate-block]", result.stderr)
            test.write_text("buildLayout(activate: false)")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("activate-false", result.stderr)

    def test_rejects_retired_options(self):
        with tempfile.TemporaryDirectory() as temp:
            for option in ("--write-baseline", "--base-ref=HEAD"):
                with self.subTest(option=option):
                    result = self.run_check(Path(temp), option)
                    self.assertEqual(result.returncode, 2, result.stderr)

    def run_check(self, root, *args):
        return subprocess.run(
            [sys.executable, "-B", str(STYLE.SCRIPTS / "check-constraint-style.py"),
             "--root", str(root), *args],
            capture_output=True, text=True, env=CLEAN_ENV,
        )


if __name__ == "__main__":
    unittest.main()
