---
id: PAD-154
title: 'System > Processes: the project of each sbx command'
status: Done
assignee: []
created_date: '2026-11-25 09:30'
updated_date: '2026-11-25 09:31'
labels: []
dependencies: []
type: feature
ordinal: 170000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
System > Processes lists sbx's processes on the Mac by kind, and the operator cannot tell which project a leftover sbx run or sbx exec (or a watcher) belongs to. The sandbox is in the command line, and Paddock's sandboxes are named after their projects. Sandbox machines stay without one: sbx does not link a machine's container id to its sandbox (PAD-31).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each sbx run, sbx exec, and watcher row shows its sandbox in a Project column, sortable; a sandbox that is not a Paddock project says so
- [x] #2 The sandbox is read from the command line by a tested parser that skips sbx's global options and the exec and run options that take a value
- [x] #3 Doc UI
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
System > Processes has a sortable Project column: SbxProcess.sandbox reads the sandbox of sbx exec, sbx run --name, and watcher rows from the command line (SbxProcesses.sandbox: skips global options, exec's value options as sbx's help lists them, short flags together like -iu; nil for --cloud, a run without --name, or a word that is not a sandbox name), tested on the real ps capture and edge cases. A sandbox that is not a Paddock project is dimmed and says so; machines and the daemon show none (sbx does not link a machine to its sandbox, PAD-31). Doc UI and CHANGELOG. Not compiled on the Mac yet.
<!-- SECTION:FINAL_SUMMARY:END -->
