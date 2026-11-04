---
id: PAD-81
title: Rename the sbx Processes page to Processes
status: In Progress
assignee: []
created_date: '2026-11-04 15:07'
updated_date: '2026-11-04 15:07'
labels:
  - ui
dependencies: []
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator asked (2026-11-04) for the sidebar's System > sbx Processes page to be called just Processes: the sidebar row, its breadcrumb, File > Processes, the status popover's hint, and the Log category.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The sidebar, breadcrumb, File menu item, status hint, and Log category say Processes
- [x] #2 backlog doc UI says Processes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Renamed in ContentView (sidebar, breadcrumb), PaddockApp (File menu), StatusBarView, ProcessesView, AppModel, and LogCategory.processes; doc-15 updated. Lands in the PAD-73.3 commit. Not built here: check the sidebar and menu on the Mac.
<!-- SECTION:NOTES:END -->
