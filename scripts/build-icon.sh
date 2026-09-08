#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
icon_root="$(mktemp -d)"
trap 'rm -rf "$icon_root"' EXIT
iconset="$icon_root/BrewDesk.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/BrewDesk-icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" assets/BrewDesk-icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o assets/BrewDesk.icns
