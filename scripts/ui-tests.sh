#!/bin/bash
# Runs the end-to-end UI flows: two copies of the app on loopback, every screen driven through
# its real buttons and text fields. Windows open off-screen; it takes about a minute.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product UIFlowRunner
"$(swift build --show-bin-path)/UIFlowRunner"
