#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/make_shortcut.py --output Resources/Shortcuts/Template.shortcut --no-import-questions
swift build --configuration release --product AnyDock
anydock_bin="$(swift build --configuration release --show-bin-path)"
anydock_app="$PWD/dist/AnyDock.app"
mkdir -p "$anydock_app/Contents/MacOS" "$anydock_app/Contents/Resources"
cp "$anydock_bin/AnyDock" "$anydock_app/Contents/MacOS/AnyDock"
ditto "$anydock_bin/AnyDock_AnyDock.bundle" "$anydock_app/Contents/Resources/AnyDock_AnyDock.bundle"
for anydock_language in en zh-Hans; do
  mkdir -p "$anydock_app/Contents/Resources/$anydock_language.lproj"
  cp "Sources/AnyDock/Resources/$anydock_language.lproj/InfoPlist.strings" \
    "$anydock_app/Contents/Resources/$anydock_language.lproj/InfoPlist.strings"
done
cp Resources/Info.plist "$anydock_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$anydock_app/Contents/Resources/AppIcon.icns"
mkdir -p "$anydock_app/Contents/Resources/Brand"
cp Resources/Brand/AnyDockIcon.png Resources/Brand/MenuBarTemplate.png \
  Resources/Brand/MenuBarTemplate@2x.png "$anydock_app/Contents/Resources/Brand/"
if [[ -d Resources/Shortcuts ]]; then
  ditto Resources/Shortcuts "$anydock_app/Contents/Resources/Shortcuts"
fi
codesign --force --sign - "$anydock_app"
printf '%s\n' "$anydock_app"
