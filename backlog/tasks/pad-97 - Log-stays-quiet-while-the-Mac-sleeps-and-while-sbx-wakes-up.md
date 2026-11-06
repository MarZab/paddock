---
id: PAD-97
title: Log stays quiet while the Mac sleeps and while sbx wakes up
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06 07:23'
updated_date: '2026-11-06 07:38'
labels:
  - app
  - sbx
  - log
dependencies: []
priority: high
type: bug
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator log from 2026-11-05/06: with the Mac asleep overnight (dark wakes, Power Nap), Paddock logged about 400 lines of the same background-read failures: "Could not read <project> from sbx" for two projects with sbx 503 (the host is not fully awake, post-resume hold-off) and "not signed in to Docker", each followed by an empty line, plus "The checks did not finish" and "the command ran longer than 900 s and was ended" for an sbx ls. PAD-25 clears such errors when sbx recovers, but every failure was still logged: two projects alternated as lastError, so neither counted as a repeat. A cancelled read (a view going away) was also logged as CancellationError().
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A background read failure is logged once; the same message again for the same read kind is not logged until that read works
- [ ] #2 A cancelled read (CancellationError) is not logged as an error
- [ ] #3 Between the system going to sleep and its full wake, the timed reads (checks, host processes, snapshots) are skipped; after wake they run again
- [ ] #4 A failed command whose output ends with a newline adds no empty log lines
- [ ] #5 Background sbx reads end after a short timeout, not the 15 min one used for creates
- [x] #6 Core tests cover the log line splitting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented: readFailed skips a message already logged for the same ReadKind; CancellationError not logged (refreshSnapshot, refreshAllSnapshots, checks); systemAsleep from NSWorkspace willSleep/didWake skips the refresh timer, host processes, and snapshot reads, and refreshes on wake; LogEntry.lines(of:) drops trailing empty lines; StatusProbe (and so every sbx read through probe.reads) and readRunner use FoundationProcessRunner(timeout: 90 s). Core tests pass on Linux (LogFilterTests); the 4 other failures fail on origin/main too. App/ NOT compiled here: needs a Mac build and a night of sleep to check AC1-5.
<!-- SECTION:NOTES:END -->
