---
id: PAD-24
title: Terminal tabs keep their view while hidden instead of replaying the scrollback
status: Done
assignee:
  - '@claude'
created_date: '2026-10-27 13:44'
updated_date: '2026-10-31 17:52'
labels:
  - app
  - shell
dependencies: []
priority: high
type: bug
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Switching to a terminal tab (or back from Info, a browser tab, another project) built a new SwiftTerm view and replayed the session's scrollback (up to 2 MB) on the main actor. A full-screen program (Claude Code, OpenCode) draws diffs, and the trimmed scrollback lacks its first full draw (and the alternate screen switch), so the tab often showed a blank page until the program redrew; the replay also stalls the main thread. Each session's terminal view now lives as long as its tab (TerminalViewCache in PaddockShellUI), so showing a tab again only re-parents the view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Showing a terminal tab again shows the screen as it was, without a replay
- [x] #2 Closing a tab releases its view and ends its output task
- [x] #3 A view that was resized while hidden sends the new size when shown (the program redraws)
- [x] #4 Checked on the Mac with Claude Code and OpenCode tabs: switch tabs, projects, and halves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TerminalViewCache in PaddockShellUI, used by ProjectTerminals; released on tab close and terminateAll. AppKit code is not compiled on Linux; needs a Mac build and the AC #4 check.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Terminal tabs keep their SwiftTerm view while hidden (TerminalViewCache in PaddockShellUI) instead of rebuilding it and replaying up to 2 MB of scrollback on the main actor; closing a tab releases its view and output task, and a view resized while hidden sends its size when shown. Verified on the Mac 2026-10-31 with Claude Code and OpenCode: switching tabs, Info, projects and halves.
<!-- SECTION:FINAL_SUMMARY:END -->
