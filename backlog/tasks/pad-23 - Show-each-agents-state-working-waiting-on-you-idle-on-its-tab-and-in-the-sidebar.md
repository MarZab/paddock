---
id: PAD-23
title: >-
  Show each agent's state (working, waiting on you, idle) on its tab and in the
  sidebar
status: In Progress
assignee: []
created_date: '2026-10-25 17:41'
updated_date: '2026-10-31 17:56'
labels:
  - app
  - agents
milestone: m-3
dependencies: []
priority: medium
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
There is no cross-agent standard, so a Paddock kit installs each agent's own signal and writes one state file in the sandbox. Claude Code: hooks (https://code.claude.com/docs/en/hooks): UserPromptSubmit, PreToolUse and PostToolUse -> working; PermissionRequest (fires at once, unlike the Notification permission_prompt, which waits about 6 s) and Notification elicitation_dialog/elicitation_url_dialog -> waiting; Stop and StopFailure -> idle; SessionEnd -> ended. OpenCode: a plugin in ~/.config/opencode/plugins (https://opencode.ai/docs/plugins/) on the event hook: session.status (busy/retry/idle), session.idle, permission.asked/permission.replied, question.asked/replied/rejected, session.error; busy and waiting sessions are tracked by session ID so a child session going idle does not hide the parent. The state is display-only data from inside the sandbox: Paddock validates it against a fixed set of states and never uses it for rules, mounts, or any decision. Doc updates: Kits, UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A status kit (Paddock builtin, on by default) installs paddock-agent-state, Claude Code's hooks (merged into ~/.claude/settings.json, existing hooks kept), and OpenCode's plugin, with tests of the generated files
- [x] #2 A watcher in the sandbox prints one JSON line per state change; AgentState parses it with a fixture-based test and rejects unknown states and oversized fields
- [x] #3 Checked on the Mac with Claude Code and OpenCode: each of working, waiting (permission and question), idle, and ended shows up in the state file; differences from the specs are written in the Kits doc
- [ ] #4 The project's terminal tab and its sidebar row show the state (a dot or badge, with waiting more prominent), and the menu bar extra can count waiting agents (PAD-10)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on Linux: AgentStatusKit (state helper, watcher, Claude Code hooks merged into settings.json, OpenCode plugin), AgentState parser, builtin kit 'status' (recommended, all agents); tests run the scripts and plugin for real. Found and fixed by the test: node's argv index in the merge script. AC 2 is half done (the watcher exists and works by hand; the app does not follow it yet). AC 3 and 4 need the Mac and Xcode. Kits doc has an Agent status section.

Per-session state: found on the Mac that one state file mixed two sessions. Now one file per session (session_id from the hook stdin) tagged with PADDOCK_TAB, which the app passes with sbx run -e when it opens an agent tab (App/TerminalViews.swift, not built here). AgentStates.state(ofTab:) is the lookup. Test caught a watcher that ignored TERM. Left: the app following the watcher, the badge views, OpenCode sharing a server across tabs.

Display written (not built here, no Xcode): AgentActivity/AgentStates.overall in PaddockCore; Tab.activity + TerminalTabs.setActivity + a mark on agent tabs in PaddockShell; AppModel.syncAgentWatchers follows paddock-agent-watch per running project; ProjectRow.dot(for:activity:) pulses the sandbox dot (orange when waiting). AC 4 half done: tab and sidebar done, menu bar count waits for PAD-10. AC 3 (Mac check) still open.

AC 2 stays open: AgentState tests use inline lines; a fixture of real paddock-agent-watch output from the Mac is still to capture.

Finished-while-away dot on agent tabs: AgentTabMarks (PaddockCore, tested), wired in ProjectTerminals.showAgentActivity/setTabs/close; the tab bar draws it. Not built here. 'Selected' means the selected tab of its half, whether or not the project is on screen.

2026-10-31 Mac check: working, waiting, idle and finished-while-away show on tabs and sidebar rows for Claude Code and OpenCode. Open: AC 2 (a fixture of real paddock-agent-watch output was not captured yet) and AC 4 (the menu bar extra count depends on PAD-10).

2026-10-31 Fixtures/agent/watch.jsonl holds real paddock-agent-watch output from the Mac; AgentStatusKitTests.parsesTheWatchersOwnOutput parses it (Package.swift copies Fixtures/agent). 497 PaddockCore tests pass on Linux.
<!-- SECTION:NOTES:END -->
