---
id: PAD-78
title: Log page shows earlier sessions; lines reach the file while the UI is stuck
status: In Progress
assignee: []
created_date: '2026-11-04 12:55'
updated_date: '2026-11-04 12:57'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Creating a project froze Paddock (sbx 0.51, 2026-11-04). After the restart, the Log page showed nothing from before the force quit. Each session writes its own file in ~/Library/Logs/Paddock, but the page shows only the current session. Every line also hopped to the main actor before it was written (AppModel.appendLog), so once the main thread hangs, background work (the project's create steps, image builds) stops reaching the file, which is the moment it matters most. Related: PAD-27 (hang diagnostics).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lines from background work (`activityLog` sinks) are written to the session's log file before the main actor is involved, exactly once each
- [ ] #2 The Log page can show an earlier session: a picker lists the sessions in ~/Library/Logs/Paddock, newest first, labelled with when they started; this session stays the default
- [x] #3 An earlier session's file is read back into entries (time, error, category, message) with the same filters; a line Paddock cannot parse still shows, as text
- [x] #4 LogEntry's file line round-trips through the reader in tests, including errors, sources, and messages with colons and brackets
- [x] #5 backlog doc UI (Log) describes earlier sessions
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core: LogEntry(fileLine:), LogFiles.session(named:), sessions(_:current:), and entries(in:), with tests. The file line marks "no source" with `-`. App (not compiled here):
- AppModel.activityLog writes to LogFile before hopping to the main actor (showLog), and appendLog writes once.
- LogFile.sessions() and entries(ofSession:).
- ErrorLogView session picker.
AC1 and AC2 need a build and a look on the Mac.
<!-- SECTION:NOTES:END -->
