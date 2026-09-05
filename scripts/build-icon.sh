#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="ui/assets/app-icon/ferndrop.png"
ICONSET="build/FernDrop.iconset"
mkdir -p "$ICONSET"
# Package the approved artwork at standard macOS resolutions; no redrawing.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/FernDrop.icns
