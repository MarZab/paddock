---
id: PAD-18
title: Notice a crash on the next launch
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-10-25 17:23'
labels:
  - app
  - crash
milestone: m-3
dependencies: []
priority: low
type: feature
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Error Log now also goes to ~/Library/Logs/Paddock/paddock.log (App/LogFile.swift, capped, no secrets; uncommitted with PAD-22's work, lands with it). What is left: on launch, when a Paddock crash report in DiagnosticReports is newer than the last run, say so in the status popover with Reveal in Finder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After a crash, the next launch shows a notice in the status popover that opens the report
- [ ] #2 The notice does not show again once the operator has seen it
<!-- AC:END -->
