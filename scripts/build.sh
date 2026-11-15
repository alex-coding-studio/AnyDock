#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/make_shortcut.py --output Resources/Shortcuts/Template.shortcut --no-import-questions
swift build --configuration release --product SnapDock
snapdock_bin="$(swift build --configuration release --show-bin-path)"
snapdock_app="$PWD/dist/SnapDock.app"
mkdir -p "$snapdock_app/Contents/MacOS" "$snapdock_app/Contents/Resources"
cp "$snapdock_bin/SnapDock" "$snapdock_app/Contents/MacOS/SnapDock"
ditto "$snapdock_bin/SnapDock_SnapDock.bundle" "$snapdock_app/Contents/Resources/SnapDock_SnapDock.bundle"
for snapdock_language in en zh-Hans; do
  mkdir -p "$snapdock_app/Contents/Resources/$snapdock_language.lproj"
  cp "Sources/SnapDock/Resources/$snapdock_language.lproj/InfoPlist.strings" \
    "$snapdock_app/Contents/Resources/$snapdock_language.lproj/InfoPlist.strings"
done
cp Resources/Info.plist "$snapdock_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$snapdock_app/Contents/Resources/AppIcon.icns"
mkdir -p "$snapdock_app/Contents/Resources/Brand"
cp Resources/Brand/SnapDockIcon.png "$snapdock_app/Contents/Resources/Brand/SnapDockIcon.png"
if [[ -d Resources/Shortcuts ]]; then
  ditto Resources/Shortcuts "$snapdock_app/Contents/Resources/Shortcuts"
fi
codesign --force --sign - "$snapdock_app"
printf '%s\n' "$snapdock_app"
