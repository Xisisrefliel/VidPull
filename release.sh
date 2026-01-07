#!/bin/bash

set -e

echo "=== VidPull Release Script ==="
echo ""

cd "$(dirname "$0")"

if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

if ! command -v create-dmg &> /dev/null; then
    echo "create-dmg not found. Installing via Homebrew..."
    brew install create-dmg
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Building Release version..."
xcodebuild -project VidPull.xcodeproj \
    -scheme VidPull \
    -configuration Release \
    -derivedDataPath build \
    build

APP_PATH="build/Build/Products/Release/VidPull.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

echo ""
echo "Creating DMG..."
create-dmg \
    --volname "VidPull" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "VidPull.app" 150 200 \
    --app-drop-link 450 200 \
    "VidPull.dmg" \
    "$APP_PATH"

echo ""
echo "=== Release Complete ==="
echo ""
echo "DMG created: VidPull.dmg"
echo ""
echo "To distribute:"
echo "  - Zip the .dmg file for easier distribution"
echo "  - Users may need to right-click and select 'Open' on first launch"
echo "  - Or run: xattr -cr VidPull.app"
