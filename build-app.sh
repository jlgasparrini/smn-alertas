#!/bin/sh
# Builds SMN Alertas.app (menu bar agent) with SwiftPM; no Xcode needed.
#   ./build-app.sh 1.4.0         production: universal app + release zip + signed appcast.xml
#   ./build-app.sh 1.4.0 --dev   development: adds "Probar estados" (DEV_TOOLS), no zip, no updates
set -e
cd "$(dirname "$0")"
REPO=jlgasparrini/smn-alertas
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"
ED_KEY=0rtf1dFTvRU2rbhjEE+HESvXr1+R+/DfZRlRnMB/FPk=     # public half; the private one is in the Keychain
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
SPARKLE="$SCRATCH/artifacts/sparkle/Sparkle"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUPublicEDKey</key><string>$ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature: notifications need a signed bundle with an identifier.
codesign --force --deep --sign - "$APP"
if $DEV; then
    echo "Built $APP (development, with Probar estados)"
else
    # Release zip; ditto keeps the bundle's signature and metadata intact.
    ZIP="SMN-Alertas-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "build/$ZIP"
    # Appcast with just the latest version, signed with the Keychain key (Sparkle rejects unsigned updates).
    SIG=$("$SPARKLE/bin/sign_update" --account smn-alertas "build/$ZIP")
    cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SMN Alertas</title>
    <item>
      <title>Versión $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/v$VERSION}/$ZIP" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
    echo "Built $APP, build/$ZIP and build/appcast.xml (upload both to the v$VERSION release)"
fi
