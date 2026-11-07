---
id: PAD-125
title: 'Extra folders inside ~/Library/Logs: allowed read-only, with a warning'
status: Done
assignee: []
created_date: '2026-11-07 09:53'
updated_date: '2026-11-07 09:53'
labels:
  - security
dependencies: []
type: feature
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: share Paddock's logs folder (~/Library/Logs/Paddock, with its hang captures) with an agent. FolderPolicy refused everything inside ~/Library. Operator chose the narrow exception: inside ~/Library/Logs, for extra folders the operator adds in Paddock only, always read-only. (backlog doc Security rules)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FolderPolicy.check(allowingLogs:) passes a folder inside ~/Library/Logs (not Logs itself, links followed); without it, and for the rest of ~/Library, it refuses as before
- [x] #2 Only ExtraFolders.check opts in: project folders and sbxenv.yaml workspaces never get the exception
- [x] #3 Such a folder is always mounted read-only (at add, at every create, whatever the project file says); its Read-only box cannot be cleared; the field warns
- [x] #4 Tests cover each of these; CLAUDE.md, Security rules doc, CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FolderPolicy gets an opt-in exception for folders inside ~/Library/Logs, used only by ExtraFolders (operator-added extra folders), which forces them read-only; the UI warns and locks the Read-only box. Security rule in CLAUDE.md and doc-14 updated; tests in FolderPolicyTests and ExtraFoldersTests.
<!-- SECTION:FINAL_SUMMARY:END -->
