#!/usr/bin/env python3
import argparse
import importlib.util
import io
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_layout", SCRIPTS / "check-native-layout.py")
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)

ROOTS = (*NATIVE.ROOTS, "Tests")
BASELINE = "scripts/constraint-style-baseline.json"
PATTERNS = {
    "activate-false": re.compile(r"\bactivate\s*:\s*false\b"),
    "activate-block": re.compile(r"\bNSLayoutConstraint\s*\.\s*activate\s*\("),
}


def file_counts(text):
    code = NATIVE.swift_code(text)
    return {name: count for name, pattern in PATTERNS.items() if (count := len(pattern.findall(code)))}


def counts(sources):
    result = {name: found for name, text in sources if (found := file_counts(text))}
    return dict(sorted(result.items()))


def current_counts(root):
    return counts((str(path.relative_to(root)), path.read_text())
                  for directory in ROOTS for path in sorted((root / directory).rglob("*.swift")))


def increases(current, previous):
    return [f"{name} [{category}]: {count} > {previous.get(name, {}).get(category, 0)}"
            for name, categories in current.items()
            for category, count in categories.items()
            if count > previous.get(name, {}).get(category, 0)]


def previous_counts(root, ref):
    NATIVE.git(root, "rev-parse", "--verify", f"{ref}^{{commit}}")
    if NATIVE.git(root, "ls-tree", "--name-only", ref, BASELINE).strip():
        return json.loads(NATIVE.git(root, "show", f"{ref}:{BASELINE}"))
    archive = NATIVE.git(root, "archive", ref, *ROOTS)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        return counts((entry.name, tree.extractfile(entry).read().decode())
                      for entry in tree if entry.isfile() and entry.name.endswith(".swift"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=SCRIPTS.parent)
    parser.add_argument("--base-ref", default="origin/main")
    parser.add_argument("--write-baseline", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / BASELINE
    actual = current_counts(root)
    if args.write_baseline:
        path.write_text(json.dumps(actual, indent=2) + "\n")
    errors = NATIVE.differences(actual, json.loads(path.read_text()))
    try:
        errors += increases(actual, previous_counts(root, args.base_ref))
    except subprocess.CalledProcessError:
        errors.append(f"Cannot read base ref {args.base_ref}")
    if errors:
        print("Legacy constraint style may only decrease; write new layout with SnapKit:", file=sys.stderr)
        print("\n".join(f"  {error}" for error in errors), file=sys.stderr)
        return 1
    totals = {category: sum(found.get(category, 0) for found in actual.values()) for category in PATTERNS}
    print("Constraint style baseline matches (" + ", ".join(f"{k} {v}" for k, v in totals.items()) + ").")
    return 0


if __name__ == "__main__":
    sys.exit(main())
