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

# Apple Silicon (arm64) only.
echo "Compiling Swift sources..."
swiftc -O \
    -framework AppKit \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/main.swift

echo "Copying Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc code signature — required for arm64 apps to launch at all.
# Do NOT swallow errors: an unsigned/invalidly-signed arm64 app is killed by macOS.
echo "Code signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict --verbose=1 "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Run with:  open \"$APP_BUNDLE\"   (or move it to /Applications)"
