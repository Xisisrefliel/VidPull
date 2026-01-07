#!/bin/bash

set -e

echo "=== VidPull Setup Script ==="
echo ""

cd "$(dirname "$0")"

if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Building project..."
xcodebuild -project VidPull.xcodeproj \
    -scheme VidPull \
    -configuration Debug \
    build

echo ""
echo "=== Build Complete ==="
echo ""
echo "To run the app:"
echo "  1. Open VidPull.xcodeproj in Xcode"
echo "  2. Press Cmd+R to run"
echo ""
echo "Note: Make sure yt-dlp is installed on your system:"
echo "  brew install yt-dlp"
echo ""
echo "The app will appear in your menu bar with a download icon."
