---
id: PAD-65
title: >-
  Terminal copy survives the program's output; right-click menu with Copy,
  Paste, Select All
status: Done
assignee:
  - '@claude'
created_date: '2026-11-01 13:04'
updated_date: '2026-11-01 13:11'
labels:
  - terminal
dependencies: []
priority: high
type: bug
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Copy from a terminal tab stopped working while an agent runs. Cause: SwiftTerm 1.20 drops the selection on every chunk of output and every resize while allowMouseReporting is on (TerminalView.feedPrepare and linefeed set selection.active = false). An agent that keeps redrawing (a spinner, a status line) wipes the selection before Cmd-C, so Copy has nothing to copy. Also, while the program turns on mouse tracking, a plain drag goes to the program; Shift-drag selects (SwiftTerm's shiftBypassesMouseReporting).

Fix in PaddockShellUI: a TerminalView subclass keeps the text of the last selection made in it. Copy uses the live selection, or that kept text when output cleared it. A new click in the terminal drops the kept text. Add a right-click menu on the terminal: Copy, Paste, Select All.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cmd-C after selecting text in an agent tab that keeps printing copies the selected text
- [x] #2 Edit > Copy stays enabled after output cleared the highlight, until the next click in the terminal
- [x] #3 Right-click in a terminal shows Copy, Paste, Select All; Copy is disabled with nothing selected
- [x] #4 Right-click opens the menu even while the program has mouse tracking on
- [x] #5 doc-12 PaddockShell (or doc-15 UI) describes copy and the menu
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PaddockTerminalView: TerminalView subclass in SandboxTerminalView.swift; selectionChanged keeps the selected text, mouseDown drops it, copy/validateUserInterfaceItem fall back to it.
2. menu(for:) returns Copy, Paste, Select All targeting the view.
3. PaddedTerminalView uses the subclass.
4. Doc PaddockShell: copy and the menu. Build on the Mac (PaddockShellUI is macOS only).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented PaddockTerminalView (SandboxTerminalView.swift) and documented it in doc-12. Not built yet: PaddockShellUI is macOS only and this session runs on Linux. Needs mise run build and a manual check on the Mac.

Built and checked by the operator on the Mac (2026-11-01): copy from a busy agent tab and the right-click menu work. swiftlint: no new warnings in SandboxTerminalView.swift.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Copy from a terminal stopped working because SwiftTerm 1.20 drops the selection on every chunk of output while mouse reporting is on, so a redrawing agent cleared it before Cmd-C. PaddockTerminalView (SwiftTerm subclass in PaddockShellUI) keeps the last selection's text; Copy uses the live selection or that text until the next click, and Edit > Copy validates against it. Right-click shows Copy, Paste, Select All, also while the program tracks the mouse. Shift-drag selects while it does. doc-12 updated. Verified by the operator on the Mac.
<!-- SECTION:FINAL_SUMMARY:END -->
