---
id: PAD-139
title: Publish a port on a host port the operator chooses
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-21 15:18'
updated_date: '2026-11-21 15:19'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Ports card's Add popover publishes a sandbox port with the host port Paddock picks (Ports.mapping: the same number when free in ports.publishRange, else the lowest free). The operator wants to set the other side of the mapping too: an optional host (Mac) port next to the sandbox port, checked like any typed mapping (in ports.publishRange, not a Paddock service, not used by any sandbox), with Paddock's pick when left empty.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Publish in the Add popover has a sandbox port and an optional Mac port field; empty Mac port keeps Paddock's pick
- [x] #2 A chosen host port is refused outside ports.publishRange, when reserved, or when any sandbox (this one too) already publishes it; the sandbox port may be published once
- [x] #3 Tests cover the chosen-host-port mapping
- [x] #4 backlog doc UI, Ports describes it; CHANGELOG line
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Ports.mapping takes an optional hostPort: when given, run Ports.check and refuse a host port this sandbox already publishes. 2. AppModel.publish passes it. 3. NewPortPopover: Sandbox and Mac fields for Publish, Mac empty = auto. 4. Doc UI Ports, CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core tests (publishesOnAChosenHostPort) and lint pass on Linux. The popover (App/PortsViews.swift) is not built or tried yet: needs mise run build on the Mac before AC 1 is checked and the ticket set Done.
<!-- SECTION:NOTES:END -->
