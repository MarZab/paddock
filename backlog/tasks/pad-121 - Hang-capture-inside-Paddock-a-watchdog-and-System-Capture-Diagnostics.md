---
id: PAD-121
title: 'Hang capture inside Paddock: a watchdog and System > Capture Diagnostics'
status: Done
assignee: []
created_date: '2026-11-07 09:19'
updated_date: '2026-11-07 14:21'
labels:
  - tooling
dependencies: []
type: feature
ordinal: 125000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
mise run hang (tools/tasks/hang.sh) needs a terminal and the repository, and a hang is often gone before it runs. Paddock captures itself instead: a watchdog thread checks every 2 s that the main thread answers and, once it has not for 6 s, captures what mise run hang does (sample, footprint, vmmap, heap, open files, the system log, Paddock's log) into ~/Library/Logs/Paddock/hangs/<time>/, once per hang and at most every 10 minutes; when the main thread answers again the log says how long it was stuck and where the report is. System > Capture Diagnostics captures the same on demand. spindump needs sudo and stays in mise run hang. Release builds have Hardened Runtime, which may keep sample from reading the process: to verify on the Mac.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A watchdog on its own thread (no Swift tasks for detection) captures once when the main thread has not answered for 6 s, at most once per hang and every 10 minutes, and logs on recovery how long it was stuck and where the report is
- [x] #2 System > Capture Diagnostics captures the same on demand and shows the folder in Finder
- [x] #3 The steps and the stuck rule live in PaddockCore (HangCapture, HangWatchdogClock) with tests; commands go through ProcessRunner
- [x] #4 UI doc and CHANGELOG updated; verified on the Mac that sample reads Paddock in a Release build (or the doc says it does not)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PaddockCore HangCapture (steps, capture via ProcessRunner) + HangWatchdogClock (rule), tested.
2. App HangWatchdog thread, recovery log; System > Capture Diagnostics.
3. UI doc, CHANGELOG. On the Mac: build, Capture Diagnostics in Paddock and Paddock Dev, check sample.txt.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A watchdog thread captures Paddock after 6 s without the main thread (HangCapture, HangWatchdogClock in PaddockCore, tested) into ~/Library/Logs/Paddock/hangs/; System > Capture Diagnostics on demand; sample reads Paddock Dev and the Release build. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
