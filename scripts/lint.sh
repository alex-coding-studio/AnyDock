#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--fix" ]]; then
  swift format format --in-place --recursive Sources Tests/AnyDockCoreTests Tests/AnyDockTests Package.swift
else
  swift format lint --strict --recursive Sources Tests/AnyDockCoreTests Tests/AnyDockTests Package.swift
fi
python3 -m compileall -q scripts Tests/ShortcutTests
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
plutil -lint Sources/AnyDock/Resources/*.lproj/*.strings Sources/AnyDock/Resources/*.lproj/*.stringsdict
