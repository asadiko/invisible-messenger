#!/bin/bash
# Launches a throwaway copy of the release app with every window open, then checks with ScreenCaptureKit
# that none of them appear in screen captures. Needs Screen Recording permission for your terminal app.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
APP="build/Invisible Messenger.app"
PROFILE=capturecheck
SERVICE=com.asadiko.InvisibleMessenger.$PROFILE

cleanup() {
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true
  rm -rf "$HOME/Library/Application Support/InvisibleMessenger/profiles/$PROFILE"
  for account in identity data-key app-password; do
    security delete-generic-password -s "$SERVICE" -a "$account" >/dev/null 2>&1 || true
  done
  defaults delete "$SERVICE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

swiftc -O scripts/CaptureCheck.swift -o build/capture-check
open -n "$APP" --env "IM_PROFILE=$PROFILE" --env IM_SEED_DEMO=1 --env IM_CAPTURE_DEMO=1
sleep 4
PID=$(pgrep -n -f "$APP/Contents/MacOS/InvisibleMessenger")
build/capture-check "$PID"
