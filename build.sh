#!/bin/bash
# 编译并打包 StickyNotes.app, 安装到 /Applications
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release)..."
swift build -c release

APP="build/StickyNotes.app"
echo "==> 打包 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/StickyNotes "$APP/Contents/MacOS/StickyNotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> 签名 (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> 安装到 /Applications ..."
# 先退出正在运行的旧版本
pkill -x StickyNotes 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/StickyNotes.app"
cp -R "$APP" /Applications/

echo "✅ 完成! 运行: open /Applications/StickyNotes.app"
