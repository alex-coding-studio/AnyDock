#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

require_version() {
  local pinned
  pinned="$(sed -n "s/^  $2: //p" .github/workflows/ci.yml)"
  if [[ "$("$1" "${@:3}")" != "$pinned" ]]; then
    echo "$1 $pinned is required (pinned in .github/workflows/ci.yml); found $("$1" "${@:3}")." >&2
    exit 1
  fi
}
require_version swiftformat SWIFTFORMAT_VERSION --version
require_version swiftlint SWIFTLINT_VERSION version

baseline_cache="$(mktemp -d "${TMPDIR:-/tmp}/anydock-swiftlint.XXXXXX")"
trap 'rm -rf "$baseline_cache"' EXIT

case "${1:-}" in
  --fix)
    swiftformat Sources Tests Package.swift
    ;;
  --write-baseline)
    echo '[]' > "$baseline_cache/empty.json"
    swiftlint lint --quiet --baseline "$baseline_cache/empty.json" --write-baseline "$baseline_cache/raw.json" > /dev/null || true
    python3 scripts/portable-swiftlint-baseline.py --root "$PWD" --config .swiftlint.yml --record "$baseline_cache/raw.json"
    ;;
  "")
    ;;
  *)
    echo "Usage: ./scripts/lint.sh [--fix|--write-baseline]" >&2
    exit 2
    ;;
esac

swiftformat Sources Tests Package.swift --lint
baseline_path="$(python3 scripts/portable-swiftlint-baseline.py --root "$PWD" --config .swiftlint.yml --output "$baseline_cache/baseline.json")"
swiftlint lint --strict --quiet ${baseline_path:+--baseline "$baseline_path"}
python3 -B scripts/test-native-layout.py
python3 -B scripts/check-native-layout.py
python3 -B scripts/test-constraint-style.py
python3 -B scripts/check-constraint-style.py
python3 -m compileall -q scripts Tests/ShortcutTests
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
plutil -lint Sources/AnyDock/Resources/*.lproj/*.strings Sources/AnyDock/Resources/*.lproj/*.stringsdict
