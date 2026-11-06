---
id: PAD-38
title: Hands-free voice mode per agent session
status: In Progress
assignee: []
created_date: '2026-10-29 08:07'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - app
milestone: m-5
dependencies:
  - PAD-37
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: medium
type: feature
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For a real spoken back-and-forth with an agent (away from the keyboard), the operator switches a session into hands-free mode: after the agent speaks or asks, Paddock listens on its own and sends what was said when the operator stops talking. Only the operator turns the mode on; it is the only case where the microphone opens without a key press, so it must be obvious and easy to leave. Outside hands-free mode, an ask waits for the operator to press the key. Design: backlog doc Voice (planned).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Nothing an agent sends can turn hands-free on: no voice message kind is about it (test)
- [ ] #2 Hands-free is turned on only by the operator (the pill, the microphone's menu) and is not remembered across launches
- [ ] #3 After a say or a question has been read out the app listens on its own (behind a start word), and sends the text or answers the question after the operator stops talking, without a key press
- [ ] #4 The Hands-free pill shows it is on, and the microphone indicator shows whenever it listens
- [ ] #5 Hands-free turns itself off after an idle time without the operator speaking (default 20 min; 5, 10, 20, 60, or never in the microphone's menu; speech before a start word does not count) and when Paddock goes to the background unless kept on; each is logged (HandsFreeLimits, tests)
- [ ] #6 Checked on the Mac: builds, the idle limit and the background limit each end hands-free, and a relaunch starts with it off
- [x] #7 Voice doc updated
- [ ] #8 (was PAD-50) When hands-free opens the microphone into a tab on its own with nothing said yet, nothing heard counts as dictation and nothing is sent until the start word is said; what follows it is the dictation
- [ ] #9 (was PAD-50) Clicking Listen, Option-Space, answering an agent's question, and resuming a dictation that already holds words need no start word
- [ ] #10 (was PAD-50) "stop" and "send" said before the start word do nothing; final results before it are dropped, so a long wait does not pile up text
- [x] #11 (was PAD-50) The start word is 'Paddock' by default, set with the voiceWakeWord app default (empty turns it off), matched without case or punctuation (WakeWord, with tests), and given to recognition as a contextual string
- [ ] #12 (was PAD-50) The popup's text field says 'Say "Paddock" to start' while it waits; the Hands-free help mentions it
- [ ] #13 (was PAD-50) Checked on the Mac: builds, and a hands-free conversation needs the word before each new dictation
- [x] #14 (was PAD-50) Voice doc updated
- [ ] #15 (was PAD-51) After the operator turns Listen off (pill, microphone, Option-Space), hands-free does not turn it on after a reply, a send, a question, or a spoken stop, and does not listen for stop while an agent speaks
- [ ] #16 (was PAD-51) Listening again, or turning hands-free on, ends that
- [ ] #17 (was PAD-51) Checked on the Mac: builds, and a reply after Listen off leaves the microphone off
- [x] #18 (was PAD-51) Voice doc updated
- [ ] #19 (was PAD-52) Hearing a start word plays one sound, a spoken stop or cancel (dictating, or over an agent being read aloud) another; nothing while muted
- [ ] #20 (was PAD-52) Checked on the Mac: builds, both sounds play once each, and the chime is not transcribed into the dictation
- [x] #21 (was PAD-52) Voice doc updated
- [ ] #22 (was PAD-53) Music plays only while hands-free waits for a start word after the operator spoke, the tab's agent reports working (status kit), and at least 3 s have passed; it fades out when the start word is heard, the agent stops working, or the microphone goes off
- [ ] #23 (was PAD-53) It plays through the shared engine only with echo cancellation, so the recognizer does not hear it and it never turns the microphone on by itself
- [x] #24 (was PAD-53) Generated in PaddockCore (WaitingMusic): fades in, stays under a fixed ceiling, and after a minute thins to a soft note every 8 s; the renderer fades out without locks on the audio thread (tests)
- [ ] #25 (was PAD-53) Waiting Music toggle in the microphone's menu (voiceWaitingMusic, on by default); nothing while muted
- [ ] #26 (was PAD-53) Checked on the Mac: builds, music plays during a hands-free wait, the start word is still recognized over it, and it does not end up in the dictation
- [x] #27 (was PAD-53) Voice doc updated
- [ ] #28 (was PAD-54) A dictation or typed answer without a letter or digit, or of fillers only, is not sent, does not start the hands-free countdown, and leaves Send disabled; leading punctuation is dropped (DictationText, tests)
- [ ] #29 (was PAD-54) Hands-free listens again after such a send as after a real one
- [ ] #30 (was PAD-54) Checked on the Mac: builds, and noise in hands-free never reaches the agent
- [x] #31 (was PAD-54) Voice doc updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PaddockCore HandsFreeLimits: idle minutes (default 20, 0 = never, clamped), keep in background; reason(idleFor:appActive:) says why hands-free must turn off. Tests.
2. VoiceMessage test: nothing an agent can send turns hands-free on (no kind for it).
3. App/Voice.swift: hands-free is not remembered across launches; a check every 15 s turns it off after the idle time without the operator speaking; it turns off when Paddock goes to the background unless kept; each time it turns itself off is logged (voice category); idle time and keep-in-background are in the microphone's menu.
4. Rewrite the criteria to the design that shipped (one app-wide switch in the popup and mic menu, not per session), update Voice and UI docs.
5. Mac check, then close.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
First part (with PAD-37's panel): a Hands-free checkbox in the dictation panel (app-wide, voiceHandsFree, told to agents via paddock-voice status) sends 5 s after the last speech result, with a countdown; pausing, editing, or "stop" said as its own sentence (StopWord, PaddockCore, tested) stops it for that dictation. Not yet: listening on its own after a say or ask, per-session toggle, tab and project marks, turning itself off.

Hands-free now answers questions aloud: after the question is read out, the microphone opens for the answer (only while Paddock is in front and no other dictation is open) and it is sent 5 s after the operator stops talking. Still not: listening after a say, per-session toggle, marks, turning itself off.

Hands-free now also listens after a say has been read out (reply into its tab), so the popup follows a back and forth.

2026-10-31 Limits written (App/Voice.swift, HandsFreeLimits in PaddockCore, HandsFreeLimitsTests, Voice doc). The criteria were rewritten to the design that shipped: one app-wide switch, not a per-session toggle with tab and project marks; the sandbox cannot turn it on (test). A relaunch now starts with hands-free off. The old 'when the session ends' rule is dropped: hands-free is app-wide, so there is no session to end, and the idle limit covers a forgotten agent. Not built on the Mac yet (AC 2 to 6).

Merged 2026-11-06 (criteria kept, marked with their old ticket): PAD-50 Hands-free start word: nothing is dictated until the operator says Paddock; PAD-51 Listen turned off stays off in hands-free; PAD-52 Chimes when the microphone hears a start word or a spoken stop; PAD-53 Waiting music while a hands-free agent works; PAD-54 Do not send punctuation or filler noise to the agent
<!-- SECTION:NOTES:END -->
