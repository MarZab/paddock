---
id: PAD-39
title: Spoken agent state announcements
status: To Do
assignee: []
created_date: '2026-10-29 08:07'
updated_date: '2026-10-29 08:29'
labels:
  - voice
  - app
milestone: m-5
dependencies:
  - PAD-35
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: low
type: feature
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With an agent working in the background, the operator wants to hear when it needs them or finishes without watching the status marks. The states already reach the app (PAD-23, backlog doc Kits, Agent status), and the words are Paddock's own, not the agent's, so this needs no voice kit and carries no untrusted text. Design: backlog doc Voice (planned).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per project setting: off, needs you only, or every change (needs you, finished); sounds instead of speech is an option
- [ ] #2 Announcements go through the app-wide speech queue and say the project (and session when there are several), for example "claude-plane is waiting for you"
- [ ] #3 A state that flips back within a short window is not announced, and nothing is announced for the tab the operator is looking at
- [ ] #4 UI doc and Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The rule is in PaddockCore (VoiceAnnouncements.announcement, tested); the app does not call it yet (needs a per-project setting and the previous state per session).
<!-- SECTION:NOTES:END -->
