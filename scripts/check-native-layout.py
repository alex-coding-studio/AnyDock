#!/usr/bin/env python3
import argparse
import io
import json
import re
import subprocess
import sys
import tarfile
from collections import Counter
from pathlib import Path

ROOTS = ("Sources",)
BASELINE = "scripts/native-layout-baseline.json"
STRING_START = re.compile(r'(#+)?("""|")')
CALL = re.compile(
    r"(?P<anchor>\.\s*constraint\s*\()"
    r"|(?P<item>\bNSLayoutConstraint\s*(?:\.\s*init\s*)?\(\s*item\s*:)"
    r"|(?P<implicit>\.\s*init\s*\(\s*item\s*:)"
    r"|(?P<vfl>\bNSLayoutConstraint\s*\.\s*constraints\s*\(\s*withVisualFormat\s*:)"
    r"|(?P<add>\baddConstraints?\s*\()"
)
ANCHORS = r"(?:top|bottom|leading|trailing|left|right|centerX|centerY|firstBaseline|lastBaseline|width|height)Anchor"
TARGET = re.compile(r"\b(?:equalTo|lessThanOrEqualTo|greaterThanOrEqualTo)\s*:\s*(?:[\w.\[\]?! +\-]+\.)?(" + ANCHORS + r")\s*[,)]")
DIMENSION = r"(?:(?P<item>[\w.\[\]?!]+)\.)?(?P<dimension>widthAnchor|heightAnchor)"


def swift_code(text):
    masked = list(text)
    index = 0
    while index < len(text):
        start = index
        if text.startswith("//", index):
            index = text.find("\n", index)
            if index < 0:
                index = len(text)
        elif text.startswith("/*", index):
            depth = 1
            index += 2
            while index < len(text) and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
        else:
            match = STRING_START.match(text, index)
            if not match:
                index += 1
                continue
            hashes = match[1] or ""
            index += len(match[0])
            end = match[2] + hashes
            escape = "\\" + hashes
            while index < len(text):
                if text.startswith(escape, index):
                    index += len(escape) + 1
                elif text.startswith(end, index):
                    index += len(end)
                    break
                else:
                    index += 1
        for offset in range(start, min(index, len(text))):
            if text[offset] != "\n":
                masked[offset] = " "
    return "".join(masked)


def violations(text):
    code = swift_code(text)
    found = []
    for match in CALL.finditer(code):
        category = match.lastgroup
        start = match.end()
        depth = 1
        end = start
        while end < len(code) and depth:
            depth += (code[end] == "(") - (code[end] == ")")
            end += 1
        if category == "implicit":
            labels = []
            nesting = 0
            argument_start = start
            for token in re.finditer(r"[()[\]{},]", code[start:end]):
                if token[0] in "([{":
                    nesting += 1
                elif token[0] in ")]}":
                    nesting = max(0, nesting - 1)
                elif token[0] == "," and nesting == 0:
                    label = re.match(r"\s*(\w+)\s*:", code[argument_start:start + token.start()])
                    if label:
                        labels.append(label[1])
                    argument_start = start + token.end()
            label = re.match(r"\s*(\w+)\s*:", code[argument_start:end])
            if label:
                labels.append(label[1])
            if labels != ["attribute", "relatedBy", "toItem", "attribute", "multiplier", "constant"]:
                continue
            category = "item"
        if category == "anchor":
            before = re.search(r"\b(" + ANCHORS + r")\s*$", code[:match.start()])
            target_anchor = TARGET.search(code[start:end])
            anchors = [before[1], target_anchor[1]] if before and target_anchor else []
            if any(a in {"leftAnchor", "rightAnchor"} for a in anchors):
                category = "left-right"
            elif any(a in {"firstBaselineAnchor", "lastBaselineAnchor"} for a in anchors):
                category = "baseline"
            elif {"widthAnchor", "heightAnchor"}.issubset(anchors):
                source = re.search(DIMENSION + r"\s*$", code[:match.start()])
                target = re.search(r"\b(?:equalTo|lessThanOrEqualTo|greaterThanOrEqualTo)\s*:\s*" + DIMENSION, code[start:end])
                source_item = (source["item"] or "self").removeprefix("self.") if source else None
                target_item = (target["item"] or "self").removeprefix("self.") if target else None
                if source and target and source_item != target_item:
                    category = "cross-dimension"
        found.append((category, code.count("\n", 0, match.start()) + 1))
    return found


def counts(sources):
    result = {}
    for name, text in sources:
        categories = Counter(category for category, _ in violations(text))
        if categories:
            result[name] = dict(sorted(categories.items()))
    return dict(sorted(result.items()))


def current_counts(root):
    return counts((str(path.relative_to(root)), path.read_text())
                  for directory in ROOTS for path in sorted((root / directory).rglob("*.swift")))


def differences(actual, expected):
    return [f"{name} [{category}]: actual {actual.get(name, {}).get(category, 0)}, baseline {expected.get(name, {}).get(category, 0)}"
            for name in sorted(actual.keys() | expected.keys())
            for category in sorted(actual.get(name, {}).keys() | expected.get(name, {}).keys())
            if actual.get(name, {}).get(category, 0) != expected.get(name, {}).get(category, 0)]


def ratchet(current, previous):
    errors = []
    if current["requirements"]:
        errors.append("Native layout exceptions are not supported.")
    for name, categories in current["counts"].items():
        for category, count in categories.items():
            if count > previous["counts"].get(name, {}).get(category, 0):
                errors.append(f"{name} [{category}]: baseline may only decrease.")
    return errors


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def previous_baseline(root, ref):
    git(root, "rev-parse", "--verify", f"{ref}^{{commit}}")
    if git(root, "ls-tree", "--name-only", ref, BASELINE).strip():
        return json.loads(git(root, "show", f"{ref}:{BASELINE}"))
    archive = git(root, "archive", ref, *ROOTS)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        initial = counts((entry.name, tree.extractfile(entry).read().decode())
                         for entry in tree if entry.isfile() and entry.name.endswith(".swift"))
    return {"requirements": {}, "counts": initial}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--base-ref", default="origin/main")
    parser.add_argument("--write-baseline", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / BASELINE
    baseline = json.loads(path.read_text())
    actual = current_counts(root)
    if args.write_baseline:
        baseline["counts"] = actual
        path.write_text(json.dumps(baseline, indent=2, ensure_ascii=False) + "\n")
    errors = differences(actual, baseline["counts"])
    previous = previous_baseline(root, args.base_ref)
    errors += ratchet(baseline, previous)
    if errors:
        print("Native Auto Layout must migrate to SnapKit:", file=sys.stderr)
        print("\n".join(f"  {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"Native layout baseline matches ({sum(sum(v.values()) for v in actual.values())} calls).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
