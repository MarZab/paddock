---
id: PAD-6
title: Check the browser kit's open points on the Mac
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - browser
  - kits
  - verify
milestone: m-2
dependencies: []
priority: high
type: task
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The browser tab works live, but some points from the design were never checked on the Mac (doc: Browser). Check each and fix or write down what differs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 sbx 0.49.2 takes the v2 mixin with ports and setup.startup next to Paddock's v1 kits
- [ ] #2 Digest references work with --kit
- [ ] #3 The memory a sandbox with Chromium needs is known and written in the Browser doc
- [ ] #4 Whether another sandbox with a global loopback allow can reach the dashboard's host port is known; if it can, that port is denied like a gateway port, with a test
<!-- AC:END -->
