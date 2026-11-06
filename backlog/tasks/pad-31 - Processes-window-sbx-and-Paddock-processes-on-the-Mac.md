---
id: PAD-31
title: 'Processes window: sbx and Paddock processes on the Mac'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-28 20:59'
updated_date: '2026-11-06 10:40'
labels:
  - app
  - core
dependencies: []
priority: medium
type: feature
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Leftover sbx tools cost a lot without anyone noticing: on 2026-10-28 four bare `sbx` dashboards had run for 4 days with their terminals gone, using up to 1.3 cores and 500 MB and running a stats script in every sandbox every second. Each sandbox VM (`containerd-shim-nerdbox-v1`) also costs the Mac memory and CPU that Linux inside it does not show (3.6 GB and 85% for one). Paddock should show the sbx-related processes on the Mac, grouped by what they are, and offer to stop the ones whose terminal is gone. It is not a general process manager: anything not attributable to sbx or Paddock stays Activity Monitor's.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Lists sbx-related processes of the current user on the Mac in groups: left behind by Paddock, orphaned sbx tools (parent gone, not the daemon), sbx tools in use, and sbx itself (daemon, llmman, each sandbox VM) with CPU, memory, and age
- [ ] #2 Each sandbox VM row names its sandbox (mapping captured from real sbx output first)
- [ ] #3 Orphaned sbx tools can be stopped from the window after a confirmation that lists them; nothing is stopped automatically except Paddock's own watchers
- [ ] #4 The status bar shows when orphaned sbx tools exist
- [x] #5 Never stops the sbx daemon, llmman, a VM, or a process outside sbx and Paddock
- [x] #6 Parsers have fixture tests from real captures; doc UI describes the window
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SbxProcesses.classify on HostProcesses (current user only): watcher, leftover watcher, orphaned tool, tool in use, daemon, llmman, sandbox VM (container ID), helper.
2. SbxProcesses.stop: re-reads ps and signals only processes still the same and stoppable (orphaned tool, leftover watcher).
3. App: File > sbx Processes window (groups, Stop N Without a Terminal with a confirmation listing them), status popover button, orange mark on the status button; read with the loads every 10 s.
4. VM rows name their sandbox once a capture shows the mapping (lsof of the shims pending).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
sbx ls has sandbox UUIDs, the shims a 64-hex container ID: no link in either output (captured 2026-10-28). The container ID stays the same across a VM restart (be318788... kept it while its pid changed). Asked the operator for lsof of the shims. Until then VM rows show the ID's first 12 characters.

Operator: the window needed a better UI. Now a sortable Table (kind, process, PID, CPU, memory, running, command) with multiple selection; Stop from a header button for every process without a terminal or the context menu for the selected ones, always confirmed. ps is read every 30 s (for the status button mark) and when the window opens.

Operator checked on the Mac 2026-11-06: the Processes window works. Stopping orphans (AC3), VM names (AC2) and the status bar hint (AC4) not reported.
<!-- SECTION:NOTES:END -->
