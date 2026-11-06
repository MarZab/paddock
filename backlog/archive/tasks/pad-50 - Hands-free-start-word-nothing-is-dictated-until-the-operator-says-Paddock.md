---
id: PAD-50
title: 'Hands-free start word: nothing is dictated until the operator says Paddock'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 19:11'
updated_date: '2026-11-06 10:27'
labels:
  - voice
dependencies: []
priority: medium
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With hands-free on, the microphone reopens on its own after every send and after an agent speaks, and dictates everything it hears, so talk in the room (or a call) ends up typed into the agent and sent 4 s later. The operator wants a keyword to start talking. Design: backlog doc Voice, Hands-free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When hands-free opens the microphone into a tab on its own with nothing said yet, nothing heard counts as dictation and nothing is sent until the start word is said; what follows it is the dictation
- [ ] #2 Clicking Listen, Option-Space, answering an agent's question, and resuming a dictation that already holds words need no start word
- [ ] #3 "stop" and "send" said before the start word do nothing; final results before it are dropped, so a long wait does not pile up text
- [x] #4 The start word is 'Paddock' by default, set with the voiceWakeWord app default (empty turns it off), matched without case or punctuation (WakeWord, with tests), and given to recognition as a contextual string
- [ ] #5 The popup's text field says 'Say "Paddock" to start' while it waits; the Hands-free help mentions it
- [ ] #6 Checked on the Mac: builds, and a hands-free conversation needs the word before each new dictation
- [x] #7 Voice doc updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. WakeWord in PaddockCore (match, text after it) with tests.
2. App/Voice.swift: listen(byOperator:) waits for the word for automatic listens into a tab with an empty draft; heard/draft count only text after it; SpeechListener.keepsFinal drops finals before it; commands ignored until it; the word goes into the contextual strings; placeholder and help text.
3. Voice doc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core tested on Linux (WakeWordTests). App/Voice.swift cannot build here (Linux); the Mac build and a real hands-free run are AC6.

Operator asked for "computer" as a second start word: the setting is now a comma-separated list (WakeWords), default "Paddock, computer"; tested in WakeWordTests.

Merged into PAD-38.
<!-- SECTION:NOTES:END -->
