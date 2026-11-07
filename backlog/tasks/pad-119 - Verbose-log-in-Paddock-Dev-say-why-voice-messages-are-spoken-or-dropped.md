---
id: PAD-119
title: 'Verbose log: say why voice messages are spoken or dropped'
status: Done
assignee: []
created_date: '2026-11-07 09:04'
updated_date: '2026-11-07 14:21'
labels:
  - voice
  - tooling
dependencies: []
documentation:
  - doc-18
type: feature
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agent report 2026-11-07 (sandbox ectopress): of four paddock-voice say calls that all succeeded in the sandbox, only the fourth was heard. Paddock drops a say silently when it does not parse, is older than 60 s by the sandbox's clock (VoiceMessage.isStale, checked before it is recorded, so it is not in the popup either), its tab's popup is closed, voice reply is off or muted, or the speech queue drops or cuts it. A Debug-build-only verbose log (Verbose Log in the File menu, the verboseLog default) logs each decision so the next report can name the cause. Suspect: the sandbox's clock behind the Mac's. (backlog doc Voice)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With it on, every voice message from a watcher logs what Paddock did with it: not a message, stale (with its age by the sandbox's clock), recorded and not read aloud (popup closed, no tab, voice reply off, muted), or handed to speech and how it ended (done, interrupted, dropped, cut off)
- [x] #2 Docs and CHANGELOG updated
- [x] #3 File > Verbose Log in every build (Paddock and Paddock Dev), stored in the verboseLog default and off by default
- [x] #4 A top-level System menu holds Log, Processes, Verbose Log, Log Files, Crash Reports, and Edit Paddock's Config; the File menu no longer does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppModel.verboseLog + debugLog, Debug builds only; File > Verbose Log toggle.
2. Voice.receive and speakWithoutListening log each decision (ids and lengths, never the text).
3. Docs UI + Voice, CHANGELOG. Build and try in Paddock Dev.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Verbose Log (System menu, every build) logs what became of each voice message; the System menu holds Log, Processes, Verbose Log, Log Files, Crash Reports, Capture Diagnostics, and Edit Paddock's Config. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
