#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/FernDrop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O mac/Core.swift mac/LAN.swift mac/App.swift mac/main.swift -o "$APP/Contents/MacOS/FernDrop" -framework AppKit -framework WebKit -framework CryptoKit -framework Network -framework Security
cp -R ui "$APP/Contents/Resources/"
bash scripts/build-icon.sh
cp build/FernDrop.icns "$APP/Contents/Resources/FernDrop.icns"
if [ -d vendor/bin ]; then cp -R vendor/bin "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.ferndrop.desktop</string><key>CFBundleName</key><string>FernDrop</string><key>CFBundleExecutable</key><string>FernDrop</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>NSHighResolutionCapable</key><true/><key>NSLocalNetworkUsageDescription</key><string>发现并直接连接你的已配对设备，避免文件绕行公网。</string><key>NSBonjourServices</key><array><string>_ferndrop._tcp</string></array><key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string FernDrop.icns' "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built: $PWD/$APP"
