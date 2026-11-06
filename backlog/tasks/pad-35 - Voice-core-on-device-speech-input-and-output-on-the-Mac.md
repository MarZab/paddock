---
id: PAD-35
title: 'Voice core: on-device speech input and output on the Mac'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 08:07'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - core
milestone: m-5
dependencies:
  - PAD-34
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: medium
type: feature
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock needs speech in both directions without installing anything and without audio ever reaching a sandbox: the Mac transcribes and speaks, only text crosses. The operator runs macOS 26 only, so older macOS versions are not a concern and the deployment target can move to 26. Text that will be spoken can come from a sandbox (an agent's `paddock voice say`), so it is untrusted like tab titles. Several projects can talk at once, so speech must be serialized and always say who is speaking. Design: backlog doc Voice (planned).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Deployment target is macOS 26; the app has NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription, and the com.apple.security.device.audio-input entitlement, with Hardened Runtime on and App Sandbox off
- [ ] #2 Speech input uses SpeechAnalyzer on-device only (never a server), streams partial and final text, takes contextual strings, and reports end of utterance from its speech detector; language assets are downloaded only after the operator confirms
- [ ] #3 Speech output uses AVSpeechSynthesizer through one app-wide queue: utterances never overlap, each starts with the project name (and the session name when a project has more than one agent), and speaking stops at once when the operator starts talking or typing in that tab, reporting interrupted
- [x] #4 Text to speak is cleaned before speaking: control, bidi, and zero-width characters dropped, markdown and code blocks removed, cut to a fixed length, and plain text only (no SSML); tests cover each
- [x] #5 Keyword lists are checked: a cap on count and length, letters, digits, and a few punctuation characters only; tests cover rejection
- [x] #6 Logic lives in PaddockCore behind protocols so tests run with fakes; the Voice doc and Security rules doc are updated
- [x] #7 (was PAD-45) SpeechVoices picks the operator's choice while installed, else the best voice for the language; novelty voices never; tested
- [ ] #8 (was PAD-45) The microphone's right-click menu has Voice: Automatic (names the voice) and every offered voice with its quality, and Get Better Voices
- [ ] #9 (was PAD-45) The popup shows a hideable hint with Get Voices when only basic voices are installed and voice reply is on
- [ ] #10 (was PAD-45) A voice downloaded while Paddock runs is picked up without a restart
- [x] #11 (was PAD-45) Voice doc updated
- [x] #12 (was PAD-46) Speech plays through Paddock's own AVAudioEngine with voice processing on the input
- [ ] #13 (was PAD-46) Saying stop or cancel over an agent being read aloud through the speakers cuts it off (checked on the Mac)
- [ ] #14 (was PAD-46) Dictation and hands-free still work with the shared engine; no echo of the agent's words in the transcription
- [x] #15 (was PAD-46) Voice doc updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PaddockCore (Linux-tested): SpokenText (clean text for speech), VoiceKeywords (checks, project names), SpeechQueue actor over a SpeechSynthesizing protocol (one queue, speaker prefix, interrupt), VoiceChoice matching, BracketedPaste.
2. App (macOS 26, not buildable here): deployment target 26, Info.plist usage strings, audio-input entitlement, SpeechAnalyzer input and AVSpeechSynthesizer output behind the core protocols; checked on the Mac with PAD-34.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PaddockCore: SpokenText, VoiceKeywords, VoiceChoice, BracketedPaste, SpeechQueue (fake synthesizer tests: one at a time, interrupt by tab, per-project cap), VoiceAnnouncements; 449 tests pass on Linux.
App: project.yml (macOS 26, usage strings, App/Paddock.entitlements with audio-input), App/Info.plist, App/Voice.swift (SystemSpeech over AVSpeechSynthesizer, SpeechListener over SpeechAnalyzer/SpeechTranscriber with AVAudioEngine and AVAudioConverter). Not built: no macOS SDK here, and the SpeechAnalyzer calls are written from Apple's WWDC25 API, so expect compile fixes on the Mac. AC1 to AC3 stay open until it builds and runs there.

Merged 2026-11-06 (criteria kept, marked with their old ticket): PAD-45 Voice picker and a hint for better voices; PAD-46 Echo cancellation so the operator can talk over an agent being read aloud
<!-- SECTION:NOTES:END -->
