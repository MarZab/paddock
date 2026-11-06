---
id: PAD-107
title: mise run test keeps each run's output in .tmp/test-runs
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:24'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
dependencies: []
priority: low
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tests run on the operator's Mac (Xcode's Swift), while agents in a sandbox cannot run them (no Swift for linux/arm64). Pasting a failed run's output loses the start and gets cut; a log file in the repo's ignored scratch/ folder lets an agent read the whole run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every mise run test writes its whole output (both packages) to .tmp/test-runs/<time>.log (.tmp/ is gitignored), with the commit, the Swift version, and each package's exit status, and .tmp/test-runs/latest.log points at the newest
- [x] #2 The task still prints the output live and fails when either package fails
- [x] #3 Only the newest 20 runs are kept
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checked in the sandbox with a stand-in swift on PATH (one package failing): output live and in the log with commit, Swift version and each exit status, task exit 1, latest.log points at the run; 25 old logs plus one run leave the newest 20. shellcheck clean. Arguments pass to swift test in both packages.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
mise run test tees each run (both packages, with commit, version, Swift version, and each exit status) into .tmp/test-runs/<time>.log, latest.log points at the newest, the newest 20 are kept, and arguments go to swift test. Both packages run even when the first fails. Used today to read the Mac runs from a sandbox.
<!-- SECTION:FINAL_SUMMARY:END -->
