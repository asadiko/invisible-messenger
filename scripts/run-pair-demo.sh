#!/bin/bash
# Launches two separate copies of the built app (profiles "alice" and "bob") to try pairing on one Mac.
# PROFILES="a b" overrides the profile names.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Invisible Messenger.app"
[[ -d "$APP" ]] || { echo "Build first: scripts/build-app.sh"; exit 1; }

EXTRA=()
[[ "${CAPTURABLE:-}" == "1" ]] && EXTRA+=(--env IM_DEV_CAPTURABLE=1)
[[ "${SEED:-}" == "1" ]] && EXTRA+=(--env IM_SEED_DEMO=1)

for profile in ${PROFILES:-alice bob}; do
  open -n "$APP" --env "IM_PROFILE=$profile" ${EXTRA[@]+"${EXTRA[@]}"}
done
