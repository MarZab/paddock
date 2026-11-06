---
id: PAD-101
title: A closed voice popup keeps its agent silent
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06 07:25'
updated_date: '2026-11-06 10:27'
labels:
  - voice
dependencies: []
priority: medium
type: feature
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-06: when the voice popup is closed, the agent should not be able to speak. Until now anything an agent said (paddock-voice say) opened the popup and was read aloud with voice reply on, so closing the popup did not keep an agent quiet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An agent's say or question is read aloud only while its tab's voice popup is open (and voice reply on, not muted); hands-free does not listen after one that was not read
- [ ] #2 A say no longer opens the popup; it goes to the conversation, seen when the operator opens it. A question still opens the popup, silently
- [ ] #3 Closing the popup cuts off what its agent is saying and drops what waits
- [ ] #4 An agent outside a Paddock tab is never read aloud
- [x] #5 doc Voice describes it
- [ ] #6 The agent is told voice reply is off (--set-status) while its tab's popup is closed, and told again when the popup opens or closes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in App/Voice.swift: receive() speaks and listens hands-free only when panelOpen(for: message.tab); the onChange that opened the popup for a say is gone (questions still open it); closePanel interrupts the tab in SpeechQueue. doc Voice updated. NOT compiled here: needs a Mac build and a try with a say into a closed and an open popup.

AC6: tell() sends voiceReply && popup open; showPanel and closePanel tell the tab's agent when the state changes. NOT compiled.

Merged into PAD-42.
<!-- SECTION:NOTES:END -->
