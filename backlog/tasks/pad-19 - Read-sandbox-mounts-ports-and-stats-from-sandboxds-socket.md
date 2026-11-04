---
id: PAD-19
title: 'Read sandbox mounts, ports, and stats from sandboxd''s socket'
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - sbx
  - core
milestone: m-3
dependencies: []
priority: low
type: feature
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SandboxdReads does not map runtime_mounts with a value, ports (only empty lists were captured), or stats (sbx's TUI runs a shell one-liner per sandbox through POST /sandbox/N/exec) (doc: SbxService, Fast reads). CPU and memory, which sbx's dashboard shows, are in no JSON captured so far. Capture fixtures with scripts/socket-capture.py first; Paddock sends only GETs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixtures for a sandbox with a mount and published ports are captured over the socket, with typed models and tests
- [ ] #2 The Filesystem page and ports read them from the socket when it is up
- [ ] #3 Whether CPU and memory can be read without POST is decided and written in the SbxService doc
<!-- AC:END -->
