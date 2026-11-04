---
id: PAD-46
title: Echo cancellation so the operator can talk over an agent being read aloud
status: In Progress
assignee: []
created_date: '2026-10-29 11:19'
updated_date: '2026-10-29 11:38'
labels:
  - voice
  - app
dependencies:
  - PAD-38
priority: medium
type: feature
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
While an agent is read aloud, the microphone hears mostly the Mac's own speaker: the operator's "stop" never shows in the transcription (seen on the Mac with the popup's Hearing line, 3d54ec1). AVSpeechSynthesizer plays on its own, so nothing subtracts it from the microphone. Fix: render speech with AVSpeechSynthesizer.write(_:toBufferCallback:) and play the buffers through an AVAudioPlayerNode on the same AVAudioEngine whose input node has voice processing on (setVoiceProcessingEnabled(true)), so Apple's echo cancellation removes the speech from the microphone. SpeechListener and SystemSpeech then share one engine. Headphones avoid the problem meanwhile. backlog doc Voice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Speech plays through Paddock's own AVAudioEngine with voice processing on the input
- [ ] #2 Saying stop or cancel over an agent being read aloud through the speakers cuts it off (checked on the Mac)
- [ ] #3 Dictation and hands-free still work with the shared engine; no echo of the agent's words in the transcription
- [x] #4 Voice doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
VoiceAudio: one AVAudioEngine, input voice processing on (ducking off), AVAudioPlayerNode to the main mixer at 24 kHz mono. SystemSpeech renders with write(_:toBufferCallback:) through SpeechFeed (converts, schedules, done after the last buffer plays) while the microphone watches for stop; otherwise plays as before. SpeechListener taps the shared engine. Written, not built: AC2 and AC3 need the Mac.

First run on the Mac: Listen failed, -10875 'client-side input and output formats do not match' (AUVPAggregate). Fix: mixer to output connected with the input node's output format; fallback without voice processing (logged) if the engine still will not start.

Second run: Listen stays on, no text, no errors. Likely the voice-processed microphone has several channels and the converter to the analyzer's mono format was nil, so buffers went to the analyzer unconverted and were dropped. Now the first channel is taken first, a missing converter is an error (noConversion), and each start logs the microphone format and whether echo cancellation is on.
<!-- SECTION:NOTES:END -->
