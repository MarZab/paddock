---
id: PAD-115
title: mise run lint and build keep each run's output in .tmp
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06 09:11'
updated_date: '2026-11-06 09:11'
labels:
  - tooling
dependencies: []
priority: low
type: chore
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tests keep each run's output in .tmp/test-runs (PAD-107) so an agent in a sandbox can read a run made on the Mac. Lint and build print only live, so a failure on the Mac has to be pasted. Operator request 2026-11-06.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mise run lint and mise run build write their whole output to .tmp/lint-runs and .tmp/build-runs (<time>.log, latest.log, the newest 20), under a header with the commit and ending with the exit status
- [x] #2 Both tasks still print live and fail when the command fails
- [x] #3 mise run clean removes both folders; README and CLAUDE.md name them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Shared helper tools/tasks/lib/logged.sh. Lint verified in the sandbox (log, latest.log, exit status, header). Build verified only with stand-in xcodebuild and xcbeautify (exit 65 kept, raw log, beautified live); AC1 needs a real build on the Mac.
<!-- SECTION:NOTES:END -->
