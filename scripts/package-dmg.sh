#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT
cp -R dist/BrewDesk.app "$stage_dir/"
xattr -cr "$stage_dir/BrewDesk.app"
codesign --verify --deep --strict "$stage_dir/BrewDesk.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname BrewDesk -srcfolder "$stage_dir" -ov -format UDZO dist/BrewDesk-local.dmg
