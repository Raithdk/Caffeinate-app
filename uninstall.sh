#!/bin/bash
# Remove Caffinate: quit it, unregister the login item, delete it from /Applications.
set -euo pipefail

APP_NAME="Caffinate"
DEST="/Applications/$APP_NAME.app"

if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
    echo "Quitting running instance..."
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
    sleep 1
fi

if [ -d "$DEST" ]; then
    echo "Removing $DEST ..."
    rm -rf "$DEST"
    echo "✅ Uninstalled."
else
    echo "Nothing to remove — $DEST not found."
fi

echo "Note: if you enabled \"Launch at Login\", you can also remove it under"
echo "System Settings → General → Login Items."
