#!/bin/bash
# Build Caffinate.app — a standalone macOS menu bar app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Caffinate"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

echo "Cleaning previous build..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

echo "Compiling Swift sources..."
swiftc -O \
    -framework AppKit \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/main.swift

echo "Copying Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc code signature so macOS will run it locally without Gatekeeper fuss.
echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"
echo "Run with:  open \"$APP_BUNDLE\"   (or move it to /Applications)"
