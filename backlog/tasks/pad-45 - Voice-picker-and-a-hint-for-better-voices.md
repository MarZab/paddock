---
id: PAD-45
title: Voice picker and a hint for better voices
status: In Progress
assignee: []
created_date: '2026-10-29 10:49'
updated_date: '2026-10-29 10:54'
labels:
  - voice
  - app
dependencies: []
priority: medium
type: feature
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock spoke with the default system voice. Use what macOS has: pick the best installed voice for the Mac's language automatically (premium, enhanced, basic; own region first; no novelty voices), let the operator choose any installed voice in the microphone's right-click menu (Voice: Automatic or a voice), follow voices installed while Paddock runs, and when only basic voices exist show a hint in the popup with Get Voices (System Settings, Accessibility, Spoken Content, Manage Voices) that can be hidden. No downloads by Paddock. backlog doc Voice, Speaking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SpeechVoices picks the operator's choice while installed, else the best voice for the language; novelty voices never; tested
- [ ] #2 The microphone's right-click menu has Voice: Automatic (names the voice) and every offered voice with its quality, and Get Better Voices
- [ ] #3 The popup shows a hideable hint with Get Voices when only basic voices are installed and voice reply is on
- [ ] #4 A voice downloaded while Paddock runs is picked up without a restart
- [x] #5 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Not built yet. The System Settings URL (x-apple.systempreferences:com.apple.Accessibility-Settings.extension) opens Accessibility; whether a deeper anchor reaches Spoken Content directly is unverified.

Operator reported a hang after this landed (no capture of Paddock Dev: mise run hang took the installed app). Hardened: voices are read off the main thread, one read at a time, and a change notice within 5 s of a read is ignored (reading may itself post it, which looped on the main thread); language and the offered list are worked out once per change instead of per view update. Cause not confirmed.
<!-- SECTION:NOTES:END -->
