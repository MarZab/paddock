---
id: PAD-134
title: >-
  sbx ls lists sbx-kit-builder without workspaces; the whole list failed to
  decode
status: Done
assignee: []
created_date: '2026-11-07 14:45'
updated_date: '2026-11-07 14:47'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 136000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx 0.51 lists its own sbx-kit-builder sandbox (detached, with cpus, memory, memory_mib) with no workspaces and no mounts. SbxSandbox required workspaces, so the whole sbx ls --json failed: 'Could not read <sandbox> from sbx' and a create reported 'Could not create' although it succeeded (seen 2026-11-07, Paddock log). Capture: Fixtures/sbx/ls-kit-builder.json.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SbxSandbox decodes an entry without workspaces (empty list)
- [x] #2 Fixture-based test with the captured sbx-kit-builder entry
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SbxSandbox now decodes an entry without workspaces as none (sbx-kit-builder, sbx's own sandbox). Fixture ls-kit-builder.json captured from sbx 0.51; test sandboxWithoutWorkspaces. Full tests and lint pass.
<!-- SECTION:FINAL_SUMMARY:END -->
