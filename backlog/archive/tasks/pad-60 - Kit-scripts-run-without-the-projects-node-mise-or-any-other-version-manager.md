---
id: PAD-60
title: Kit scripts run without the project's node (mise or any other version manager)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-30 08:06'
updated_date: '2026-11-06 09:41'
labels:
  - kits
  - bug
dependencies: []
priority: high
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock's kit scripts in the sandbox (paddock-voice, the browser kit's node scripts, the Claude Code settings merge) started with '#!/usr/bin/env node' (or ran 'node FILE'), so they ran whatever node is first on the sandbox's PATH. In a project whose image puts a version manager's shims first (paddock-app: mise, its mise.toml pins node 26.12.1, not installed), that node is the shim, which tries to install and fails: 'Could not tell the agent in paddock-app whether voice is on: mise ... Permission denied'. The project's image is the project's business (operator: do not investigate it); Paddock's scripts must work whatever node the project has: they find a node that runs themselves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Kit scripts run with a working node even when the project's node on PATH is a version manager's shim that fails
- [x] #2 Paddock sets no version-manager variables and runs no version-manager commands
- [x] #3 Tests cover the launcher (or the chosen interpreter path) in every kit script
- [x] #4 doc Kits updated
- [x] #5 Checked on the Mac in a recreated sandbox with the voice and browser kits (gik.si; paddock-app no longer exists): the scripts carry the launcher, run with a failing node first on PATH, and voice settings and the browser watcher work
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. NodeScript.header: /bin/sh first line, a JS-valid second line that tries each node on PATH, then /usr/local/bin and /usr/bin, with 'node -e 0' (stdin kept), and execs the first that runs; 127 with a message otherwise
2. Wrap every kit Node script with it; install steps run the merge with 'sh FILE'
3. SandboxWatchers' replace script also matches watchers running as an absolute node
4. Tests: broken shim first on PATH, sh FILE, no working node, every script has the header, watcher replacement through an absolute node
5. doc Kits
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
mise run test passes (496 + 31). Existing sandboxes keep their old scripts until recreated; paddock-app needs a recreate to pick this up. Not yet checked on the Mac in that sandbox.

2026-11-06 Mac check in gik.si (sbx 0.51.0; paddock-app no longer exists): paddock-voice, paddock and paddock-browser-watch carry the NodeScript header; paddock-voice words list and paddock --help exit 0; the browser watcher runs as /usr/local/bin/node /usr/local/bin/paddock-browser-watch for both Paddock and Paddock Dev, with the voice and status watchers; the Claude settings merge wrote 12 hook lines. gik.si's own node works, so a failing shim was simulated: a node that exits 1 first on PATH, and paddock-voice words list still exited 0. Voice in gik.si started listening with no 'Could not tell the agent' error in the Log. Not checked: a page from playwright-cli showing in the Playwright tab (the watcher itself runs).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Paddock's Node scripts in a sandbox (paddock-voice, the browser kit's paddock and watcher, the Claude settings merge) start with NodeScript.header: a /bin/sh line that tries each node on PATH, then /usr/local/bin and /usr/bin, and runs the first that starts, or exits 127 with a message. Paddock sets no version-manager variables and runs none. Tests cover every script's header, a broken shim first on PATH, sh FILE and no node; doc Kits describes it. Verified on the Mac in gik.si, with a failing node simulated first on PATH. Follow-up if it ever matters: a page in the Playwright tab was not looked at in this check.
<!-- SECTION:FINAL_SUMMARY:END -->
