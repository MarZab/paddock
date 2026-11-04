---
id: PAD-60
title: Kit scripts run without the project's node (mise or any other version manager)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-30 08:06'
updated_date: '2026-10-30 08:27'
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
- [ ] #5 Checked on the Mac: after recreating paddock-app, voice settings and the browser watcher work there
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
<!-- SECTION:NOTES:END -->
