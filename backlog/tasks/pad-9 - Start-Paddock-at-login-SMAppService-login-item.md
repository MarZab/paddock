---
id: PAD-9
title: Start Paddock at login (SMAppService login item)
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - app
milestone: m-3
dependencies: []
priority: medium
type: feature
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
M6 asks that Paddock starts at login with the hardening checks green. Use SMAppService.mainApp, off by default, switched by the operator.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The operator can turn start at login on and off from the app
- [ ] #2 After a login Paddock starts and its checks turn green with sbx running
- [ ] #3 The setting reflects SMAppService's real status, including when the operator turned it off in System Settings
<!-- AC:END -->
