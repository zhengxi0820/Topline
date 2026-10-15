#!/bin/bash
# 打包 Topline.app；--install 时安装到 /Applications 并启动
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Topline.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Topline "$APP/Contents/MacOS/Topline"
cp -R Resources/bin Resources/lib "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Topline</string>
    <key>CFBundleIdentifier</key><string>com.zhengxi.topline</string>
    <key>CFBundleName</key><string>Topline</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "已打包: $APP"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -d /Applications/Topline.app ]]; then
        osascript -e 'tell application id "com.zhengxi.topline" to quit' >/dev/null 2>&1 || true
        sleep 1
        # 只移除本脚本自己安装的同名应用
        rm -rf /Applications/Topline.app
    fi
    cp -R "$APP" /Applications/Topline.app
    open /Applications/Topline.app
    echo "已安装并启动: /Applications/Topline.app"
fi
