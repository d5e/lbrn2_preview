#!/bin/bash
set -euo pipefail

DESTINATION="$HOME/Library/QuickLook/LightBurnPreview.qlgenerator"
if [ -e "$DESTINATION" ]; then
  rm -rf "$DESTINATION"
  echo "Removed $DESTINATION"
else
  echo "No installed LightBurn Quick Look generator found."
fi

qlmanage -r
qlmanage -r cache
