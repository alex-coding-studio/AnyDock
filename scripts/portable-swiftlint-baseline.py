#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse


def materialize(root, baseline, output):
    root = root.resolve()
    data = json.loads(baseline.read_text())
    if not isinstance(data, list):
        raise ValueError("SwiftLint baseline must be an array")
    for entry in data:
        location = entry["violation"]["location"]
        value = location["file"]
        if value.startswith("file://"):
            continue
        relative = Path(value)
        if relative.is_absolute():
            raise ValueError("Portable baseline entries must be repository-relative paths")
        target = (root / relative).resolve()
        if target == root or root not in target.parents:
            raise ValueError("Portable baseline entry escapes the project")
        location["file"] = target.as_uri()
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def record(root, source, baseline):
    root = root.resolve()
    data = json.loads(source.read_text())
    for entry in data:
        location = entry["violation"]["location"]
        target = Path(unquote(urlparse(location["file"]).path)).resolve()
        if root not in target.parents:
            raise ValueError(f"Baseline entry is outside the project: {target}")
        location["file"] = target.relative_to(root).as_posix()
    data.sort(key=lambda entry: (entry["violation"]["location"]["file"], entry["violation"]["location"]["line"] or 0,
                                 entry["violation"]["location"]["character"] or 0, entry["violation"]["ruleIdentifier"]))
    baseline.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def configured_baseline(config):
    if not config.is_file():
        return None
    for line in config.read_text().splitlines():
        match = re.fullmatch(r"baseline:\s*(.*?)\s*", line)
        if not match:
            continue
        value = match[1]
        if not value or value in ("null", "~"):
            return None
        if value.startswith('"'):
            value = json.loads(value)
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1].replace("''", "'")
        else:
            value = value.split(" #", 1)[0].rstrip()
        return (config.parent / value).resolve()
    return None


def main():
    parser = argparse.ArgumentParser(description="Resolve portable SwiftLint baseline entries for the current checkout without changing the tracked baseline")
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--output", type=Path)
    mode.add_argument("--record", type=Path)
    args = parser.parse_args()
    baseline = configured_baseline(args.config)
    if baseline and args.record:
        record(args.root, args.record, baseline)
    elif baseline:
        materialize(args.root, baseline, args.output)
        print(args.output)


if __name__ == "__main__":
    main()
