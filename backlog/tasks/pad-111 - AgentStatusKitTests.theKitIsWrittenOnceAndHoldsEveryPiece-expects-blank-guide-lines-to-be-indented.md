---
id: PAD-111
title: >-
  AgentStatusKitTests.theKitIsWrittenOnceAndHoldsEveryPiece expects blank guide
  lines to be indented
status: To Do
assignee: []
created_date: '2026-11-06 08:47'
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
- [ ] #1 The test allows empty lines in the guide and still fails for a non-empty line that is not indented
- [ ] #2 The written kit still parses as YAML with the guide as the agent-context content
- [ ] #3 mise run test passes this test on the Mac and in a sandbox
<!-- AC:END -->
