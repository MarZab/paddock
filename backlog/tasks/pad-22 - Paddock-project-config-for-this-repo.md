---
id: PAD-22
title: Paddock project config for this repo
status: In Progress
assignee: []
created_date: '2026-10-25 16:10'
updated_date: '2026-10-29 17:31'
labels:
  - tooling
  - images
dependencies:
  - PAD-2
priority: medium
type: chore
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents working on Paddock in a Paddock sandbox need Swift for Linux (swift test on PaddockCore and PaddockShell), the Linux tools in mise.toml (swiftlint, swiftformat, shellcheck, backlog), and Python. Add .paddock.toml and tools/sandbox/Dockerfile: the claude-code template plus mise and Swift 6.3.3 (the operator's Xcode toolchain; the Ubuntu 24.04 build, since 6.3.3 has none for the template's 26.04). The build context is tools/sandbox only, because the repo with build outputs is about 7 GB and the builder copies the whole context.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Paddock builds the image from .paddock.toml on the Mac
- [ ] #2 In the sandbox, swift --version reports 6.3.3 and mise install installs the Linux tools
- [ ] #3 mise run test passes in the sandbox
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checked in a sandbox with Docker: the template is Ubuntu 26.04 arm64 with node, npm, python3, git, gh, and rg; the apt step works (libstdc++-dev is virtual on 26.04, so build-essential instead). Not checked: the Swift download (download.swift.org was still waiting for approval) and the steps after it.

2026-10-29: in the sandbox, swift build/test and swiftlint failed to start: Swift 6.3.3's Ubuntu 24.04 build (and swiftlint) link libxml2.so.2, and the template's Ubuntu 26.04 has only libxml2.so.16. The Dockerfile now installs noble's libxml2 and libicu74 (only libxml2.so.2, libicuuc.so.74, libicudata.so.74, about 35 MB) into /usr/local/lib/noble-compat with an ld.so.conf entry, downloaded from noble-updates through a private apt state (system sources untouched, signed by the template's archive key). Checked by running the step in this sandbox: ldd finds everything, mise run test passes (466 + 29), swiftlint runs. The image itself is not built yet (no Docker daemon in a claude-code sandbox): AC1 still needs the Mac.
<!-- SECTION:NOTES:END -->
