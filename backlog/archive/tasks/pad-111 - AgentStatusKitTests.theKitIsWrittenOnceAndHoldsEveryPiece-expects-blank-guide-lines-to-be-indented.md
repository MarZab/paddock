---
id: PAD-111
title: >-
  AgentStatusKitTests.theKitIsWrittenOnceAndHoldsEveryPiece expects blank guide
  lines to be indented
status: Done
assignee: []
created_date: '2026-11-06 08:47'
updated_date: '2026-11-06 09:22'
labels:
  - tests
  - kits
dependencies: []
priority: medium
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AgentStatusKit indents SandboxGuide.context under content: | and leaves blank lines empty on purpose (YAML allows it), but the test requires every line after content: | to start with 16 spaces. SandboxGuide has blank lines since 943c8a3 (committed without running the tests), so the test fails on the Mac, in Linux, and at 81f2c45.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The test allows empty lines in the guide and still fails for a non-empty line that is not indented
- [x] #2 The written kit still parses as YAML with the guide as the agent-context content
- [x] #3 mise run test passes this test on the Mac and in a sandbox
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: the test split on content: | at 14 spaces, but the kit has it at 6, so it checked the whole file. Fixed in Linux sandbox. AC2 (YAML parse) and AC3 (Mac) still to verify.

AC2: the kit written by AgentStatusKit.install (at ee89c38) parses with PyYAML; its agent-context content equals SandboxGuide.context, 13 blank lines kept. AC3: theKitIsWrittenOnceAndHoldsEveryPiece passed on the Mac (.tmp/test-runs/2026-11-06_10-14-33.log, 85d5464) and in Linux (10-08-26).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The test split the kit on content: | at the wrong indent and so checked the whole file; it now takes the guide after the 6-space marker and allows empty lines while still requiring every other line indented. Verified: the written kit parses as YAML with the guide as agent-context content; the test passes on the Mac and in Linux.
<!-- SECTION:FINAL_SUMMARY:END -->
