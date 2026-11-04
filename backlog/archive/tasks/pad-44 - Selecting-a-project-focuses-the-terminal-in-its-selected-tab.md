---
id: PAD-44
title: Selecting a project focuses the terminal in its selected tab
status: Done
assignee:
  - '@claude'
created_date: '2026-10-29 10:40'
updated_date: '2026-10-31 17:52'
labels:
  - app
dependencies: []
priority: medium
type: feature
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Clicking a project in the sidebar left the keyboard in the sidebar list, so typing went nowhere until the operator clicked into the terminal. SandboxTerminalView takes a focus request (a rising number) and makes its terminal the window's first responder, waiting for the window if needed; ProjectTerminals.focusSelectedTerminal asks for it for the left half's selected tab, else the right's; ProjectTabs asks on each project selection. backlog doc UI, Project view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Selecting a project in the sidebar focuses the terminal of its selected tab (left half first) so typing reaches it
- [x] #2 UI doc updated
- [x] #3 When the left half shows Info or a host tab, the right half's selected terminal is focused if it has one; otherwise focus stays where it was
- [x] #4 Selecting a terminal tab in either half's tab bar (or opening a new one) focuses its terminal
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Written; the AppKit view part is not compiled on Linux, not built yet.

Tab selection: ProjectTerminals.setTabs asks for focus whenever the selection is a session tab (click, shown tab again, new tab; open() registers the session before selecting). Not built on the Mac yet.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Selecting a project, or a terminal tab in either half (click, shown again, new tab), focuses that terminal so typing reaches it; with Info or a host tab on the left, the right half's selected terminal gets focus. Verified on the Mac 2026-10-31.
<!-- SECTION:FINAL_SUMMARY:END -->
