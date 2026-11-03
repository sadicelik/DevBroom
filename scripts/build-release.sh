#!/bin/bash
# Builds a universal, ad-hoc signed dist/DevBroom.app and dist/DevBroom.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null)/DevBroom"

rm -rf dist
mkdir -p dist/DevBroom.app/Contents/MacOS dist/DevBroom.app/Contents/Resources
cp "$BIN" dist/DevBroom.app/Contents/MacOS/DevBroom
cp Resources/Info.plist dist/DevBroom.app/Contents/Info.plist

codesign --force --deep --sign - dist/DevBroom.app
ditto -c -k --keepParent dist/DevBroom.app dist/DevBroom.zip
echo "Built dist/DevBroom.app and dist/DevBroom.zip"
