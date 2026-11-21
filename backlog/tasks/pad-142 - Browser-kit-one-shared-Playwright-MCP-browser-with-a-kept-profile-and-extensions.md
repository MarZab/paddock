---
id: PAD-142
title: >-
  Browser kit: one shared Playwright MCP browser with a kept profile and
  extensions
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-21 16:56'
updated_date: '2026-11-21 17:02'
labels:
  - browser
  - kits
dependencies:
  - PAD-141
priority: medium
ordinal: 144000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator wants the agent browser to keep logins and to run Chromium extensions. Extensions need a kept profile, and a kept profile allows one browser at a time, so one stdio server per agent (PAD-141) cannot share it. One Playwright MCP server per sandbox, over HTTP on localhost inside the sandbox, gives every agent the same browser. Checked on Linux: Chrome Headless Shell ignores extensions, full Chromium (PLAYWRIGHT_MCP_BROWSER=chromium) loads them; the server Host check accepts only localhost:PORT; killing the server leaves its Chrome running unless the whole process group is stopped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each sandbox start runs one Playwright MCP server on localhost:38324 in the sandbox (not published to the Mac), with a profile kept in /home/agent/.cache/paddock-browser/profile and a shared browser context
- [x] #2 Every unpacked extension folder (with manifest.json, a safe name) in /home/agent/.config/paddock-browser/extensions loads in its Chromium; `paddock-browser-mcp restart` picks up changes and stops the old browser with it
- [x] #3 Claude Code is registered with the server over HTTP (user scope) instead of a stdio server per session
- [x] #4 The agent instructions say the browser is shared and keeps its logins, how to add an extension, and that port 38324 is taken
- [x] #5 Tests cover the launcher config (extensions, profile, host, no unrestricted file access) and the registration; the Browser doc describes it
- [ ] #6 Checked live on the Mac: an extension loads, a login survives a sandbox restart, and the pages show in the Playwright tab
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. paddock-browser-mcp (Node launcher): writes the config (localhost:38324, shared context, kept profile, extension flags from the extensions folder), starts the real playwright-mcp in its own process group with its own environment; restart/stop end the group.
2. Kit: link the real playwright-mcp, install the launcher, start it on every start before registering Claude Code over HTTP.
3. Agent instructions, tests, Browser doc, changelog. Live check on the Mac stays open.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Ran the launcher from the dumped kit (paths pointed at a scratch home) on Linux: start with no extensions (page reports missing), copy an unpacked test extension in, restart (old Chrome gone), the extension content script ran (loaded); status lists it; stop leaves no Chrome and no listener; PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS set in the caller did not reach the server. Earlier: two HTTP clients share tabs; localStorage survived a server restart. Tests (634) and lint pass. Open: AC 1 and 6 on a real sandbox (the start step, the registry under the agent HOME so the watcher and dashboard see it).
<!-- SECTION:NOTES:END -->
