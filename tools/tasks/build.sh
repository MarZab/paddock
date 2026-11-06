#!/usr/bin/env bash
#MISE description="Build the app; each run's raw xcodebuild output is kept in .tmp/build-runs"
#MISE depends=["generate"]
# The version comes from git (mise run version, backlog doc UI, Version). The log holds xcodebuild's
# own output (what xcbeautify hides), so an agent can read a build made on the Mac.
set -uo pipefail
# shellcheck source=tools/tasks/lib/logged.sh
. tools/tasks/lib/logged.sh

build() {
  # pipefail: the build's status, not xcbeautify's
  xcodebuild -scheme Paddock -destination 'platform=macOS' -derivedDataPath .tmp/build/DerivedData \
    MARKETING_VERSION="$(tools/tasks/version.sh)" CURRENT_PROJECT_VERSION="$(tools/tasks/version.sh build)" \
    PADDOCK_COMMIT="$(tools/tasks/version.sh commit)" build
}

# Live output is beautified; the log keeps the raw output.
if command -v xcbeautify >/dev/null 2>&1; then
  logged_run build build 2>&1 | xcbeautify
  exit "${PIPESTATUS[0]}"
fi
logged_run build build
