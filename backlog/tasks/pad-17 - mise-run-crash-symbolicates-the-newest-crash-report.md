---
id: PAD-17
title: Keep each build's dSYM and symbolicate the newest crash report
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-10-25 17:23'
labels:
  - tooling
  - crash
milestone: m-3
dependencies: []
priority: medium
type: chore
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Merged from PAD-16. macOS writes crash reports to ~/Library/Logs/DiagnosticReports (the status popover's Crash Reports opens it). File and line numbers need the dSYM of the same build, and every build overwrites build/DerivedData/.../Paddock.app.dSYM. mise run install should copy it to build/dSYMs/<build number>/ (the build number is the commit count, which the .ips records). A mise task then finds the newest Paddock .ips, picks the dSYM for its build number, and prints the exception, the asi message, and the crashing thread with file and line (atos).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mise run crash prints the newest report's exception, message, and symbolicated crashing thread
- [ ] #2 It says clearly when no report or no matching dSYM exists
- [ ] #3 mise run install keeps the dSYM under build/dSYMs/<CFBundleVersion>/
- [ ] #4 An older install's crash report can still be matched to its dSYM
<!-- AC:END -->
