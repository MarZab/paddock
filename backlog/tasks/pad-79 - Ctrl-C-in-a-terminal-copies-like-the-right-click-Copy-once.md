---
id: PAD-79
title: 'Ctrl-C in a terminal copies like the right-click Copy, once'
status: Done
assignee: []
created_date: '2026-11-04 14:19'
updated_date: '2026-11-06 10:57'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator asked (2026-11-04) for Ctrl-C to copy the way the terminal's right-click Copy does: the terminal's own selection (live, or kept after output cleared it), else what the program last copied (OSC 52, such as Claude Code's own selection; PAD-65, PAD-66). Ctrl-C is also how the operator stops an agent, so it must still reach the program when there is nothing new to copy, as in Windows Terminal and VS Code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Plain Ctrl-C (no Command, Option, or Shift) in a focused terminal with a selection or a program copy puts that text on the clipboard and is not sent to the program
- [x] #2 After that copy the text is spent (selection cleared, kept and program copy dropped), so the next Ctrl-C reaches the program as an interrupt
- [x] #3 With nothing to copy, Ctrl-C reaches the program as before; Cmd-C keeps copying only the terminal's own selection
- [x] #4 The decision lives in PaddockShellCore with tests; backlog doc PaddockShell (or UI) describes it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PaddockShellCore TerminalCopy (text, isControlC, controlC) with tests. PaddockTerminalView installs a local keyDown monitor in viewDidMoveToWindow (removed when the view leaves the window) that acts only when this terminal is the window's first responder. On .copy it puts the text, calls selection.selectNone(), drops the kept and program copies, and swallows the key. The menu's Copy uses TerminalCopy.text. Not compiled here (AppKit); ACs 1-3 need a check on the Mac.

Operator confirmed on the Mac 2026-11-06: Ctrl-C with a selection copies and is not sent; the next Ctrl-C interrupts; with nothing to copy it interrupts as before.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Plain Ctrl-C with a selection or a program copy copies it and is not sent; the copy is spent, so the next Ctrl-C interrupts; with nothing to copy it interrupts as before; Cmd-C still copies only the terminal's own selection. Confirmed on the Mac by the operator 2026-11-06.
<!-- SECTION:FINAL_SUMMARY:END -->
