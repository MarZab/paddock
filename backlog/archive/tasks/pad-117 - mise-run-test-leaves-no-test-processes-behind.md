---
id: PAD-117
title: mise run test leaves no test processes behind
status: Done
assignee: []
created_date: '2026-11-06 10:19'
updated_date: '2026-11-06 10:20'
labels:
  - tooling
dependencies: []
priority: low
type: chore
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After a timeout or an interrupt, mise run test left PaddockCorePackageTests.xctest processes running (parent gone). They held SwiftPM's build lock, so the next run waited on 'Another instance of SwiftPM' until its own timeout. Found 2026-11-06.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A timeout, an interrupt, or a normal end of mise run test leaves no PackageTests.xctest process of this checkout running
- [x] #2 A stale one from an earlier run is stopped before the next run starts
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
test.sh stops any PackageTests.xctest of this checkout (matched by its command line, anchored so shells that mention the name are left alone) before a run, after each package, and on INT or TERM. Verified in the sandbox: a stale fake process was stopped by the next run, and a 3 s timeout killed the run and left none behind. Not run on the Mac, where swift test starts xctest with the bundle as an argument (the pattern allows that form).
<!-- SECTION:FINAL_SUMMARY:END -->
