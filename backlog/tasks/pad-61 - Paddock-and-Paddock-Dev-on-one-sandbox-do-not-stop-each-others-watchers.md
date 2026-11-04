---
id: PAD-61
title: Paddock and Paddock Dev on one sandbox do not stop each other's watchers
status: Done
assignee:
  - '@claude'
created_date: '2026-11-01 06:52'
updated_date: '2026-11-04 19:20'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With the installed Paddock and Paddock Dev (PAD-40) both running, each follows the same sandbox's paddock-agent-watch (and browser and voice watchers). SandboxWatchers.replaceScript stops every watcher of its kind on each start, so the two apps kill each other's watcher in turn: the killed app's stream ends, it clears the agents' states (tab and sidebar marks go blank), restarts after 2 s, and kills the other one. The marks flicker every few seconds while the agents do nothing. Fix: each app tags its watcher with its bundle ID (an argument the watchers ignore) and replaces only its own and untagged (older) watchers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each watcher started in a sandbox carries the starting app's bundle ID on its command line
- [x] #2 A start replaces only the same app's watchers and untagged ones from earlier versions; another app's watcher keeps running (test)
- [x] #3 Mac-side leftover detection still recognizes the tagged sbx exec command (test)
- [x] #4 backlog doc Kits, Watchers describes the tag
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SandboxWatchers.owner: bundle ID (letters, digits, . -), passed as $2; the watcher runs as WATCHER --for=OWNER.
2. replaceScript kills exact untagged and own-tagged command lines only.
3. isWatcherExec accepts the trailing owner word.
4. Tests: other owner's watcher survives; update argument expectations; doc-8 Watchers.

5. Second cause (operator saw the flicker with only one Paddock running): every watcher end cleared the states, so marks blinked working -> finished -> working. Now the states survive a restart (resync, 3 s) and each end is logged with its run time.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core tests pass on Linux (mise run test). Not built on the Mac yet. Still unknown: what ends the agent watcher when only one Paddock runs; the new Sandbox activity log line (paddock-agent-watch in X ended after Ns (reason)) should show it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All acceptance criteria were met; see the implementation notes. Closed in the 2026-11-04 backlog cleanup.
<!-- SECTION:FINAL_SUMMARY:END -->
