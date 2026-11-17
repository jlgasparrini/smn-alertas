#!/bin/sh
# Builds SMN Alertas.app (menu bar agent) with SwiftPM; no Xcode needed.
#   ./build-app.sh 1.1.0         production: universal app + release zip
#   ./build-app.sh 1.1.0 --dev   development: adds "Probar estados" (DEV_TOOLS), no zip
set -e
cd "$(dirname "$0")"
VERSION="${1:-1.0.0}"
DEV=false
[ "$2" = "--dev" ] && DEV=true

FLAGS=""
SCRATCH=.build
if $DEV; then
    FLAGS="-Xswiftc -DDEV_TOOLS"
    SCRATCH=.build-dev          # separate cache so switching builds doesn't recompile everything
fi

# Universal binary: runs on Intel and Apple silicon Macs.
for arch in arm64 x86_64; do
    swift build -c release --product SMNAlertas --triple "$arch-apple-macosx13.0" --scratch-path "$SCRATCH" $FLAGS
done
APP="build/SMN Alertas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"     # regenerate with: swift scripts/make-icon.swift
lipo -create -output "$APP/Contents/MacOS/SMNAlertas" \
    "$SCRATCH/arm64-apple-macosx/release/SMNAlertas" "$SCRATCH/x86_64-apple-macosx/release/SMNAlertas"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SMN Alertas</string>
  <key>CFBundleIdentifier</key><string>local.smnalertas</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
if $DEV; then
    echo "Built $APP (development, with Probar estados)"
else
    # Release zip; ditto keeps the bundle's signature and metadata intact.
    ditto -c -k --keepParent "$APP" "build/SMN-Alertas-$VERSION.zip"
    echo "Built $APP and build/SMN-Alertas-$VERSION.zip"
fi
