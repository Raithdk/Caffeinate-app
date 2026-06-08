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

# Build a universal binary (arm64 + x86_64) so it runs on both Apple Silicon and Intel.
echo "Compiling Swift sources (universal arm64 + x86_64)..."
swiftc -O -framework AppKit -target arm64-apple-macos13.0  -o "$BUILD_DIR/$APP_NAME-arm64"  Sources/main.swift
swiftc -O -framework AppKit -target x86_64-apple-macos13.0 -o "$BUILD_DIR/$APP_NAME-x86_64" Sources/main.swift
lipo -create -output "$MACOS_DIR/$APP_NAME" "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
rm -f "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

echo "Copying Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc code signature so macOS will run it locally without Gatekeeper fuss.
echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"
echo "Run with:  open \"$APP_BUNDLE\"   (or move it to /Applications)"
