---
id: PAD-51
title: Listen turned off stays off in hands-free
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 19:13'
updated_date: '2026-11-06 10:27'
labels:
  - voice
dependencies: []
priority: medium
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With hands-free on, the microphone came back by itself after each agent reply, send, or question, even when the operator had turned Listen off. Off should mean off. Design: backlog doc Voice, Hands-free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After the operator turns Listen off (pill, microphone, Option-Space), hands-free does not turn it on after a reply, a send, a question, or a spoken stop, and does not listen for stop while an agent speaks
- [ ] #2 Listening again, or turning hands-free on, ends that
- [ ] #3 Checked on the Mac: builds, and a reply after Listen off leaves the microphone off
- [x] #4 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
App/Voice.swift only (listenTurnedOff); cannot build on Linux, so AC1-3 wait for the Mac.

Merged into PAD-38.
<!-- SECTION:NOTES:END -->
