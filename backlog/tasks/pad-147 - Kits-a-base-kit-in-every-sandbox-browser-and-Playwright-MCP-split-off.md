---
id: PAD-147
title: 'Kits: a base kit in every sandbox; browser and Playwright MCP split off'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-24 21:45'
updated_date: '2026-11-25 06:40'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 155000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock's tabs (paddock ui interactive tabs, native tabs, wait/feedback) and its sandbox guide came with heavier kits: the helper, the watcher and the OpenUI Lang reference with the browser kit (playwright-cli, Chromium, certutil, Playwright MCP), the guide with the status kit. Asking the operator something pulled in Chromium, and turning status off (to keep its hooks out of Claude Code) dropped the agent's sandbox instructions. Playwright MCP (a server, an entry in Claude Code's config, a kept profile with logins) could not be had without it or left out. Decided with the operator (2026-11-24): one ticket for the whole split; the base kit optional and recommended. The watcher and helper keep their names (paddock-browser-watch, paddock), so sandboxes not yet recreated keep working.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The status kit carries only agent state (helper, watcher, Claude Code hooks, OpenCode plugin); the guide is gone from it
- [x] #2 The browser kit needs the base kit and keeps playwright-cli, Chromium, certutil and the proxy CA, the dashboard, the wrapper and its guide; without it paddock open URL, page reload/back/goto and annotate fail saying they need the browser kit, and the watcher reports no sessions
- [x] #3 A browser-mcp kit, on the browser kit, installs, starts and registers the shared Playwright MCP server, with its guide; the browser kit no longer does
- [x] #4 Existing projects get the base kit through chosenKits; the app follows the watcher for every sandbox that has the base kit or an older browser kit
- [x] #5 Tests cover the kits' specs, the selection and the page-command refusal; doc Kits and doc Browser describe the kits as they are
- [x] #6 A base kit (Paddock's, needs node, recommended and offered in the picker like any kit, so a project may leave it out) installs paddock, the tab watcher and the interactive tabs' reference, and carries the sandbox guide and the tabs guide; a kit choice from before it (no kitChoice recorded) still gets it, a choice made since is taken as it is
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BaseKit (paddock-base, needs node): paddock, paddock-browser-watch (names kept for sandboxes not yet recreated), the A2UI reference, SandboxGuide plus the tabs guide; KitSelection.always adds it in chosenKits, the picker hides it. 2. AgentStatusKit: agent state only. 3. BrowserKit: needs base; playwright-cli, Chromium, certutil, CA, dashboard, wrapper, browser guide; the helper's cli() refuses without playwright-cli and the watcher skips sessions. 4. BrowserMCPKit (paddock-browser-mcp, needs browser, Claude Code only, not recommended): MCP install, launcher, start, Claude registration, guide. 5. AppModel follows the watcher with the base kit or an older browser kit. 6. Tests, doc Kits, doc Browser, doc Overview, CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done in the Linux sandbox; 635 + 36 tests and lint pass. Consequences: every sandbox now gets the node kit through base (a copy of Node's official image), also projects that chose no kits; projects that chose the browser kit lose Playwright MCP at their next recreate unless browser-mcp is added (Info tab, Kits), since it is opt-in now; openUrl in an A2UI tab needs the browser kit (the reference says so). Not yet on the Mac: the app build (KitPicker hides base, the watcher follows base-kit sandboxes) and a recreated sandbox without the browser kit (tabs and the watcher without playwright-cli).

Operator asked (2026-11-24) to make the base kit optional: it is recommended and shown in the picker; Project.kitChoice (KitSelection.choiceRevision) tells a choice made since PAD-147 from an older one, which keeps getting base (KitSelection.addedToOlderChoices) since the status and browser kits carried its parts then. Unticking base unticks browser, which needs it.

Built on the Mac at 401b0e4 (no warnings). Left: a recreated sandbox without the browser kit (tabs work, live pages refused), one with browser and browser-mcp, and one with base unticked.

Checked by the operator in a project on the Mac (2026-11-24): works.

Ported to pr/2026-11-25-web (2026-11-25) on the OpenUI code: the base kit carries the OpenUI Lang reference (BaseKit.openUIReference) and OpenUI's ui guide; the page-refusal test lives in PaddockHelperTests. 609 + 36 tests and lint pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Paddock's kits are split by what they bring. base (paddock-base, needs node, recommended, optional) installs paddock, the tab watcher and the interactive tabs' reference, and carries the sandbox guide and the tabs guide; it downloads nothing. status is agent state only. browser needs base and is the browser: playwright-cli, Chromium, certutil and the proxy CA, the dashboard, the wrapper; without it paddock refuses live pages with a message naming the kit, and the watcher reports no sessions. browser-mcp (Claude Code only, opt-in) installs, starts and registers the shared Playwright MCP server. The helper and watcher keep their names, so older sandboxes work until recreated; a project records kitChoice, and a choice from before the base kit keeps getting it. Built first on the A2UI branch (pr/2026-11-25), tested on the Mac and used in a project; brought to this branch on the OpenUI code (its reference in the base kit).
<!-- SECTION:FINAL_SUMMARY:END -->
