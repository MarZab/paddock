---
id: PAD-132
title: Recreate always in a project's title bar
status: Done
assignee: []
created_date: '2026-11-07 12:44'
updated_date: '2026-11-07 12:44'
labels:
  - ui
dependencies: []
type: feature
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: recreating a sandbox was offered only as Sync's recreate item when Paddock found a difference. The title bar now has Recreate whenever the project has a sandbox, confirmed first. (backlog doc UI, Project Info)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Recreate shows in the project's title bar whenever there is a sandbox, disabled while busy or when the agent is no paddock.yaml entry
- [x] #2 It asks first, saying the terminals close and what is lost (Claude's sessions unless kept), then does what Sync's recreate items do
- [x] #3 UI doc and CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Title bar Recreate button (arrow.triangle.2.circlepath) next to Start/Create, with a confirmation; AppModel.recreateSandbox applies a .recreate SyncItem like Sync does.
<!-- SECTION:FINAL_SUMMARY:END -->
