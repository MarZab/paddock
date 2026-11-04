---
id: PAD-30
title: 'Paddock leaves no sbx watchers behind, on the Mac or in sandboxes'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-28 20:59'
updated_date: '2026-10-28 21:51'
labels:
  - core
  - app
  - crash
dependencies: []
priority: high
type: bug
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Captures on 2026-10-28 found five `sbx exec paddock-app paddock-browser-watch` processes on the Mac whose parent was gone (one per Paddock restart that day, about 86 MB each), and inside the sandbox six `paddock-browser-watch` (Node, about 75 MB each) and six `paddock-agent-watch`, of which only the newest pair belonged to the running Paddock. On quit, Paddock ends its terminals but not the `sbx exec` streams it follows, so their processes outlive it; after a crash nothing cleans up; and killing the `sbx exec` client on the Mac does not end its process in the sandbox. Each restart adds another pair in every sandbox with the kits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Quitting Paddock ends every long-running sbx process it started (watchers, the event stream, image builds)
- [ ] #2 On launch Paddock stops its own watchers left on the Mac by an earlier run: only processes of the current user whose parent is gone and whose command is exactly `sbx exec <sandbox> paddock-agent-watch` or `paddock-browser-watch`; it logs how many, and touches nothing else
- [x] #3 Starting a watcher stops older watchers of the same kind in that sandbox first, so at most one of each runs per sandbox, with any kit version (no sandbox recreate)
- [x] #4 The browser kit's one-off `paddock-browser-watch --captured ...` calls are never stopped by this
- [x] #5 Tests: the Mac process list parser and orphan match against a real `ps` capture, the in-sandbox cleanup script run on Linux, and quit ending tracked processes
- [x] #6 Docs (Kits, Browser, UI or SbxService as they apply) say how watchers are cleaned up
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Track every FoundationLineStreamer process; FoundationLineStreamer.terminateAll() ends them; AppModel calls it in willTerminate.
2. HostProcesses: parse `ps -axww -o pid,ppid,user,rss,%cpu,etime,command` (fixture from the operator's capture, sanitized).
3. SandboxWatchers: watch commands become `sbx exec N sh -c SCRIPT paddock-watch WATCHER`; the script stops older watchers of the kind (exact cmdline match) then execs the watcher. leftovers()/stopLeftovers() find and SIGTERM Mac-side orphans; AppModel runs it once at launch before starting watchers.
4. Found while testing: children inherited the blocked signal mask of Swift worker threads, so terminate() did nothing on Linux. Process.runUnmasked() in both runners.
5. Docs Kits (Watchers), Browser, ProcessRunner.

6. Watchers end with Paddock: sbx exec -i with an input pipe Paddock holds; the wrapper stops the watcher when that input ends (checked on the Mac that sbx passes the end of input on).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Signal mask: a child of a Swift worker thread had SigBlk fffffffe3bfbea27 with SIGTERM pending; sh unblocks its own mask, so only exec'd programs (sleep, sbx) were affected. PaddockShell's pty.c already resets the mask. Unknown whether macOS Foundation passes the mask on; runUnmasked holds either way. Test isolation: FoundationLineStreamer takes a RunningProcesses (shared by default) so the quit test does not end other tests' streams; fake watchers sleep 3 s, since a killed watcher's sleep keeps pipes it inherited from concurrent tests (that made an AgentStatusKit test wait 30 s). PaddockCore 407 and PaddockShell 26 tests pass on Linux. App changes (AppModel willTerminate and launch) are not compiled here: needs a Mac build and the checks in AC 1 and 2.

Mac check 2026-10-28: after the first new start, one watcher pair per sandbox (old six pairs gone). After quit the Mac-side sbx exec clients exited a few seconds later, but the in-sandbox pair stayed until the next start, so watchers now follow Paddock's input (sbx exec -i; killing the client closed stdin inside, checked on the Mac). Linux findings: a held-open input kept Foundation from noticing a child's exit, so the streamer closes it once output ends; children with SIGCHLD blocked hung in dash's wait, so tests start such shells through python3 that clears the mask. 409 PaddockCore tests pass on Linux, 6 runs.
<!-- SECTION:NOTES:END -->
