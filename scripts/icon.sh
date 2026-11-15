#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
snapdock_iconset="$PWD/.build/Brand.iconset"
mkdir -p "$snapdock_iconset"
for snapdock_size in 16 32 128 256 512; do
  sips -z "$snapdock_size" "$snapdock_size" Resources/Brand/SnapDockIcon.png --out "$snapdock_iconset/icon_${snapdock_size}x${snapdock_size}.png" >/dev/null
  snapdock_retina=$((snapdock_size * 2))
  sips -z "$snapdock_retina" "$snapdock_retina" Resources/Brand/SnapDockIcon.png --out "$snapdock_iconset/icon_${snapdock_size}x${snapdock_size}@2x.png" >/dev/null
done
iconutil -c icns "$snapdock_iconset" -o Resources/AppIcon.icns
