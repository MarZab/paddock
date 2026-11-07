---
id: PAD-122
title: Log in the sidebar shows a red dot on an error until the Log is seen
status: Done
assignee: []
created_date: '2026-11-07 09:26'
updated_date: '2026-11-07 14:21'
labels:
  - ui
dependencies: []
type: feature
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: an error that arrives while another page is shown should show on the sidebar's Log item. (backlog doc UI, Log)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Showing the Log page (sidebar, System > Log, Shift-Cmd-L) clears it, and errors while it is shown do not count
- [x] #2 UI doc and CHANGELOG updated
- [x] #3 A red dot on the sidebar's Log (no count) while an error arrived since it was last shown; the label is its own view and changes only when the dot does
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A red dot on the sidebar's Log for errors not seen since it was last shown; the sidebar's labels are views of their own, so network events no longer redraw the window. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
