#!/usr/bin/env bash
#MISE description="Show what sbxenv.yaml and its kit would change in this repo's sandbox; changes nothing"
# tools/sandbox/run.sh plan, the script Paddock writes into every project (SandboxFiles), unchanged;
# see it for the name, the overlay Paddock keeps, and RUN_SANDBOX_NAME / RUN_SANDBOX_OVERLAY.
set -euo pipefail
exec tools/sandbox/run.sh plan "$@"
