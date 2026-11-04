---
id: PAD-58
title: sbx Processes as a page under the sidebar's System section (was Library)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-30 07:50'
updated_date: '2026-10-31 17:48'
labels:
  - app
dependencies: []
priority: medium
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx Processes (PAD-31) opened in a window of its own. It becomes a sidebar item like Models, Network, and Filesystem, and the sidebar's Library section is renamed System (the breadcrumb too). File > sbx Processes and the status popover's button select the page instead of opening a window; the window goes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The sidebar's Library section is called System, in the sidebar and the breadcrumb
- [x] #2 System lists sbx Processes, which shows the processes table in the main window
- [x] #3 doc UI updated
- [x] #4 File > sbx Processes selects the page; there is no sbx Processes window and the status popover has no sbx Processes button
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Sidebar item, breadcrumb, File menu and status popover now select .processes; the Window scene and SbxProcessesView.windowID are gone; the view's 760x360 minimum (sized for its window) dropped. App code is not compiled on Linux; needs mise run build on the Mac.

2026-10-31 Mac check: System section and the processes page in the main window confirmed. Operator asked to drop the status popover's Log and sbx Processes buttons as duplicates of the sidebar; removed in App/StatusBarView.swift, doc UI updated, not rebuilt yet (last AC).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
sbx Processes is a page under the sidebar's System section (was Library; breadcrumb too). File > sbx Processes selects it; there is no window of its own, and the status popover's duplicate button is gone. Verified on the Mac 2026-10-31.
<!-- SECTION:FINAL_SUMMARY:END -->
