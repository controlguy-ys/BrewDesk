#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$PWD/dist"
build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT
app_dir="$build_root/BrewDesk.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/BrewDesk" "$app_dir/Contents/MacOS/BrewDesk"
cp assets/BrewDesk.icns "$app_dir/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
for bundle in "$bin_dir"/*.bundle; do
  if [ -d "$bundle" ]; then cp -R "$bundle" "$app_dir/Contents/Resources/"; fi
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BrewDesk</string>
<key>CFBundleDisplayName</key><string>BrewDesk</string>
<key>CFBundleIdentifier</key><string>dev.brewdesk.mac</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleIconFile</key><string>BrewDesk.icns</string>
<key>CFBundleExecutable</key><string>BrewDesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
chmod -R u+w "$app_dir"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
rm -rf "$PWD/dist/BrewDesk.app"
mv "$app_dir" "$PWD/dist/BrewDesk.app"
printf 'Built: %s\n' "$PWD/dist/BrewDesk.app"
