---
id: PAD-36
title: 'Voice kit: paddock voice say, ask, words, status for agents'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 08:07'
updated_date: '2026-11-06 10:27'
labels:
  - voice
  - agents
  - kits
milestone: m-5
dependencies:
  - PAD-34
documentation:
  - backlog/docs/doc-18 - Voice.md
priority: medium
type: feature
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The agent should be a full participant in voice: answer by voice, ask the operator something and get the spoken answer back, and feed recognition the words it is working with (function names, tools, file names) so dictation of code terms comes out right. It should also know when a prompt was spoken, since spoken prompts can contain transcription errors and want a short spoken reply. All of this is one opt-in builtin kit, `voice` (needs `status`, whose `paddock-agent-watch` watcher already carries lines from the sandbox to the app, so no new watcher). Everything the kit sends is display or speech data from an untrusted sandbox: Paddock validates it and never uses it for any decision. Design: backlog doc Voice (planned); kit pattern: backlog doc Kits, backlog doc Browser (paddock open, annotate).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `paddock voice say TEXT [--wait]` queues speech; with --wait it prints done or interrupted
- [ ] #2 `paddock voice ask QUESTION [--choice X]... [--timeout S]` shows the question to the operator, waits, and prints the answer text, the matched choice, timeout, or dismissed; the answer is written back into the sandbox with sbx exec and never in argv
- [x] #3 `paddock voice words add|remove|list|clear` manages per-project keywords that the app adds to the project's file and folder names as recognition context
- [x] #4 `paddock voice status` prints whether voice is on, whether hands-free is on, and whether the last prompt was spoken; `paddock voice` alone prints a quick start
- [ ] #5 Claude Code gets a UserPromptSubmit hook (merged into ~/.claude/settings.json, existing hooks kept) that adds context when the prompt matches the app's last dictation record for that session; OpenCode gets the equivalent through its plugin or the fallback the spike named
- [x] #6 Agent instructions say when to speak (finished, needs the operator), to keep it to one or two sentences without code or full paths, to use ask for decisions when the operator is in voice mode, and to add keywords for names it works with
- [x] #7 The kit's lines are parsed by a typed parser with fixture-based tests that reject unknown kinds, oversized fields, and too many choices or keywords; generated kit files are tested like AgentStatusKitTests
- [x] #8 Kits doc and Voice doc updated
- [ ] #9 (was PAD-99) Voice notices a sandbox without paddock-voice and shows one hint naming the fix (Sync / recreate with the voice kit), not one error per dictation
- [ ] #10 (was PAD-99) sbx WARN lines about the sentinel connection are not logged as voice errors
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. VoiceKit (builtin `voice`, needs status): node command `paddock-voice` (say, ask, words, status; app-only --answer, --dictated, --set-status, --hook claude), a sh watcher `paddock-voice-watch` followed like the other watchers, Claude Code UserPromptSubmit hook merged with the status kit's merge script, agent instructions.
2. Named `paddock-voice`, not `paddock voice`: `paddock` belongs to the browser kit, and the voice kit must not depend on it.
3. Messages are files in /tmp/paddock-voice/out the watcher prints once and removes; answers and the dictation record go in with sbx exec -i and stdin, never argv.
4. VoiceMessage parser with strict limits and fixture tests; scripts run for real in tests (node here).
5. OpenCode prompt context waits for PAD-34 (no guessing the plugin hook); OpenCode agents still get say/ask/words/status.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Written and tested on Linux (VoiceKitTests run paddock-voice and paddock-voice-watch for real with Node; VoiceTests parse Fixtures/voice/watch.jsonl, the kit's own output).
Deviations from the ticket text: the command is `paddock-voice` (not `paddock voice`: `paddock` is the browser kit's), and the kit has its own watcher, paddock-voice-watch, instead of riding paddock-agent-watch (changing the status kit would mark every status sandbox for recreate). Words are state (printed at each watcher start), say/ask/cancel are events (printed once).
Open: AC2 needs the app side (App/Voice.swift, not built here) checked on the Mac; AC5 has Claude Code done against the documented hook shape (fixture capture PAD-34) and OpenCode waiting for PAD-34.

Merged 2026-11-06 (criteria kept, marked with their old ticket): PAD-99 Voice in a sandbox without the voice kit says so once instead of failing every dictation
<!-- SECTION:NOTES:END -->
