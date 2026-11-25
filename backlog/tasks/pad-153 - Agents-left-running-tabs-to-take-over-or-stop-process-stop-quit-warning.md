---
id: PAD-153
title: 'Agents left running: tabs to take over or stop, process stop, quit warning'
status: In Progress
assignee: []
created_date: '2026-11-25 08:39'
updated_date: '2026-11-25 08:51'
labels: []
dependencies: []
priority: high
type: feature
ordinal: 164000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When Paddock quits, or an agent tab closes, only the sbx client on the Mac ends: the agent process in the sandbox keeps running with no terminal (seen live: an idle claude on pts/1 forty minutes after its tab was gone). sbx cannot attach to a running process again (no exec attach; sbx run --name starts a new agent), but the status kit records each agent's session (Claude's session_id), its tab (PADDOCK_TAB), and its pid, so Paddock can find these agents, resume their conversation in a new tab, and stop the old process. The operator asked for: a tab per left-running session (closing it stops the session; opening it offers to take it over), the same rows in the sidebar, a general process section with stop, stop in the project's Processes tab, and a warning on quit while agents run.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
All four subtasks are done on Linux (PaddockCore tests, lint). Left for the Mac: build the app, then check live that a tab closed and Paddock quit leave agents that show as left running, that Take Over resumes the conversation (sbx run --name N -- --resume ID reaching claude), that Stop and closing the tab stop them, the two Processes changes, and the quit question.
<!-- SECTION:NOTES:END -->
