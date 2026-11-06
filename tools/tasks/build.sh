#!/usr/bin/env bash
#MISE description="Build the app"
#MISE depends=["generate"]
# The version comes from git (mise run version, backlog doc UI, Version).
set -euo pipefail
xcodebuild -scheme Paddock -destination 'platform=macOS' -derivedDataPath .tmp/build/DerivedData \
  MARKETING_VERSION="$(tools/tasks/version.sh)" CURRENT_PROJECT_VERSION="$(tools/tasks/version.sh build)" \
  PADDOCK_COMMIT="$(tools/tasks/version.sh commit)" build | xcbeautify
