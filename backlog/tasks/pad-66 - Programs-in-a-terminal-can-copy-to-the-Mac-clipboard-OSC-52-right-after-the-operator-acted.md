---
id: PAD-66
title: >-
  Programs' copies (OSC 52) reach the clipboard only through the terminal's
  right-click Copy
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-01 13:13'
updated_date: '2026-11-01 13:20'
labels:
  - terminal
  - security
dependencies: []
priority: high
type: bug
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Claude Code, while it tracks the mouse, selects text in its own view and copies it with OSC 52 (ESC ] 52 ; c ; base64 ST); it then says it copied. SwiftTerm's TerminalViewDelegate.clipboardCopy does nothing by default, so nothing reached the clipboard, and SwiftTerm's own Copy stayed disabled because the drag went to the program.

The program runs in the sandbox, so it never reaches the Mac clipboard on its own (operator's decision): the terminal keeps the last OSC 52 text (UTF-8, not blank, up to 1 MB, never from a scrollback replay). The right-click menu's one Copy copies the terminal's own selection, else that text (the newer of a kept selection and the program's copy wins). Cmd-C copies only the terminal's own selection. OSC 52 reads stay refused; pasting is only the operator's Paste. Logic in PaddockShellCore (ClipboardWrite) with tests; wiring in PaddockShellUI (PaddockTerminalView.programCopy, copyFromMenu, Coordinator.clipboardCopy).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An OSC 52 write never changes the clipboard by itself; Cmd-C copies only the terminal's own selection
- [ ] #2 OSC 52 reads stay refused
- [ ] #3 doc-12 PaddockShell describes the rule
- [ ] #4 After selecting text in Claude Code (it reports copied), the right-click menu's Copy is enabled and puts that text on the Mac clipboard
- [ ] #5 Non-UTF-8, blank, or over 1 MB writes are refused (tests)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ClipboardWrite (text, preview) in PaddockShellCore with tests.
2. Coordinator.clipboardCopy keeps the text on PaddockTerminalView.programCopy, not while replaying.
3. Right-click menu item copies it.
4. doc-12. Build and check on the Mac.
<!-- SECTION:PLAN:END -->
