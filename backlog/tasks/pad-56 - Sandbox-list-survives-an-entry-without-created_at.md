---
id: PAD-56
title: Sandbox list survives an entry without created_at
status: Done
assignee:
  - '@claude'
created_date: '2026-10-30 07:34'
updated_date: '2026-11-06 09:26'
labels:
  - bug
dependencies: []
priority: high
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx ls --json (sbx 0.49.2) can list a sandbox without created_at, apparently while it is still being created. SbxSandbox required createdAt, so the whole list failed: 'Could not read paddock-app from sbx: unexpected output from sbx ls --json: DecodingError.keyNotFound createdAt, Path [0]'. A later capture of the same sandbox (running, with created_at and a new ports array) is in Fixtures/sbx/ls-ports.json.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SbxSandbox.createdAt is optional; an sbx ls entry without created_at decodes
- [x] #2 sandboxd's /sandbox entry without created_at decodes too
- [x] #3 The project's Created row shows '-' when sbx gives no creation time
- [x] #4 Fixture ls-ports.json (real capture with ports) decodes, with a test
- [x] #5 doc SbxService notes created_at can be missing
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. createdAt optional in SbxSandbox and the sandboxd wire shape
2. App Created row handles nil
3. Fixture ls-ports.json from the operator's capture (paths anonymized); tests for it and for a missing created_at
4. Update doc SbxService
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tests: mise run test, 481 + 29 passed in the Linux sandbox, including sandboxWithoutCreatedAt, sandboxListWithPorts and aSandboxWithoutCreatedAtIsListed. AC 3 (App/ProjectViews.swift Created row) is changed but still needs mise run build on the Mac. The full mise run lint run in the sandbox scanned 9665 files outside the project; running swiftlint on just the changed files found no new issues.

AC3: the Created row in App/ProjectViews.swift shows '-' when createdAt is nil, and the Mac build at 1281f47 compiles it (.tmp/build-runs/2026-11-06_10-12-41.log). Not seen in the app: sbx leaves created_at out only briefly while a sandbox is being created.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SbxSandbox.createdAt and sandboxd's wire shape make created_at optional, so one entry without it no longer breaks the whole sandbox list; the Created row shows '-'. Tests cover a missing created_at from the CLI and the socket and the real ls-ports.json capture; doc SbxService notes it. The app builds on the Mac; the '-' was not seen live, since the gap lasts only while a sandbox is created.
<!-- SECTION:FINAL_SUMMARY:END -->
