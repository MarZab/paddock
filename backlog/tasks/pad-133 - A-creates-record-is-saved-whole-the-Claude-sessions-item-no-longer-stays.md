---
id: PAD-133
title: 'A create''s record is saved whole: the Claude sessions item no longer stays'
status: Done
assignee: []
created_date: '2026-11-07 12:48'
updated_date: '2026-11-07 12:48'
labels:
  - sync
dependencies: []
type: bug
ordinal: 135000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator report 2026-11-07: the Claude sessions notice never hid. AppModel.recordCreated saved only sandboxKits and sandboxEnvironment from ProjectRunner.create's result, and only when one of those changed: sandboxClaudeSessions (PAD-127) and sandboxEnvironmentRecord (PAD-103's 'what changed since the create') were never saved, so Sync kept comparing against nothing. Project.recordingCreate now takes every create-time field, tested. A sandbox recreated before this fix needs one more recreate to be recorded. (backlog doc App config, Sync)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Project.recordingCreate takes sandboxKits, sandboxEnvironment, sandboxEnvironmentRecord, and sandboxClaudeSessions; nil when none differ
- [x] #2 After a recreate is recorded, Sync shows no claude-sessions item; tested
- [x] #3 CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
recordCreated uses Project.recordingCreate (PaddockCore, tested), which takes all four create-time fields; the missing two kept Sync items after a recreate.
<!-- SECTION:FINAL_SUMMARY:END -->
