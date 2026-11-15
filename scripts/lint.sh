#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--fix" ]]; then
  swift format format --in-place --recursive Sources Tests/SnapDockCoreTests Package.swift
else
  swift format lint --strict --recursive Sources Tests/SnapDockCoreTests Package.swift
fi
python3 -m compileall -q scripts Tests/ShortcutTests
plutil -lint Resources/Info.plist
plutil -lint Sources/SnapDock/Resources/*.lproj/*.strings Sources/SnapDock/Resources/*.lproj/*.stringsdict
