---
id: PAD-33
title: 'Status marks: one static symbol per state, no pulsing'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-28 21:55'
updated_date: '2026-11-06 09:30'
labels:
  - app
  - ui
dependencies: []
priority: medium
type: feature
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The project dot carried two meanings, the sandbox state by color and the agents by pulsing (green while working, orange while waiting), and tabs pulsed the same way. The operator could only tell working from idle by watching the dot for a while. Each state now gets its own static shape, with color as a second cue, shared by the sidebar, cards, toolbar, and tabs. Agreed with the operator on 2026-10-28: needs you (orange exclamation circle, an agent waiting or an approval request), working (green ellipsis circle), finished while unseen (accent checkmark circle), running idle (green dot), changing (grey half dot), stopped (grey ring), problem (red triangle), nothing without a sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One mark per project, the most urgent first: needs you, working, finished unseen, running, changing, problem, stopped, none; decided in PaddockCore (ProjectBadge) and tested
- [x] #2 Agent and host tabs use the same symbols for working, waiting, and finished
- [x] #3 Nothing pulses; entering needs you bounces the symbol once
- [x] #4 Each state differs by shape, not only by color
- [x] #5 Docs UI and Kits (Agent status) describe the marks
- [x] #6 Sidebar row, project card, toolbar, and the Info status row show the same mark; the tooltip says it in words (state and approval requests; agents have their own rows since PAD-63)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PaddockCore ProjectBadge: the mark by priority (needs you, working, finished, running, changing, problem, stopped, none), its words; AgentTabMarks.hasUnseen for the project-level finished.
2. App: ProjectBadgeView (static SF Symbols, one bounce on entering needs you); AppModel.badge(of:) and badgeHelp(of:); sidebar row, card, toolbar, Info Status row use them; the separate orange hand label goes (the badge and tooltip carry approval requests).
3. PaddockShellUI: tab marks use the same symbols; host tab icons get a corner mark; no pulse anywhere.
4. Docs UI (Status marks) and Kits (Agent status, Display).

5. (2026-11-06) AC2 gap: the card has no tooltip and labels its mark with the state only; the toolbar tooltip leaves out approval requests. Both use AppModel.badgeHelp now. AC2's 'agents' dropped: since PAD-63 agents have their own rows and the project mark says nothing about them.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Unknown sbx states: only running and stopped appear in captures; other statuses show as changing, or as a problem when they contain error, fail, dead, unhealthy, or crash. 414 PaddockCore tests pass and PaddockShell builds on Linux; the SwiftUI views compile only on the Mac and need a look.

2026-10-31 Mac check: marks on agent tabs and sidebar rows work, nothing pulses, states differ by shape. Not yet checked: the project card, toolbar and Info status row showing the same mark, and the tooltip wording (AC 2).

2026-11-06: Mac build at e1d2960 succeeded (.tmp/build-runs, 10:29). Operator checked: card, toolbar and Info status row show the sidebar's mark, their tooltips match the sidebar's words, and a waiting approval request is named in each.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Each project has one static mark per state (ProjectBadge, tested in PaddockCore), drawn the same in the sidebar row, card, toolbar and Info's Status row; agent and host tabs use matching symbols; nothing pulses, entering needs you bounces once; states differ by shape. The tooltip and VoiceOver say the state and waiting approval requests everywhere (the card and toolbar were fixed last). Agents moved to their own rows in PAD-63, so the project mark no longer carries their state. Verified on the Mac by the operator.
<!-- SECTION:FINAL_SUMMARY:END -->
