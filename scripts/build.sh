#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDKROOT="$(xcrun --sdk macosx10.15 --show-sdk-path 2>/dev/null || xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --find clang)"
BUNDLE="$PROJECT_DIR/build/LightBurnPreview.qlgenerator"

mkdir -p "$BUNDLE/Contents/MacOS"
cp "$PROJECT_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"

"$CLANG" \
  -bundle \
  -fobjc-arc \
  -arch x86_64 \
  -mmacosx-version-min=10.15 \
  -isysroot "$SDKROOT" \
  -I"$SDKROOT/usr/include/libxml2" \
  -framework Foundation \
  -framework QuickLook \
  -framework ImageIO \
  -framework CoreGraphics \
  -framework CoreServices \
  -lxml2 \
  "$PROJECT_DIR/src/LightBurnQuickLook.m" \
  -o "$BUNDLE/Contents/MacOS/LightBurnPreview"

echo "Built $BUNDLE"
