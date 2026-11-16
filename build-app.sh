#!/bin/sh
# Builds SMN Alertas.app (menu bar agent) with SwiftPM; no Xcode needed.
set -e
cd "$(dirname "$0")"
VERSION="${1:-1.0.0}"
# Universal binary: runs on Intel and Apple silicon Macs.
for arch in arm64 x86_64; do
    swift build -c release --product SMNAlertas --triple "$arch-apple-macosx13.0"
done
APP="build/SMN Alertas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
lipo -create -output "$APP/Contents/MacOS/SMNAlertas" \
    .build/arm64-apple-macosx/release/SMNAlertas .build/x86_64-apple-macosx/release/SMNAlertas
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SMN Alertas</string>
  <key>CFBundleIdentifier</key><string>local.smnalertas</string>
  <key>CFBundleExecutable</key><string>SMNAlertas</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature: notifications need a signed bundle with an identifier.
codesign --force --sign - "$APP"
# Release zip; ditto keeps the bundle's signature and metadata intact.
ditto -c -k --keepParent "$APP" "build/SMN-Alertas-$VERSION.zip"
echo "Built $APP and build/SMN-Alertas-$VERSION.zip"
