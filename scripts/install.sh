#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_DIR/scripts/build.sh"

QUICKLOOK_DIR="$HOME/Library/QuickLook"
DESTINATION="$QUICKLOOK_DIR/LightBurnPreview.qlgenerator"
mkdir -p "$QUICKLOOK_DIR"

if [ -e "$DESTINATION" ]; then
  BACKUP="$QUICKLOOK_DIR/LightBurnPreview.qlgenerator.backup-$(date +%Y%m%d%H%M%S)"
  mv "$DESTINATION" "$BACKUP"
  echo "Previous generator preserved at $BACKUP"
fi

ditto "$PROJECT_DIR/build/LightBurnPreview.qlgenerator" "$DESTINATION"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$DESTINATION"
fi

qlmanage -r
qlmanage -r cache
echo "Installed $DESTINATION"
