---
id: PAD-54
title: Do not send punctuation or filler noise to the agent
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 19:26'
updated_date: '2026-10-29 19:26'
labels:
  - voice
dependencies: []
priority: high
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The recognizer turns noise into "." or "Hmm.", and stripping a start word or command can leave a lone comma; hands-free sent those to the agent as prompts. Design: backlog doc Voice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A dictation or typed answer without a letter or digit, or of fillers only, is not sent, does not start the hands-free countdown, and leaves Send disabled; leading punctuation is dropped (DictationText, tests)
- [ ] #2 Hands-free listens again after such a send as after a real one
- [ ] #3 Checked on the Mac: builds, and noise in hands-free never reaches the agent
- [x] #4 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DictationText in PaddockCore with DictationTextTests; App/Voice.swift uses it in send, the countdown, the Send button, typed answers, and the start-word check. App not built here.
<!-- SECTION:NOTES:END -->
