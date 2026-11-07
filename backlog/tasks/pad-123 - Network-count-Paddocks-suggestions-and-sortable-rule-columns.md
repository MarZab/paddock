---
id: PAD-123
title: 'Network: count Paddock''s suggestions, and sortable rule columns'
status: Done
assignee: []
created_date: '2026-11-07 09:26'
updated_date: '2026-11-07 14:21'
labels:
  - ui
dependencies: []
type: feature
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: the Network page should show how many denies Paddock suggests, and the rules table's columns should sort. (backlog doc UI, Network)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The sidebar's Network item shows the number of Paddock's suggestions (none when zero), and the Suggested filter shows it too
- [x] #2 Clicking a column header of the rules table (Network, Filesystem, a project's Info) sorts by it, again to reverse; until then rows keep their scope order
- [x] #3 UI doc and CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The sidebar's Network item and the Suggested filter count Paddock's suggestions; rule tables sort by any column. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
