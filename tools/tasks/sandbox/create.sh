#!/usr/bin/env bash
#MISE description="Create this repo's sandbox from sbxenv.yaml and its kit; needs --replace, as it replaces one of that name"
#USAGE flag "--replace" help="confirm that a sandbox of that name is replaced"
# tools/sandbox/run.sh create, the script Paddock writes into every project (SandboxFiles), unchanged;
# see it for the name, the overlay Paddock keeps, and RUN_SANDBOX_NAME / RUN_SANDBOX_OVERLAY.
set -euo pipefail
exec tools/sandbox/run.sh create "$@"
