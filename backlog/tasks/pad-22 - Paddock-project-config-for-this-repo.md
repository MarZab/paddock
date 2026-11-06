---
id: PAD-22
title: Paddock project config for this repo
status: In Progress
assignee: []
created_date: '2026-10-25 16:10'
updated_date: '2026-11-06 08:44'
labels:
  - tooling
  - images
dependencies: []
priority: medium
type: chore
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents working on Paddock in a Paddock sandbox need Swift for Linux (swift test on PaddockCore and PaddockShell), the Linux tools in mise.toml (swiftlint, swiftformat, shellcheck, backlog), Node for backlog's npm install, and Python. Since PAD-73.3 the repo describes its sandbox as sbxenv.yaml plus its own v3 kit (tools/sandbox/paddock); image builds (PAD-2) are gone. Commit 943c8a3 replaced the working paddock-dev kit with an empty one, so a new sandbox had none of this and thisRepositorysOwnFilesAreAccepted read a kit that no longer existed. The sandbox image is now Debian 13 (Docker Hardened Images), not Ubuntu 26.04.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tools/sandbox/paddock installs Swift 6.3.3 for Linux (the Debian 12 build, checked against swift.org's signing keys) with its system packages, mise, and Node, and allows only the hosts installing and the tools need
- [x] #2 Each start trusts the workspace's mise config and installs the tools in mise.toml; Xcode-only tools (xcodegen, xcbeautify) are macOS-only in mise.toml, so mise install and every mise run work on Linux
- [x] #3 In the sandbox, mise run test builds outside Packages/*/.build (the Mac's), and the repo's own sbxenv.yaml and kit pass Paddock's checks (thisRepositorysOwnFilesAreAccepted)
- [ ] #4 A sandbox created from sbxenv.yaml (Paddock or sbx env run) has swift 6.3.3, mise, node, and the mise.toml tools on PATH for the agent's non-interactive shell
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. mise.toml: xcodegen and xcbeautify os = [macos]
2. Kit: install hook for apt packages and Swift (download.swift.org, gpg-verified), dockerfile for mise and Node (pinned by digest), PATH with mise shims, startup trusts and installs mise tools, agent context
3. test.sh: --scratch-path ~/.cache/paddock-build on Linux; clean removes it
4. swift-linux: skip when installed (CI keeps it)
5. Fix thisRepositorysOwnFilesAreAccepted for the new kit; CLAUDE.md and tools/tasks/README
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checked in a sandbox with Docker: the template is Ubuntu 26.04 arm64 with node, npm, python3, git, gh, and rg; the apt step works (libstdc++-dev is virtual on 26.04, so build-essential instead). Not checked: the Swift download (download.swift.org was still waiting for approval) and the steps after it.

2026-10-29: in the sandbox, swift build/test and swiftlint failed to start: Swift 6.3.3's Ubuntu 24.04 build (and swiftlint) link libxml2.so.2, and the template's Ubuntu 26.04 has only libxml2.so.16. The Dockerfile now installs noble's libxml2 and libicu74 (only libxml2.so.2, libicuuc.so.74, libicudata.so.74, about 35 MB) into /usr/local/lib/noble-compat with an ld.so.conf entry, downloaded from noble-updates through a private apt state (system sources untouched, signed by the template's archive key). Checked by running the step in this sandbox: ldd finds everything, mise run test passes (466 + 29), swiftlint runs. The image itself is not built yet (no Docker daemon in a claude-code sandbox): AC1 still needs the Mac.

2026-11-06: In this sandbox (Debian 13 arm64): the install hook's script ran as root in about 1 min, gpg Good signature from the Swift 6.x Release Signing Key, swift --version 6.3.3; the startup step wrote the mise config and mise install succeeded; docker build of paddock.dockerfile adds only mise, node, npm, npx, libatomic and the PATH; mise run test: PaddockShell 36/36, PaddockCore 556/558 (forwardsOnlyAllowedHeaders and theKitIsWrittenOnceAndHoldsEveryPiece also fail at HEAD 81f2c45), thisRepositorysOwnFilesAreAccepted passes. swiftlint now runs on Linux and reports 1310 violations, mostly line_length, which .swiftlint.yml (defaults) has had since the first commit. Not checked: a sandbox actually created from the kit (needs sbx on the Mac).
<!-- SECTION:NOTES:END -->
