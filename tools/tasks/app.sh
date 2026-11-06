#!/usr/bin/env bash
#MISE description="Build and open the app"
#MISE depends=["build"]
# Debug builds are Paddock Dev (net.zabreznik.paddock.dev), so the installed Paddock keeps running.
# Quit a running Paddock Dev first, otherwise `open` just brings the old build to the front.
# The quit returns before the app has exited, so wait for it (up to 5 s) before opening.
set -euo pipefail
osascript -e 'tell application id "net.zabreznik.paddock.dev" to quit' 2>/dev/null || true
for _ in $(seq 50); do [ "$(osascript -e 'application id "net.zabreznik.paddock.dev" is running' 2>/dev/null)" = true ] || break; sleep 0.1; done
open ".tmp/build/DerivedData/Build/Products/Debug/Paddock Dev.app"
