---
id: PAD-52
title: Chimes when the microphone hears a start word or a spoken stop
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 19:20'
updated_date: '2026-11-06 10:27'
labels:
  - voice
dependencies: []
priority: medium
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In hands-free the operator often is not looking at the screen, so they cannot tell whether Paddock heard the start word or their "stop". A short sound for each tells them. Design: backlog doc Voice, Hands-free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hearing a start word plays one sound, a spoken stop or cancel (dictating, or over an agent being read aloud) another; nothing while muted
- [ ] #2 Checked on the Mac: builds, both sounds play once each, and the chime is not transcribed into the dictation
- [x] #3 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
App/Voice.swift (Chime, NSSound Pop and Bottle); not built here (Linux).

Merged into PAD-38.
<!-- SECTION:NOTES:END -->
