---
id: PAD-112
title: >-
  Tests that run Node scripts fail on the operator's Mac, plus two timing and
  terminal tests
status: Done
assignee: []
created_date: '2026-11-06 08:47'
updated_date: '2026-11-06 10:08'
labels:
  - tests
dependencies: []
priority: medium
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the Mac run of 2026-11-06 (.tmp/test-runs/2026-11-06_09-32-18.log) ten tests that run Paddock's Node scripts failed, all passing in a Linux sandbox: NodeScriptTests aBrokenShimFirstOnPathIsSkipped (exit 127, the header's no-node exit) and runsWithShToo (no output); AgentStatusKitTests theMergeKeepsWhatIsThereAndDoesNotAddTwice, theWatcherPrintsEachSessionOnceAndForgetsTheEnded, theOpenCodePluginCombinesSessions; VoiceKitTests aQuestionGetsPaddocksAnswer, theAgentMaySayAnythingWhateverVoiceReplyIs, whatTheAgentSaysReachesTheWatcherOnce, aQuestionNobodyAnswersIsTakenBack. NodeScript.header tries node on PATH, then /usr/local/bin/node and /usr/bin/node, so a Mac whose node is only under mise or Homebrew (/opt/homebrew/bin) with a test PATH that leaves it out finds none. Also Mac only: SandboxWatchersTests aWatcherThatEndsEndsTheStream took 4.2 s against a 2 s limit, and PaddockShellCoreTests childSeesATerminalOfTheGivenSize read a 0 0 size (no terminal under mise run?).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cause of the Node failures is found on the Mac (which node the tests get, from what PATH) and the tests pass there without a node in /usr/local/bin
- [x] #2 Tests that need Node say so clearly when there is none, instead of failing on empty output
- [x] #3 aWatcherThatEndsEndsTheStream and childSeesATerminalOfTheGivenSize pass on the Mac under mise run test, or are made independent of load and of a terminal
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mac run 10:12 (.tmp/test-runs/2026-11-06_10-12-09.log), commit 1281f47: still 16 issues in 9 tests. Suspects: (1) NodeScriptTests used the first node on PATH, a version-manager shim when mise manages node, which fails with 127 under a short PATH: now the test asks node for process.execPath (fixed, untested on the Mac). (2) AgentStatusKitTests and VoiceKitTests watcher tests run '/usr/bin/env timeout 2 sh ...' and macOS has no timeout unless coreutils is installed: empty output matches. (3) '/usr/bin/env node' with env HOME only. Still to confirm on the Mac: command -v node timeout.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Causes on the Mac: the first node on PATH was a mise shim that fails (127) under the tests' short PATHs, so NodeScriptTests now ask node for its real path (process.execPath) and the Node-based kit tests use it; macOS has no timeout(1), so the watcher tests stop their process themselves; the OpenCode plugin test raced its helper (steps now wait); the pty size was lost before the child opened the slave (the parent now sets it on a slave it holds). The watcher timing limit is 15 s, since it only has to tell ended from never ending. mise run test also times out (PADDOCK_TEST_TIMEOUT), prints a heartbeat and stamps lines. Verified: Mac run e0f9c1a had both packages at exit 0; Linux full run exit 0 after the last changes.
<!-- SECTION:FINAL_SUMMARY:END -->
