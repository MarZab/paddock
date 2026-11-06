#!/usr/bin/env bash
#MISE description="Install Swift for Linux through mise (CI; a sandbox from tools/sandbox/paddock has it already)"
# CI's Swift (.github/workflows/ci.yml, Ubuntu 24.04 on x86_64), through mise. A sandbox created
# from this repo's kit (tools/sandbox/paddock) installs the same version in /opt/swift at create,
# so this does nothing there. The Mac uses Xcode's Swift, so this refuses to run there.
set -euo pipefail

# Keep in step with the operator's Xcode toolchain (Swift 6.3.3 with Xcode 26.6) and with the
# version in tools/sandbox/paddock/paddock.yaml.
SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"

if [ "$(uname -s)" != "Linux" ]; then
  echo "swift-linux is for Linux; the Mac uses Xcode's Swift." >&2
  exit 1
fi

if swift --version 2>/dev/null | grep -q "Swift version $SWIFT_VERSION "; then
  echo "Swift $SWIFT_VERSION is installed already."
  exit 0
fi

MISE_SWIFT_PLATFORM=ubuntu24.04 mise use -g "swift@${SWIFT_VERSION}"
rm -rf "$HOME/.cache/mise"
swift --version
