#!/bin/bash
# Build Caffinate and install it into /Applications, then launch it.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Caffinate"
SRC="build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# 1. Build a fresh bundle.
./build.sh

# 2. If a copy is already running, quit it so we can replace it cleanly.
if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
    echo "Quitting running instance..."
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
    sleep 1
fi

# 3. Install into /Applications.
echo "Installing to $DEST ..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# 4. Clear the quarantine flag so Gatekeeper doesn't nag about an unverified app.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# 5. Launch it.
echo "Launching..."
open "$DEST"

echo
echo "✅ Installed. Look for the coffee-cup icon in your menu bar."
echo "   Tip: open the menu and toggle \"Launch at Login\" to start it automatically."
