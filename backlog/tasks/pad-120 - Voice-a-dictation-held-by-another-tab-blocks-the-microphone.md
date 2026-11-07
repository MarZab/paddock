---
id: PAD-120
title: 'Voice: a dictation held by another tab blocks the microphone'
status: Done
assignee: []
created_date: '2026-11-07 09:19'
updated_date: '2026-11-07 14:21'
labels:
  - voice
dependencies: []
documentation:
  - doc-18
type: bug
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator report 2026-11-07: once a dictation was open in one tab, the microphone in another tab did nothing (toggleListening returned while recording was another target), and switching tabs or popups never let the microphone go; hands-free could also listen again into a tab no longer in front. (backlog doc Voice)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking the microphone or Option-Space in a tab closes another tab's dictation (its unsent text dropped, logged) and listens in this one
- [x] #2 Bringing another tab (or a project's non-agent tab) to the front closes a dictation that is not into it
- [x] #3 Hands-free listens on its own only into the tab in front (or for a question outside any tab)
- [x] #4 Voice doc and CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The microphone follows the tab in front: another tab's dictation is closed when the microphone is used or the tab changes, and hands-free listens only into the front tab. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
