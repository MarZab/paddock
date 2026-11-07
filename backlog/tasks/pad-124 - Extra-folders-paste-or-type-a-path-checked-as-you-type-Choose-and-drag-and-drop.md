---
id: PAD-124
title: >-
  Extra folders: paste or type a path, checked as you type, Choose and drag and
  drop
status: Done
assignee: []
created_date: '2026-11-07 09:45'
updated_date: '2026-11-07 14:21'
labels:
  - ui
  - security
dependencies: []
type: feature
ordinal: 128000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: adding an extra folder (project Info, New Project) only opened the Open panel, where pasting a full path needs Shift-Cmd-G. Both places get one field: paste or type a path (a full or ~ path, a file:// URL, Finder's Copy as Pathname, a Terminal-escaped path), checked as typed with the same checks as on add (ExtraFolders, FolderPolicy), Return or Add adds it; Choose... opens the Open panel at the nearest existing folder of what was typed; folders dropped from Finder are added, each checked. The checks at add and at every create stay as they are. (backlog doc UI)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ExtraFolders.path(fromInput:home:) turns pasted text into a full path (trimmed, unquoted, file:// URLs, ~, backslash escapes) or nil; tested
- [x] #2 Info and New Project show the same field: the verdict as typed, Add only when it passes, Return adds, Choose... starts at the nearest existing folder, dropped folders are added after the same check
- [x] #3 Every added folder still passes ExtraFolders.check (FolderPolicy) when added and at every create
- [x] #4 UI doc and CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extra folders from a pasted or typed path (ExtraFolders.path(fromInput:), tested), checked as typed, Choose... and drag and drop, in Info and New Project; later shown as one folders table with a plus button. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
