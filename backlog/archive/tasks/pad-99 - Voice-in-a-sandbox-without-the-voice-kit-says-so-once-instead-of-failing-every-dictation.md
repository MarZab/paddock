---
id: PAD-99
title: >-
  Voice in a sandbox without the voice kit says so once instead of failing every
  dictation
status: To Do
assignee: []
created_date: '2026-11-06 07:23'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - kits
dependencies: []
priority: medium
type: bug
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator log 2026-11-06 07:59: in one sandbox every voice action failed with executable file paddock-voice not found in PATH (the sandbox predates the voice kit or was created without it), once per dictation and once per agent tab. While sbx was answering 503 after wake, each attempt also logged four sentinel WARN lines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Voice notices a sandbox without paddock-voice and shows one hint naming the fix (Sync / recreate with the voice kit), not one error per dictation
- [ ] #2 sbx WARN lines about the sentinel connection are not logged as voice errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Merged into PAD-36.
<!-- SECTION:NOTES:END -->
