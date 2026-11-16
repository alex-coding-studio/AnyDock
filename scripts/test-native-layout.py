#!/usr/bin/env python3
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

CLEAN_ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
SCRIPTS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_layout", SCRIPTS / "check-native-layout.py")
LAYOUT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LAYOUT)
FIXTURES = SCRIPTS / "fixtures/native-layout"


class NativeLayoutTests(unittest.TestCase):
    def test_forbidden_and_legal_forms(self):
        found = LAYOUT.violations((FIXTURES / "forbidden.swift.fixture").read_text())
        self.assertEqual(Counter(category for category, _ in found), {
            "anchor": 6, "left-right": 1, "baseline": 2,
            "cross-dimension": 1, "item": 5, "vfl": 1, "add": 2,
        })
        self.assertEqual(found[0][1], 2)
        self.assertEqual(LAYOUT.violations((FIXTURES / "allowed.swift.fixture").read_text()), [])

    def test_scans_all_source_targets_but_not_tests(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ("Sources/AnyDock", "Sources/AnyDockCore", "Tests/AnyDockTests", "Other"):
                path = root / name / "Fixture.swift"
                path.parent.mkdir(parents=True)
                path.write_text("view.topAnchor.constraint(equalTo: host.topAnchor)")
            self.assertEqual(set(LAYOUT.current_counts(root)), {
                "Sources/AnyDock/Fixture.swift", "Sources/AnyDockCore/Fixture.swift",
            })

    def test_cli_checks_sources_without_git(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Sources/Fixture.swift"
            source.parent.mkdir()
            source.write_text("view.snp.makeConstraints { $0.edges.equalToSuperview() }")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / ".git").exists())
            self.assertFalse((root / "scripts/native-layout-baseline.json").exists())
            source.write_text("view.topAnchor.constraint(equalTo: host.topAnchor)")
            result = self.run_check(root)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Sources/Fixture.swift [anchor]", result.stderr)

    def test_rejects_retired_options(self):
        with tempfile.TemporaryDirectory() as temp:
            for option in ("--write-baseline", "--base-ref=HEAD"):
                with self.subTest(option=option):
                    result = self.run_check(Path(temp), option)
                    self.assertEqual(result.returncode, 2, result.stderr)

    def test_fixtures_preserve_host_with_git_environment(self):
        fixtures = (
            ("test-native-layout.py", "NativeLayoutTests"),
            ("test-constraint-style.py", "ConstraintStyleTests"),
        )
        for script, suite in fixtures:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as temp:
                host = Path(temp)
                (host / "host.txt").write_text("host")
                self.git(host, "init", "-q", "--initial-branch=main")
                self.git(host, "add", "host.txt")
                self.git(host, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                         "commit", "-qm", "host")
                index = host / ".git/index"
                head = self.git(host, "rev-parse", "HEAD").stdout
                before_index = index.read_bytes()
                bare = self.git(host, "config", "--local", "core.bare").stdout
                result = subprocess.run(
                    [sys.executable, "-B", str(SCRIPTS / script),
                     suite + ".test_cli_checks_sources_without_git"],
                    cwd=host, capture_output=True, text=True,
                    env={**CLEAN_ENV, "GIT_DIR": str(host / ".git"), "GIT_INDEX_FILE": str(index)},
                )
                self.assertEqual(self.git(host, "rev-parse", "HEAD").stdout, head, result.stderr)
                self.assertEqual(index.read_bytes(), before_index)
                self.assertEqual(self.git(host, "config", "--local", "core.bare").stdout, bare)
                self.assertEqual(result.returncode, 0, result.stderr)

    def run_check(self, root, *args):
        return subprocess.run(
            [sys.executable, "-B", str(SCRIPTS / "check-native-layout.py"), "--root", str(root), *args],
            capture_output=True, text=True, env=CLEAN_ENV,
        )

    def git(self, root, *args):
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, env=CLEAN_ENV)


if __name__ == "__main__":
    unittest.main()
