#!/bin/bash
# Renders the app icon into Resources/AppIcon.icns.
#   scripts/make-icon.sh            default design (ghost: the fading bubble)
#   scripts/make-icon.sh notch      another design: ghost | notch | eye | glass
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O scripts/make-icon.swift -o build/make-icon
build/make-icon icns "${1:-ghost}" Resources/AppIcon.icns
