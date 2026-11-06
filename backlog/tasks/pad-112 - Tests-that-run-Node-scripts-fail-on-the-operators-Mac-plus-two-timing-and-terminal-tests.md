---
id: PAD-112
title: >-
  Tests that run Node scripts fail on the operator's Mac, plus two timing and
  terminal tests
status: To Do
assignee: []
created_date: '2026-11-06 08:47'
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
- [ ] #1 The cause of the Node failures is found on the Mac (which node the tests get, from what PATH) and the tests pass there without a node in /usr/local/bin
- [ ] #2 Tests that need Node say so clearly when there is none, instead of failing on empty output
- [ ] #3 aWatcherThatEndsEndsTheStream and childSeesATerminalOfTheGivenSize pass on the Mac under mise run test, or are made independent of load and of a terminal
<!-- AC:END -->
