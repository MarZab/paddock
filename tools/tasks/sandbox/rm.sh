#!/usr/bin/env bash
#MISE description="Remove this repo's sandbox"
# tools/sandbox/run.sh rm, the script Paddock writes into every project (SandboxFiles), unchanged;
# see it for the name, the overlay Paddock keeps, and RUN_SANDBOX_NAME / RUN_SANDBOX_OVERLAY.
set -euo pipefail
exec tools/sandbox/run.sh rm "$@"
