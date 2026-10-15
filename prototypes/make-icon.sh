#!/bin/bash
# 从 icon-final.svg 生成 Resources/AppIcon.icns
# 依赖：Chrome（SVG 渲染）、sips、iconutil（系统自带）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/prototypes/icon-final.svg"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/AppIcon.iconset"

# 1024 母版（squircle 外透明）
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --user-data-dir="$TMP/chrome-profile" \
  --window-size=1024,1024 --default-background-color=00000000 \
  --screenshot="$TMP/icon_1024.png" "file://$SVG" 2>/dev/null

# 全尺寸 iconset
while read -r size name; do
  sips -z "$size" "$size" "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/$name" >/dev/null
done <<'SPECS'
16   icon_16x16.png
32   icon_16x16@2x.png
32   icon_32x32.png
64   icon_32x32@2x.png
128  icon_128x128.png
256  icon_128x128@2x.png
256  icon_256x256.png
512  icon_256x256@2x.png
512  icon_512x512.png
1024 icon_512x512@2x.png
SPECS

iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "已生成: $ROOT/Resources/AppIcon.icns"
