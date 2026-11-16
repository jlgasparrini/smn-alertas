#!/bin/sh
# Builds SMN Alertas.app (menu bar agent) with SwiftPM; no Xcode needed.
set -e
cd "$(dirname "$0")"
swift build -c release --product SMNAlertas
APP="build/SMN Alertas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SMNAlertas "$APP/Contents/MacOS/SMNAlertas"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SMN Alertas</string>
  <key>CFBundleIdentifier</key><string>local.smnalertas</string>
  <key>CFBundleExecutable</key><string>SMNAlertas</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature: notifications need a signed bundle with an identifier.
codesign --force --sign - "$APP"
echo "Built $APP"
