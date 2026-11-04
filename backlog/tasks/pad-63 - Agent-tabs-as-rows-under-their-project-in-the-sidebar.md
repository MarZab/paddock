---
id: PAD-63
title: Agent tabs as rows under their project in the sidebar
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-01 07:40'
updated_date: '2026-11-01 08:17'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The sidebar's Projects section lists each project's agent tabs as child rows, so each agent shows its own state and the project row no longer has to combine them (the confusion PAD-62 describes). The project row shows only the sandbox's state and its approval requests. Child rows come from the project's agent tabs in its tab-bar order (both halves, left first), so the order is stable and closed tabs never show; a project without agent tabs has no disclosure. Each child row: the tab's name, its mark (needs you, working, finished while not looked at, none), and how long it has been in that state ("waits 3m", from AgentState.time), dimmed when idle. Clicking one selects the project and the tab and focuses its terminal, which clears its finished mark. Projects start expanded; what the operator collapses is remembered across launches. A collapsed project shows one summary mark: the most urgent of its children, needs you > finished > working. Sessions Paddock did not open are PAD-64. Supersedes the aggregation parts of PAD-62 (its problems 2 and 3); its order question survives only for the collapsed summary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each agent tab is a row under its project, in tab-bar order, with its mark and time in state (test)
- [x] #2 The project's mark (sidebar, card, toolbar, Info) shows only the sandbox's state and approval requests, never the agents' (test)
- [ ] #3 Clicking an agent row shows the project, selects the tab, focuses its terminal, and clears its finished mark
- [x] #4 Agents are always listed (no collapsing), so a waiting agent is never hidden
- [ ] #5 A tab counts as looked at only while its project is shown and Paddock is active
- [x] #6 Each agent row's tooltip says its state and time in words (test)
- [x] #7 backlog doc UI (Status marks, Agents in the sidebar) and doc Kits (Agent status) describe it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Core: SidebarAgents.rows (tabs in tab-bar order, then sessions in no open tab), state and time text, help; AgentTabMarks.mark(of:).
2. ProjectBadge: sandbox state and approval requests only (operator 2026-11-01: the project shows sbx's status, not the agents'); no collapsing.
3. App: ProjectTerminals.sidebarAgents, select(tab:), setOnScreen; AppModel.shownProject and app active; ContentView agent rows, SidebarSelection.agent.
4. Docs: UI, Kits.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01: implemented; core tests pass on Linux. The app is not built yet (no Xcode here): AC 3 and 5 need the Mac (clicking a row, the on-screen rule).

2026-11-01 operator: rows show the tab's title as the tab bar does (program title, else the tab name); tab name in the tooltip.
<!-- SECTION:NOTES:END -->
