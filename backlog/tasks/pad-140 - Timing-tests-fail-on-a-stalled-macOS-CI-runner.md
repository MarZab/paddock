---
id: PAD-140
title: Timing tests fail on a stalled macOS CI runner
status: Done
assignee:
  - '@claude'
created_date: '2026-11-21 15:38'
updated_date: '2026-11-21 15:39'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 142000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI run 44919358292 (PR 3, macOS job) failed two tests whose code was unchanged: LlmmanAPI unreachableLlmmanFailsFast (16.5 s against a 15 s wall-clock limit, while every test in the process reported about 14 s, so the process stalled) and SandboxShellSession theStartSizeIsSentAgainAndNudgedOnceTheProgramIsUp (a fixed 500 ms sleep saw only the first of three sizes). Same failure on main acbc52c on 2026-11-07, later green. Tests must wait for the condition, not a fixed time, and not assert wall-clock durations a stall can exceed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 unreachableLlmmanFailsFast checks the refusal, not a wall-clock limit
- [x] #2 SandboxShellSession resend tests wait for the expected sizes with a deadline instead of fixed sleeps
- [x] #3 mise run test passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
unreachableLlmmanFailsFast no longer asserts a wall-clock limit (the Connection refused check already rules out the 2 s connect timeout); the two SandboxShellSession resend tests poll for the expected sizes with a 15 s deadline instead of fixed 200/300/500 ms sleeps. Negative checks (nothing sent) keep their fixed waits, since a stall cannot make them fail. mise run test and lint pass on Linux; CI on the PR will show macOS.
<!-- SECTION:FINAL_SUMMARY:END -->
