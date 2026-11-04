---
id: PAD-7
title: Show a kit's hosts in the confirmation sheet before create
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - kits
  - network
milestone: m-2
dependencies: []
priority: medium
type: feature
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Kits add their own network rules (sbx marks them provisioned). Today they only show after create as agent kit rules on the Network page (doc: Kits). sbx kit inspect --json can read them; capture a fixture first (mise run m0 or by hand on the Mac).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fixture of sbx kit inspect --json for a kit with network rules is committed, with a typed model and a test
- [ ] #2 The New Project confirmation sheet lists each chosen kit's hosts before create
- [ ] #3 Recreating a project with changed kits shows the new kits' hosts too
<!-- AC:END -->
