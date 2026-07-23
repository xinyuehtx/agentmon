#!/usr/bin/env bash
# Package agentmon into a macOS .app bundle and zip it into dist/.
# Usage: ./scripts/package.sh [version]
set -euo pipefail

APP_NAME="agentmon"
CONFIG="release"
VERSION="${1:-0.1.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="dist/${APP_NAME}.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
# 主程序与上报器同放 Contents/MacOS —— App 运行时按同目录定位 agentmon-hook
cp "$BIN_DIR/${APP_NAME}" "$MACOS/${APP_NAME}"
cp "$BIN_DIR/${APP_NAME}-hook" "$MACOS/${APP_NAME}-hook"

# 应用图标（若缺失则现场生成）
ICON="Sources/App/Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
  echo "==> Generating icon"
  swift scripts/make-icon.swift
fi
cp "$ICON" "$RES/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>agentmon</string>
    <key>CFBundleIdentifier</key><string>com.agentmon.app</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>agentmon</string>
</dict>
</plist>
PLIST

echo "==> Zipping"
( cd dist && ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip" )
echo "==> Done: dist/${APP_NAME}.zip"
