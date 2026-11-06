#!/usr/bin/env bash
#MISE description="Build a Release Paddock and install it into /Applications"
#MISE depends=["generate"]
# The version comes from git (mise run version, backlog doc UI, Version): yymmdd.N, the commit
# count as the build number, and the commit, so the sidebar and About Paddock show which commit is installed.
# Quit the installed Paddock first (not Paddock Dev, which has its own bundle ID), then replace the app.
set -euo pipefail
xcodebuild -scheme Paddock -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .tmp/build/DerivedData MARKETING_VERSION="$(tools/tasks/version.sh)" \
  CURRENT_PROJECT_VERSION="$(tools/tasks/version.sh build)" PADDOCK_COMMIT="$(tools/tasks/version.sh commit)" build | xcbeautify
osascript -e 'tell application id "net.zabreznik.paddock" to quit' 2>/dev/null || true
for _ in $(seq 50); do [ "$(osascript -e 'application id "net.zabreznik.paddock" is running' 2>/dev/null)" = true ] || break; sleep 0.1; done
rm -rf /Applications/Paddock.app
ditto .tmp/build/DerivedData/Build/Products/Release/Paddock.app /Applications/Paddock.app
open /Applications/Paddock.app
