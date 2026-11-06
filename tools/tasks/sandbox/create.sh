#!/usr/bin/env bash
#MISE description="Create this repo's sandbox from sbxenv.yaml and its kit (--replace removes the existing one first)"
#USAGE flag "--replace" help="remove the sandbox of that name first (sbx env rm), then create it again"
#USAGE flag "--force" help="with --replace: remove it even while in use (an open session or agent in it ends)"
# tools/sandbox/run.sh, the script Paddock writes into every project (SandboxFiles); see it for the
# name, the overlay Paddock keeps, and RUN_SANDBOX_NAME / RUN_SANDBOX_OVERLAY. sbx env create never
# replaces a sandbox, so --replace removes it first; a kit change takes effect only then.
set -euo pipefail
replace=0
force=()
for arg in "$@"; do
  case "$arg" in
    --replace) replace=1 ;;
    --force) force=(--force) ;;
    *) echo "unknown argument: $arg (usage: mise run sandbox:create [--replace [--force]])" >&2; exit 2 ;;
  esac
done
if [ "$replace" = 1 ]; then
  tools/sandbox/run.sh rm ${force[@]+"${force[@]}"}
elif [ "${#force[@]}" -gt 0 ]; then
  echo "--force goes with --replace" >&2
  exit 2
fi
exec tools/sandbox/run.sh create
