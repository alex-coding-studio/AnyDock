#!/usr/bin/env python3
import argparse
import importlib.util
import re
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_layout", SCRIPTS / "check-native-layout.py")
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)

ROOTS = (*NATIVE.ROOTS, "Tests")
PATTERNS = {
    "primitive-space": re.compile(r"\bPKYLayout\s*\.\s*Space\s*\."),
    "activate-false": re.compile(r"\bactivate\s*:\s*false\b"),
    "activate-block": re.compile(r"\bNSLayoutConstraint\s*\.\s*activate\s*\("),
}


def file_counts(name, text):
    code = NATIVE.swift_code(text)
    found = {category: count for category, pattern in PATTERNS.items()
             if (count := len(pattern.findall(code)))}
    if not name.startswith("Sources/AnyDock/") or Path(name).name.endswith("Metrics.swift"):
        found.pop("primitive-space", None)
    return found


def counts(sources):
    result = {name: found for name, text in sources if (found := file_counts(name, text))}
    return dict(sorted(result.items()))


def current_counts(root):
    return counts((str(path.relative_to(root)), path.read_text())
                  for directory in ROOTS for path in sorted((root / directory).rglob("*.swift")))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=SCRIPTS.parent)
    args = parser.parse_args()
    root = args.root.resolve()
    actual = current_counts(root)
    if actual:
        print("Legacy constraint style and primitive view spacing are forbidden:", file=sys.stderr)
        for name, categories in actual.items():
            for category, count in categories.items():
                print(f"  {name} [{category}]: {count}", file=sys.stderr)
        return 1
    print("Constraint style check passed: no legacy calls or primitive view spacing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
