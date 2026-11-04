---
id: PAD-62
title: 'Project mark: the most urgent agent state wins, from the tabs'' own marks'
status: To Do
assignee: []
created_date: '2026-11-01 07:36'
updated_date: '2026-11-01 07:42'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-01 (on hold while an Agents sidebar section is considered, which may replace part of this). Problems: (1) ProjectBadge orders working above finished-unseen, so one working tab hides another that finished and waits for its next prompt. (2) The project uses AgentStates.overall over every reported session (tabless, closed tabs, sessions that died without SessionEnd stay working/waiting up to a day), while tabs use AgentTabMarks, so the two can disagree and a dead session pins the project. (3) showAgentActivity counts a tab as in view when it is its project's selected tab, even when another project is shown or Paddock is in the background, so the usual case (start an agent, switch project) never marks finished. (4) The tooltip names only the top state. Suggested: needs you > finished > working > running; derive the project mark from its tabs' marks plus fresh tabless sessions; in view = project shown and app active; tooltip counts each state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Order is needs you, finished, working, running (test)
- [ ] #2 The project mark is the most urgent of its tabs' marks; a stale tabless or closed-tab session does not set it (test)
- [ ] #3 A tab is in view only while its project is shown and Paddock is active
- [ ] #4 The tooltip counts agents per state
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Superseded by PAD-63 (agents as rows under their project); the tooltip suggestion moved there.
<!-- SECTION:NOTES:END -->
