---
id: PAD-32
title: 'Sandbox resources: load, memory, disk, and the busiest processes'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-28 20:59'
updated_date: '2026-10-28 22:23'
labels:
  - app
  - core
dependencies:
  - PAD-30
priority: medium
type: feature
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sandboxes take a lot of the Mac and the operator cannot see what runs inside them. `sbx tui` reads CPU, memory, disk, and uptime by running a short /proc script in each sandbox (POST /sandbox/{name}/exec, about once a second); there is no stats API. A capture from paddock-app (scratch/sandbox-top-NAME.txt on 2026-10-28) showed 11 of 18 cores busy with workerd, Playwright Chromium, and Vite. Paddock runs the same kind of script through `sbx exec` (one costs about 0.25 s and 0.12 s of Mac CPU), plus two snapshots of /proc/<pid>/stat a second apart for current per-process CPU. `sbx exec` starts a stopped sandbox, so polling must never reach one that is stopped or stopping.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Polling only reaches running sandboxes and pauses while one stops or is removed; it never starts a sandbox
- [x] #2 Works without ps in the image (reads /proc with sh, cat, tr, head, df, sleep)
- [x] #3 Parsers have fixture tests from real captures; doc UI describes the view
- [ ] #4 The project page lists the busiest processes now (CPU over one second, memory, command), grouped by app with counts, refreshed about every 5 s only while shown
- [ ] #5 Info shows the sandbox's CPU, memory, and disk (and load), read every 5 s only while Info is shown; nothing polls in the background
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SandboxTop: tagged summary and process scripts (sh, cat, tr, head, df, sleep; getconf optional), parser, per-process CPU over one second, grouping by app, mayPoll, read through sbx exec.
2. Info: Resources section (bars for CPU, memory, disk; load), polled every 5 s while shown; Processes button.
3. Processes host tab: hierarchical sortable Table (app / process, PID, CPU, memory, command), polled every 5 s while shown.
4. Fixtures from this Paddock sandbox; doc UI (Resources).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Dropped the user column (2026-10-28): /proc/<pid>/stat has no user, reading Uid from status needs more than the plain sh tools the script is limited to, and in a sandbox nearly everything runs as agent.

Fixtures: real output of both scripts from the paddock-paddock sandbox (18 CPUs), the process one while `yes` kept one CPU busy (1.007 cores measured). The earlier capture used an untagged draft and only lends command lines to the grouping test. A cmdline with newlines (bash -c) broke the line format: tr turns newlines into spaces too. 426 PaddockCore tests pass on Linux; the SwiftUI views compile only on the Mac.

Operator, 2026-10-28: no sidebar line, CPU/memory/disk under Info and fetched only while it is open; processes in a tab of their own, full width (chosen from three mockups). Removed AppModel's 10 s background loop; Info's Resources section and the Processes tab (hierarchical Table, sortable) poll only while shown. The Mac-side ps read for PAD-31's badge stays, every 30 s.
<!-- SECTION:NOTES:END -->
