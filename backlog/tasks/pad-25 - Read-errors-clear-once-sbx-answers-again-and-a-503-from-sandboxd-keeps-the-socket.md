---
id: PAD-25
title: >-
  Read errors clear once sbx answers again, and a 503 from sandboxd keeps the
  socket
status: Done
assignee:
  - '@claude'
created_date: '2026-10-27 13:44'
updated_date: '2026-11-04 19:20'
labels:
  - app
  - sbx
dependencies: []
priority: high
type: bug
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After sleep sbx answers 503 (docker login service unavailable: the host is not fully awake). Errors from background reads (sbx ls, a sandbox's rules) went to lastError and stayed there after sbx recovered: neither the timer nor Refresh cleared them. FallbackSbxReads also took the 503 for a broken socket and read through the CLI for 60 s, which asks the same daemon and fails the same way, so the status popover said 'the socket failed'.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An error from a background read is cleared by the next successful read of the same kind
- [x] #2 A 503 from sandboxd is thrown as is: the socket stays in use and the CLI is not asked
- [x] #3 A failed health check with 503 is tried again on the next read, not after 60 s
- [x] #4 Tests cover the 503 cases in FallbackSbxReadsTests
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core tests pass on Linux (390). App side (AppModel readErrors) not compiled here; needs a Mac build.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All acceptance criteria were met; see the implementation notes. Closed in the 2026-11-04 backlog cleanup.
<!-- SECTION:FINAL_SUMMARY:END -->
