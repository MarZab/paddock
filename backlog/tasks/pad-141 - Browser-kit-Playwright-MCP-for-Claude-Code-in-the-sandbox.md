---
id: PAD-141
title: 'Browser kit: Playwright MCP for Claude Code in the sandbox'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-21 16:10'
updated_date: '2026-11-21 16:13'
labels:
  - browser
  - kits
dependencies: []
priority: medium
ordinal: 143000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents drive the browser only through playwright-cli in a shell. Claude Code also works well with Playwright MCP tools, and the operator asked for it in the browser kit. It runs in the sandbox only (stdio, no port, no Mac access), on the same Chromium build as playwright-cli. Research behind it: a browser on the Mac was considered and set aside for now (bot detection and Mac isolation trade-offs).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The browser kit installs `@playwright/mcp` pinned to the release built on the same Playwright as the pinned `@playwright/cli`, so no second Chromium is downloaded
- [x] #2 Claude Code in the sandbox has a `playwright` MCP server (user scope, stdio, headless, isolated profile, no unrestricted file access), registered again on every start
- [x] #3 A sandbox without Claude Code starts without errors from this step
- [x] #4 The agent instructions say when to use the MCP tools and that the operator does not see their pages (playwright-cli sessions for anything they should watch)
- [x] #5 KitsTests cover the pin and the registration; the Browser doc describes it
- [ ] #6 Checked live on the Mac: Claude Code lists the server and opens a page with it; whether its pages appear in the dashboard is written in the Browser doc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Pin @playwright/mcp 0.0.83 (Playwright 1.64.0-alpha-1790635538000, the same as @playwright/cli 0.1.22) in BrowserKit and install it globally with playwright-cli.
2. Startup step (user 1000): if claude is on the PATH, remove and add a user-scope stdio server `playwright` running `playwright-mcp --headless --isolated`; otherwise do nothing.
3. Agent instructions: MCP tools for quick checks of its own; playwright-cli sessions for anything the operator should watch.
4. KitsTests, Browser doc, CHANGELOG. Live check on the Mac stays open.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Pinned @playwright/mcp 0.0.83: npm shows it and @playwright/cli 0.1.22 both on playwright 1.64.0-alpha-1790635538000 (0.0.86 is on 1.66). Installed 0.0.83 on Linux: the stdio server answers initialize (Playwright 1.64.0-alpha-1790635538000) and lists 25 tools. The registration commands, run twice in a throwaway HOME, leave one mcpServers.playwright entry (stdio, playwright-mcp --headless --isolated). mise run test (632 tests) and mise run lint pass. Left for the Mac (AC 6): a real sandbox start, Claude Code listing and using the server, and whether its pages show in the dashboard. Extensions (asked in passing): Chromium can load unpacked ones through a config file with launchOptions args, but they need a kept profile, not --isolated; not part of this ticket.
<!-- SECTION:NOTES:END -->
