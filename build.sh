#!/bin/bash
set -e

# Load local config if exists (gitignored)
if [ -f ".build.local" ]; then
    source .build.local
fi

# Use SIGNING_IDENTITY env var, or fall back to ad-hoc signing
# To keep TCC permissions consistent, create .build.local with:
#   SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

echo "=== Generating Xcode project ==="
xcodegen generate

echo "=== Building Release ==="
xcodebuild -project FirefliesRecorder.xcodeproj -scheme FirefliesRecorder -configuration Release -derivedDataPath build/DerivedData build | grep -E "(error:|warning:|BUILD)" | grep -v "SWIFT_VERSION" || true

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "=== Signing (ad-hoc) ==="
else
    echo "=== Signing with $SIGNING_IDENTITY ==="
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" --entitlements FirefliesRecorder/FirefliesRecorder.entitlements --options runtime build/DerivedData/Build/Products/Release/FirefliesRecorder.app

echo "=== Creating DMG ==="
rm -rf build/dmg-contents
mkdir -p build/dmg-contents
cp -R build/DerivedData/Build/Products/Release/FirefliesRecorder.app build/dmg-contents/
ln -s /Applications build/dmg-contents/Applications
rm -f build/FirefliesRecorder.dmg
hdiutil create -volname "Fireflies Recorder" -srcfolder build/dmg-contents -ov -format UDZO build/FirefliesRecorder.dmg

echo "=== Done ==="
echo "DMG: build/FirefliesRecorder.dmg"
codesign -dv build/DerivedData/Build/Products/Release/FirefliesRecorder.app 2>&1 | grep -E "(Authority|Signature)" | head -2
