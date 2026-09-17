#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/FernDropMemoryTest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O mac/Core.swift mac/LAN.swift mac/App.swift tests/memory/main.swift -o "$APP/Contents/MacOS/FernDropMemoryTest" -framework AppKit -framework WebKit -framework CryptoKit -framework Network -framework Security
cp -R ui "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.ferndrop.memory-test</string><key>CFBundleExecutable</key><string>FernDropMemoryTest</string></dict></plist>
PLIST
"$APP/Contents/MacOS/FernDropMemoryTest"
