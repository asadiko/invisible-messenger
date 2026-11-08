#!/bin/bash
# Renders the app icon into Resources/AppIcon.icns.
#   scripts/make-icon.sh            default design (notch)
#   scripts/make-icon.sh eye        another design: notch | eye | ghost | glass
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O scripts/make-icon.swift -o build/make-icon
build/make-icon icns "${1:-notch}" Resources/AppIcon.icns
