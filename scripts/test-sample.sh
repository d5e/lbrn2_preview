#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAMPLE="$PROJECT_DIR/tests/fixtures/2023-girl-engraving-calibration-alpha.lbrn2"
OUTPUT_DIR="$PROJECT_DIR/build/sample-test"

if [ ! -f "$SAMPLE" ]; then
  echo "Missing sample project: $SAMPLE" >&2
  exit 1
fi

"$PROJECT_DIR/scripts/install.sh"
mkdir -p "$OUTPUT_DIR"
xcrun clang -fobjc-arc -framework Cocoa -framework Quartz \
  "$PROJECT_DIR/tools/preview-check.m" \
  -o "$OUTPUT_DIR/preview-check"

qlmanage -t -s 1024 -o "$OUTPUT_DIR" "$SAMPLE"
"$OUTPUT_DIR/preview-check" "$SAMPLE" "$OUTPUT_DIR/full-preview.png"

test -s "$OUTPUT_DIR/2023-girl-engraving-calibration-alpha.lbrn2.png"
test -s "$OUTPUT_DIR/full-preview.png"
echo "Inspect thumbnails and full preview in $OUTPUT_DIR"
