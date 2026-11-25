---
id: PAD-139
title: Publish a port on a host port the operator chooses
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-21 15:18'
updated_date: '2026-11-25 07:52'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Ports card's Add popover publishes a sandbox port with the host port Paddock picks (Ports.mapping: the same number when free in ports.publishRange, else the lowest free). The operator wants to set the other side of the mapping too: an optional host (Mac) port next to the sandbox port, with Paddock's pick when left empty. A chosen port is not limited to ports.publishRange (the first version was, and the operator could not publish on 8123): it is refused when it is a Paddock service (llmman, gateway ports), a Docker API port, or used by any sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Publish in the Add popover has a sandbox port and an optional Mac port field; empty Mac port keeps Paddock's pick
- [x] #2 Tests cover the chosen-host-port mapping
- [x] #3 backlog doc UI, Ports describes it; CHANGELOG line
- [x] #4 A chosen host port may be outside ports.publishRange; it is refused when it is llmman's, a gateway's or a Docker API port, or when any sandbox (this one too) already publishes it; the sandbox port may be published once
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Ports.mapping takes an optional hostPort: when given, run Ports.check and refuse a host port this sandbox already publishes. 2. AppModel.publish passes it. 3. NewPortPopover: Sandbox and Mac fields for Publish, Mac empty = auto. 4. Doc UI Ports, CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core tests (publishesOnAChosenHostPort) and lint pass on Linux. The popover (App/PortsViews.swift) is not built or tried yet: needs mise run build on the Mac before AC 1 is checked and the ticket set Done.

2026-11-25: the operator hit 'host port 8123 is outside ports.publishRange'. The range now limits only Paddock's picks; Docker API ports are refused explicitly (the range check used to cover them).

Ports, Config and Kits tests and lint pass on Linux.
<!-- SECTION:NOTES:END -->
