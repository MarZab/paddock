#!/usr/bin/env bash
# Gateway trial (backlog doc ModelGateway, Trial without the app).
# The sandbox only ever mounts scratch/trial in this repo.
# Usage: scripts/gateway-trial.sh --model MODEL [--agent opencode] [--name paddock-NAME] [--allow HOST]...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/PaddockCore"
WORKSPACE="$ROOT/scratch/trial"
mkdir -p "$WORKSPACE"
[ -f "$WORKSPACE/README.md" ] || echo "Paddock gateway trial workspace. Safe to delete." > "$WORKSPACE/README.md"

# Build, then run the binary itself (not `swift run`), so Ctrl-C goes straight to the gateway.
swift build --package-path "$PKG" --product paddock-gateway
BIN="$(swift build --package-path "$PKG" --show-bin-path)/paddock-gateway"
exec "$BIN" trial "$@" "$WORKSPACE"
