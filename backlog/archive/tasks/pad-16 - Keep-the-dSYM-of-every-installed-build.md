---
id: PAD-16
title: Keep the dSYM of every installed build
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - tooling
  - crash
milestone: m-3
dependencies: []
priority: medium
type: chore
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS writes crash reports to ~/Library/Logs/DiagnosticReports (the status popover's Crash Reports opens it). File and line numbers need the dSYM of the same build, and every build overwrites build/DerivedData/.../Paddock.app.dSYM. mise run install should copy it to build/dSYMs/<build number>/ (the build number is the commit count, which the .ips records).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mise run install keeps the dSYM under build/dSYMs/<CFBundleVersion>/
- [ ] #2 An older install's crash report can still be matched to its dSYM
<!-- AC:END -->
