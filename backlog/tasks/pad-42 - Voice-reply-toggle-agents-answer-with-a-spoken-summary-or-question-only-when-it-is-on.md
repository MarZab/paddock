---
id: PAD-42
title: >-
  Voice reply toggle: agents answer with a spoken summary or question only when
  it is on
status: In Progress
assignee: []
created_date: '2026-10-29 10:12'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - app
dependencies:
  - PAD-36
priority: medium
type: feature
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator turns voice reply on or off in Paddock (dictation panel checkbox, and the microphone's context menu). On: the voice kit's UserPromptSubmit hook tells the agent with each prompt (typed too) to end with a spoken summary (paddock-voice say) or ask a decision with paddock-voice ask. Off: a spoken prompt gets 'reply in the terminal as usual, without say or ask'; a typed one gets nothing. Muted counts as off. VoiceSettings carries voiceReply to the kit's --set-status; settings without it (older Paddock) mean off. backlog doc Voice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 VoiceSettings has voiceReply; --set-status stores it, missing means off, a non-boolean is refused
- [x] #2 The hook adds the voice reply instruction to every prompt while it is on and voice is not muted, and 'as usual' for a spoken prompt while it is off
- [ ] #3 The app has the toggle in the dictation panel and the mic's context menu, remembered, and re-sends settings to agent tabs when it changes
- [x] #4 Voice doc and UI doc updated
- [x] #5 The agent's interface is only what it acts on: say, ask, words; no status command and no say --wait; the instructions and hook notes are short and written from the agent's side
- [ ] #6 Agents may always say and ask: it shows in the voice popup's conversation; voice reply decides only whether it is read aloud
- [ ] #7 (was PAD-101) An agent's say or question is read aloud only while its tab's voice popup is open (and voice reply on, not muted); hands-free does not listen after one that was not read
- [ ] #8 (was PAD-101) A say no longer opens the popup; it goes to the conversation, seen when the operator opens it. A question still opens the popup, silently
- [ ] #9 (was PAD-101) Closing the popup cuts off what its agent is saying and drops what waits
- [ ] #10 (was PAD-101) An agent outside a Paddock tab is never read aloud
- [x] #11 (was PAD-101) doc Voice describes it
- [ ] #12 (was PAD-101) The agent is told voice reply is off (--set-status) while its tab's popup is closed, and told again when the popup opens or closes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Kit and hook tested on Linux (VoiceKitTests, Node). App toggle written, not built yet.

Simplified the agent interface: say/ask gated on voice reply in the kit and in the app; status command, the spoken/typed record, and say --wait removed; instructions rewritten from the agent's point of view.

Reversed the gate: say/ask always work and always show in the popup's conversation (VoiceConversation, PaddockCore, tested); voice reply only decides reading aloud.

Merged 2026-11-06 (criteria kept, marked with their old ticket): PAD-101 A closed voice popup keeps its agent silent
<!-- SECTION:NOTES:END -->
