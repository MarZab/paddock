---
id: PAD-28
title: sbx commands never block Swift concurrency threads
status: Done
assignee:
  - '@claude'
created_date: '2026-10-28 18:54'
updated_date: '2026-10-28 22:42'
labels:
  - core
  - crash
dependencies: []
documentation:
  - doc-2
priority: high
type: bug
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A hang capture (scratch/hangs/20261028-195120, PAD-27) showed all 18 threads of Swift's cooperative pool blocked in `FoundationProcessRunner.waitForExit` (`Process.waitUntilExit` inside `Task.detached`), while only 3 sbx children were still alive. With the pool exhausted, every async task off the main actor stalls: checks time out ("The checks did not finish: no answer within 30.0 seconds" every few minutes for a day), and buttons and menu items whose actions await an actor do nothing, while the main thread itself stays idle. `Task.detached` runs on the same pool, so every blocking call inside it (waiting for exit, reading the pipes to EOF) holds a thread for the life of the command. Cancelling a caller only terminated a still-running process; a wait that never noticed the exit stayed stuck forever.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Running a command holds no Swift cooperative thread while it waits for output or exit
- [x] #2 A short command still finishes promptly while more commands than the machine has CPU cores are waiting
- [x] #3 Cancelling the caller returns at once with CancellationError and terminates the process, even if it never exits on its own
- [x] #4 Existing ProcessRunner behavior (stdout, stderr, exit code, stdin, environment, large output) is unchanged and tested
- [x] #5 doc ProcessRunner says how commands wait and what cancellation does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FoundationProcessRunner: terminationHandler set before run(); a lock-guarded RunCompletion collects stdout, stderr, and exit status and resumes one checked continuation.
2. Read each pipe and write stdin on a plain Thread of its own (not the cooperative pool, not GCD).
3. Cancellation: onCancel resumes with CancellationError at once and terminates the process; a cancel before launch starts nothing.
4. Tests: a quick command finishes while 2x CPU count blocked commands wait; cancelling throws promptly and kills the process; cancel before start never runs.
5. Update doc ProcessRunner.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tried GCD global queues first: the new test still failed (blocking reads exhaust GCD workers too; capped on Linux, about 64 on macOS). Tried readabilityHandler next: on Linux (swift-corelibs-foundation) EOF is delivered inconsistently (missed when the Pipe object is still alive, or the handle is freed), so it hung. Settled on one Thread per pipe, like PosixTerminalProcess in PaddockShell. Against the old ProcessRunner both new tests fail (quick command took 10.3 s; cancel returned a result and did not stop the process). Full PaddockCore suite: 393 passed, 3 runs, on Linux. Behavior change: a cancelled run now throws CancellationError instead of returning the terminated result; no caller checked exit 15/143. LineStreamer still calls waitUntilExit, but on a GCD thread after EOF, once per long-lived stream; left as is. Linux sandbox note: the mise Swift toolchain needs libxml2.so.2 while the image has .so.16; a symlink on LD_LIBRARY_PATH works.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FoundationProcessRunner no longer blocks Swift concurrency threads: the exit comes through terminationHandler, each pipe is read and stdin written on a thread of its own, and the caller waits on a continuation. Cancelling throws CancellationError at once and terminates the process. Cause: all 18 cooperative threads were stuck in waitUntilExit inside Task.detached (hang capture 2026-10-28), so every actor stalled and buttons did nothing. Tests: a quick command finishes while 2x CPU count commands wait; cancel returns at once and kills; cancel before start runs nothing (both new tests fail against the old runner). Built and run on the Mac.
<!-- SECTION:FINAL_SUMMARY:END -->
