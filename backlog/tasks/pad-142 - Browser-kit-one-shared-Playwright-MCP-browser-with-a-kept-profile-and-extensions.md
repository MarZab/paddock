---
id: PAD-142
title: >-
  Browser kit: one shared Playwright MCP browser with a kept profile and
  extensions
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-21 16:56'
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
- [ ] #2 Every unpacked extension folder (with manifest.json, a safe name) in /home/agent/.config/paddock-browser/extensions loads in its Chromium; `paddock-browser-mcp restart` picks up changes and stops the old browser with it
- [ ] #3 Claude Code is registered with the server over HTTP (user scope) instead of a stdio server per session
- [ ] #4 The agent instructions say the browser is shared and keeps its logins, how to add an extension, and that port 38324 is taken
- [ ] #5 Tests cover the launcher config (extensions, profile, host, no unrestricted file access) and the registration; the Browser doc describes it
- [ ] #6 Checked live on the Mac: an extension loads, a login survives a sandbox restart, and the pages show in the Playwright tab
<!-- AC:END -->
