#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/shortcuts Resources/Shortcuts
python3 scripts/make_shortcut.py --output Resources/Shortcuts/Template.shortcut --no-import-questions
python3 scripts/make_shortcut.py --output .build/shortcuts/unsigned.shortcut
shortcuts sign --mode anyone --input .build/shortcuts/unsigned.shortcut --output "Resources/Shortcuts/发送到 Mac.shortcut"
