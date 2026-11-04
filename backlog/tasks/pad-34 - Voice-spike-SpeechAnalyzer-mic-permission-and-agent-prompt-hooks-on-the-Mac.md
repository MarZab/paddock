---
id: PAD-34
title: 'Voice spike: SpeechAnalyzer, mic permission, and agent prompt hooks on the Mac'
status: To Do
assignee: []
created_date: '2026-10-29 08:07'
updated_date: '2026-10-29 08:29'
labels:
  - voice
  - agents
milestone: m-5
dependencies: []
references:
  - 'https://developer.apple.com/documentation/speech/speechanalyzer'
  - 'https://code.claude.com/docs/en/hooks'
  - 'https://opencode.ai/docs/plugins/'
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: medium
type: spike
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Voice (backlog doc Voice (planned)) depends on things nobody has checked on this Mac: macOS 26 SpeechAnalyzer as described (contextual strings for code words, its speech detector for end of utterance, language assets through AssetInventory), the microphone under Hardened Runtime with ad hoc signing (a cdhash-based designated requirement may make macOS ask for the microphone again after every `mise run install`), and what agent hooks receive when a prompt is submitted. The agent-side design (a hook that tells the agent a prompt was spoken) needs real hook input as fixtures, not guesses. Also worth knowing first: whether macOS system Dictation already types into SwiftTerm's TerminalView (it implements NSTextInputClient), as a zero-work baseline.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A throwaway build or script transcribes the operator's speech with SpeechAnalyzer on-device; findings on contextual strings (do code identifiers like PolicyPlanner come out right with and without them), the speech detector (end of utterance timing), and the AssetInventory download (size, needs a prompt or not) are written in the Voice doc
- [ ] #2 Microphone access works with the audio-input entitlement and Hardened Runtime; whether permission survives a reinstall of an ad hoc signed build is recorded, with a workaround if it does not
- [ ] #3 Claude Code UserPromptSubmit hook stdin and the effect of hookSpecificOutput.additionalContext are captured from the Claude Code version sbx ships, as sanitized fixtures in Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/
- [ ] #4 Whether an OpenCode 2.1.4 plugin can add context to a user message (chat.message or another hook) is checked and recorded; if it cannot, the fallback is named in the Voice doc
- [ ] #5 Whether system Dictation inserts text into an agent tab is recorded
<!-- AC:END -->
