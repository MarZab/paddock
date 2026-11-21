---
id: PAD-138
title: 'PseudoTerminal builds without the String(cString:) deprecation warning'
status: In Progress
assignee: []
created_date: '2026-11-09 08:11'
updated_date: '2026-11-09 08:15'
labels:
  - shell
dependencies: []
priority: low
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Mac build warns that `String(cString:)` taking an array is deprecated, in `PosixPseudoTerminal.spawn`. The array is already NUL-terminated and `open` takes it directly, as `paddock_pty_spawn` does a few lines later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Mac build no longer shows the deprecation warning in PseudoTerminal.swift
- [x] #2 PaddockShell tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Committed. PaddockShell tests pass on Linux. AC1 needs a Mac build.
<!-- SECTION:NOTES:END -->
