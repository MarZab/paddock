---
id: PAD-37
title: Push-to-talk in agent tabs and the voice ask banner
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 08:07'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - app
milestone: m-5
dependencies:
  - PAD-35
  - PAD-36
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: medium
type: feature
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator wants to talk to an agent instead of typing, and to answer an agent's `paddock voice ask` by voice. Dictated text goes into the agent's terminal like a paste, so it must not inject control sequences, and by default the operator reviews it before it is submitted. The agent can never turn the microphone on: an ask only shows a banner and waits for the operator. Banner placement follows the approval request banner (backlog doc UI, Live activity). Design: backlog doc Voice (planned).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking the mic button or pressing Option-Space (in-app only, no Accessibility permission) in an agent tab with the voice kit opens a dictation panel that stays open; live text shows in it; clicking again pauses (text editable) or listens again; the mic state is always visible while it records
- [ ] #2 The app writes a dictation record for the session before pasting, so the kit's prompt hook can tell the agent the prompt was spoken
- [ ] #3 An ask from a project in the background posts a macOS notification like approval requests do
- [ ] #4 UI doc and Voice doc updated
- [ ] #5 Send writes the text to the session's PTY as a bracketed paste with control characters removed and submits it; the text can be edited first (clicking into it pauses the microphone); Cancel sends nothing
- [ ] #6 An ask shows as a banner under that session's terminal with the question and its choices as buttons; the operator answers by voice (with Cancel and Send), clicking a choice, typing in the banner, or Dismiss; spoken answers to choices match by name or position (the second one, yes, no)
- [ ] #7 (was PAD-55) Return in the dictation field sends it like Send (noise is still not sent) and hands the focus back, so hands-free listens again
- [ ] #8 (was PAD-55) Checked on the Mac: builds, Return sends, Option-Return adds a line
- [x] #9 (was PAD-55) Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Written, not built (App/Voice.swift VoiceControls, MicrophoneButton, VoiceAskBanner, VoiceModel; TerminalViews wiring): hold the mic or Option-Space in an agent tab, live text, dictation record then bracketed paste; the ask banner with choices, a field, a mic, Dismiss. Not done: the macOS notification for a background ask (AC5), a menu for mute and send on release (app defaults voiceMuted, voiceSendOnRelease for now).

Dictation is now click to open, not hold: the panel stays open with live text, is editable while paused, and closes with Cancel or Apply; Send (voiceSendOnApply) replaces send on release. Built on the Mac before this change; this change is not built yet.

Apply is now Send (always submits); the text field is editable at any time, and clicking into it pauses the microphone. Hands-free toggle in the panel: PAD-38.

All voice UI is one popup over the terminal (VoiceControls): the question banner is gone; a question opens the popup by itself with its choices, a typed answer, Dismiss, and Send. Cancel became the Listen pill (with Voice reply and Hands-free pills) and a small close button.

Merged 2026-11-06 (criteria kept, marked with their old ticket): PAD-55 Return in the voice popup's text field sends
<!-- SECTION:NOTES:END -->
