---
id: PAD-38
title: Hands-free voice mode per agent session
status: In Progress
assignee: []
created_date: '2026-10-29 08:07'
updated_date: '2026-10-31 19:41'
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
<!-- SECTION:NOTES:END -->
