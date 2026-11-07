---
id: PAD-131
title: Project Info as a page of cards
status: Done
assignee: []
created_date: '2026-11-07 11:51'
updated_date: '2026-11-07 14:21'
labels:
  - ui
dependencies: []
type: feature
ordinal: 133000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-07: Info's status block grew to about 16 rows mixing state, create-time settings, and appearance. Operator chose two columns of cards and asked to apply the pattern to the whole Info tab: InfoCard (title, symbol, icon actions, gray box) for Status, Agent, Folders, Kits, Resources, Network, Filesystem in an adaptive grid; Ports and Recent Activity across the width; attention, suggestions, and approvals first. (backlog doc UI, Project Info)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every part of Info is an InfoCard; Status, Agent, Folders, Kits, Resources, Network, Filesystem wrap in as many columns as fit, one in a narrow window
- [x] #2 Needs attention, suggestions, and approval requests come first, full width, only when present; Ports and Recent Activity follow across the width
- [x] #3 Nothing that was on Info is lost (terminal theme, sbxenv.yaml Create, Config, Show in Finder, Edit Kits, Review, Processes, port Add, Show All)
- [x] #4 UI doc and CHANGELOG updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Info as cards in two columns (a third, two thirds): Agent with a Sessions line, Status with the sandbox's meters, Network, Ports; the notices, Folders as one table, Kits, Recent Activity. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
