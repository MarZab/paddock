#!/usr/bin/env bash
#MISE description="Install Swift for Linux in a Paddock sandbox (once per sandbox; not in the image)"
# Installs Swift for Linux into a Paddock sandbox (once per sandbox), through mise. It is not in
# the project image: the builder's disk is too small for the toolchain (tools/sandbox/Dockerfile).
# The Mac keeps using Xcode's toolchain, so this refuses to run there.
set -euo pipefail

# Keep in step with the operator's Xcode toolchain (Swift 6.3.3 with Xcode 26.6).
SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"

if [ "$(uname -s)" != "Linux" ]; then
  echo "swift-linux.sh is for the Linux sandbox; the Mac uses Xcode's Swift." >&2
  exit 1
fi

# 6.3.3 has no Ubuntu 26.04 build (the template's), so it uses the 24.04 one; the image carries
# the 24.04 libraries it links (libxml2.so.2, ICU 74; tools/sandbox/Dockerfile).
MISE_SWIFT_PLATFORM=ubuntu24.04 mise use -g "swift@${SWIFT_VERSION}"
rm -rf "$HOME/.cache/mise"
swift --version
