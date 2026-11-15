#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
anydock_iconset="$PWD/.build/Brand.iconset"
mkdir -p "$anydock_iconset"
for anydock_size in 16 32 128 256 512; do
  sips -z "$anydock_size" "$anydock_size" Resources/Brand/AnyDockIcon.png --out "$anydock_iconset/icon_${anydock_size}x${anydock_size}.png" >/dev/null
  anydock_retina=$((anydock_size * 2))
  sips -z "$anydock_retina" "$anydock_retina" Resources/Brand/AnyDockIcon.png --out "$anydock_iconset/icon_${anydock_size}x${anydock_size}@2x.png" >/dev/null
done
iconutil -c icns "$anydock_iconset" -o Resources/AppIcon.icns
