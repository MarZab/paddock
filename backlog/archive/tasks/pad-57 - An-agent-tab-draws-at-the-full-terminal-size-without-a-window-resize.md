---
id: PAD-57
title: An agent tab draws at the full terminal size without a window resize
status: Done
assignee:
  - '@claude'
created_date: '2026-10-30 07:38'
updated_date: '2026-10-31 17:52'
labels:
  - app
  - shell
  - bug
dependencies: []
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Opening an agent tab often draws Claude Code for a smaller terminal than the tab; it fills the tab only after the operator resizes the window. SandboxShellSession sends the size again after the program's first output only when the view resized while the run was starting (commit 2330349), so a size reported before the start (the usual order) is never resent; if sbx run does not carry that first size into the sandbox, or the program reads it before it is set, nothing corrects it. A resize by the operator works because it changes the size at every layer. Fix: after the first output, always send the size again on a schedule long enough for a sandbox that is still starting, and on the last send nudge the rows by one and back so the program gets a real change (SIGWINCH) inside the sandbox even when the size there already matched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After an agent session's first output its size is sent again even when the view did not resize while starting
- [x] #2 The last resend changes the rows by one and back, so the program inside the sandbox sees a real size change
- [x] #3 A later run (Run Again) gets the same resends; an earlier run's late resends do nothing
- [x] #4 Checked on the Mac: a new agent tab, on a running and on a stopped sandbox, fills the tab without resizing the window
- [x] #5 doc UI or PaddockShell says how a terminal's size reaches the program
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SandboxShellSession: after the first output always resend the size on resendAfter (1, 3, 8 s), the last one nudged a row shorter and back; skip shells on this Mac; schedule injectable for tests
2. Tests for resend without a resize, the nudge, a stale run, a Mac shell
3. UI doc
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
mise run test passes on Linux (31 PaddockShell tests). Mac check (AC 4) still open: whether sbx forwards a same-size SIGWINCH is unknown, so the nudge at 8 s is what guarantees a real change; an agent that starts later than 8 s after sbx's first output (a slow sandbox boot) would still be missed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
After an agent session's first output Paddock sends the terminal size again (at 1, 3 and 8 s, the last nudged a row shorter and back), so the program sees a real size change and fills its tab without a window resize; Run Again gets the same, a stale run's late resends do nothing. Verified on the Mac 2026-10-31 on running and stopped sandboxes.
<!-- SECTION:FINAL_SUMMARY:END -->
