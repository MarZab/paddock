---
id: PAD-64
title: 'Agent sessions Paddock did not open, under their project'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-01 07:40'
updated_date: '2026-11-04 19:20'
labels: []
dependencies:
  - PAD-63
priority: low
type: feature
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
paddock-agent-watch already reports every Claude Code and OpenCode session in the sandbox; ones Paddock did not open arrive with an empty tab (PADDOCK_TAB unset): an agent typed in a Paddock sandbox shell tab, or started from Sandbox Shell in Terminal, sbx run, or sbx exec outside Paddock. Show them as child rows under their project (PAD-63), after the agent tabs. (1) Started in a Paddock shell tab: tag shell tabs with PADDOCK_TAB too, so the agent inherits it and the row clicks through to that shell tab. Whether sbx exec takes -e/--env is not captured: get sbx exec --help from the Mac into Fixtures first; otherwise start the shell as env PADDOCK_TAB=... bash. (2) Started outside Paddock: a dimmed row (agent, state, time in state), nothing to click. Stale sessions: an agent that is killed or whose terminal closes often sends no SessionEnd, so its last state stays until the day-old cleanup. Rows with a tab go with the tab; rows without one need liveness: the status kit's watcher also reports whether the session's agent process still runs and drops it when not (kit change, reaches sandboxes on recreate). Until then, hide a tabless row idle for over an hour. Display only, like all agent state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Shell tabs carry PADDOCK_TAB (sbx exec -it N env PADDOCK_TAB=... bash, no sbx flag needed), and an agent started in one is a clickable row to that shell tab (test)
- [x] #2 A session whose agent process is gone is reported ended by the watcher and stops showing (test); a tabless row idle over an hour is hidden (test)
- [x] #3 backlog doc Kits, Agent status and doc UI describe it
- [x] #4 An agent started outside Paddock (no tab, process known) is a dimmed, non-selectable row; a session naming a tab Paddock no longer has, or from a kit without the process, gets no row (test)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01: implemented with PAD-63. The state script records the agent's pid (first non-shell parent); the watcher ends sessions whose pid is gone. Shells get PADDOCK_TAB through env, so sbx exec --help was not needed. Not checked on the Mac: that Claude Code's hook process tree gives claude's pid in a real sandbox, and the app build. Sandboxes need a recreate for the kit change.

2026-11-01 operator: agents without tabs showed. Those were sessions of closed tabs or an earlier launch, from a kit with no pid (never ended). Now only no-tab sessions with a known pid are shown.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All acceptance criteria were met; see the implementation notes. Closed in the 2026-11-04 backlog cleanup.
<!-- SECTION:FINAL_SUMMARY:END -->
