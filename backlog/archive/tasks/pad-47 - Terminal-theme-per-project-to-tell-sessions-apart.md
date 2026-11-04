---
id: PAD-47
title: 'Terminal theme per project, to tell sessions apart'
status: Done
assignee: []
created_date: '2026-10-29 11:47'
updated_date: '2026-10-31 17:39'
labels:
  - app
dependencies: []
priority: medium
type: feature
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With several projects open, their terminals look the same and sessions get mixed up. Each project picks a terminal color theme in Info (Terminal row): Default or one of TerminalTheme.all (PaddockShellCore), kept in its project file (terminalTheme, the operator's choice, never from the folder). SandboxTerminalView applies it to every terminal tab of the project, live, and goes back to SwiftTerm's own colors for Default. backlog doc UI, ProjectStore.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TerminalTheme.all: complete palettes, unique ids and backgrounds (tested)
- [x] #2 Project files keep terminalTheme; left out means Default (tested)
- [x] #3 Info's Terminal row picks the theme; every terminal tab of the project changes at once, and Default restores the original colors
- [x] #4 UI and ProjectStore docs updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
App side and the SwiftTerm view are written, not built yet.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Info's Terminal row picks a per-project terminal theme (TerminalTheme.all, kept in the project file); every terminal tab of the project changes at once and Default restores the original colors. Verified on the Mac 2026-10-31 (build + manual check).
<!-- SECTION:FINAL_SUMMARY:END -->
