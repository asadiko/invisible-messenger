#!/bin/bash
# Builds Invisible Messenger and assembles a signed .app bundle in build/.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --debug    debug build
# Set SIGN_IDENTITY to choose a signing identity (defaults to the first "Apple Development" one, else ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

swift build -c "$CONFIG" --product InvisibleMessenger
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Invisible Messenger.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/InvisibleMessenger" "$APP/Contents/MacOS/InvisibleMessenger"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP ($CONFIG, signed with: $IDENTITY)"
