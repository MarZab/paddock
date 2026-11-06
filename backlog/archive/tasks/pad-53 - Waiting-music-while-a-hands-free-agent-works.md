---
id: PAD-53
title: Waiting music while a hands-free agent works
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 19:24'
updated_date: '2026-11-06 10:27'
labels:
  - voice
dependencies: []
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In hands-free the operator is away from the screen and hears nothing while the agent works for minutes after a spoken prompt, so they cannot tell it is busy rather than stuck or deaf. Quiet generated music (no recording to license) fills the wait. Chosen over a heartbeat tick or spoken progress. Design: backlog doc Voice, Waiting music.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Music plays only while hands-free waits for a start word after the operator spoke, the tab's agent reports working (status kit), and at least 3 s have passed; it fades out when the start word is heard, the agent stops working, or the microphone goes off
- [ ] #2 It plays through the shared engine only with echo cancellation, so the recognizer does not hear it and it never turns the microphone on by itself
- [x] #3 Generated in PaddockCore (WaitingMusic): fades in, stays under a fixed ceiling, and after a minute thins to a soft note every 8 s; the renderer fades out without locks on the audio thread (tests)
- [ ] #4 Waiting Music toggle in the microphone's menu (voiceWaitingMusic, on by default); nothing while muted
- [ ] #5 Checked on the Mac: builds, music plays during a hands-free wait, the start word is still recognized over it, and it does not end up in the dictation
- [x] #6 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Synth and renderer tested on Linux (WaitingMusicTests). App side (WaitingMusicPlayer, VoiceModel.followMusic, menu toggle) not built here. A 90 s preview rendered from a Python port of the synth is in scratch/waiting-music.wav (gitignored), 2.5x louder than in the app.

Merged into PAD-38.
<!-- SECTION:NOTES:END -->
