---
id: PAD-27
title: >-
  Diagnose window corruption and hangs: MetricKit diagnostics, a main-thread
  watchdog, memory in the log
status: In Progress
assignee: []
created_date: '2026-10-27 13:44'
updated_date: '2026-10-28 19:30'
labels:
  - app
  - crash
dependencies: []
priority: high
type: feature
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator sees the whole window go fuzzy (rendering breaks), then nothing responds and the app must be killed. A force quit leaves no crash report, so nothing tells us where it was. Add: (1) MXMetricManager subscriber that writes hang, crash, and CPU/disk diagnostics (call stack trees, JSON) to ~/Library/Logs/Paddock/diagnostics/ on the next launch; (2) a watchdog off the main thread that pings the main actor every second and, when it does not answer for 2 s, logs the stall with its duration and the app's phys_footprint, and writes the main thread's stack via a sample; (3) the app's memory footprint (task_info phys_footprint) and the count of terminal sessions, web views, and open tabs in paddock.log every minute and on each stall. Until then, the operator captures by hand: sample Paddock 10 -file ~/Desktop/paddock-sample.txt; footprint Paddock > ~/Desktop/paddock-footprint.txt; and a spindump if the window is frozen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Diagnostics MetricKit delivers are written under ~/Library/Logs/Paddock/diagnostics/ and listed in the Log window
- [ ] #2 A main-thread stall over 2 s is logged with its duration and memory footprint
- [ ] #3 paddock.log has a memory line per minute with counts of sessions and web views
- [ ] #4 README or doc UI says what to capture when the window breaks
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
mise run hang (scripts/capture-hang.sh) captures by hand: sample, footprint, vmmap, lsof, child processes, Paddock and WindowServer logs, paddock.log tail, the newest Paddock report, optional sudo spindump; into scratch/hangs/<time>/. README says to run it before quitting. Still to do: MetricKit, watchdog, memory lines.

mise run hang also writes heap.txt (heap -s -guessNonObjects): malloc memory per class, largest first, so a footprint like the 1.1 GB of MALLOC_LARGE in scratch/hangs/20261028-195120 can be attributed (terminal scrollback, SwiftTerm buffers, Data).
<!-- SECTION:NOTES:END -->
