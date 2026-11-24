---
id: PAD-143
title: >-
  Browser tabs keep their web view while hidden, and the Playwright tab stays
  once shown
status: In Progress
assignee: []
created_date: '2026-11-21 19:06'
updated_date: '2026-11-21 19:08'
labels: []
dependencies: []
type: bug
ordinal: 145000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Switching from the Playwright tab (or a show tab rendered in the sandbox) to another tab and back built a new WKWebView: the dashboard loaded again from scratch, the selected session and anything the operator did were gone. The Playwright tab also disappeared whenever the agent's browser briefly had no pages (an MCP browser reconnecting), and with it the operator's selection. Keep each browser tab's web view while its tab exists, as TerminalViewCache does for terminals; keep the Playwright tab once it has appeared until the operator closes it or the sandbox stops.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Showing the Playwright tab again after another tab puts the same web view back, without a reload
- [ ] #2 Refresh still reloads the dashboard
- [ ] #3 Closing the tab, the show going away, or the sandbox stopping releases the kept web view
- [ ] #4 The Playwright tab stays when the agent's browser has no pages for a moment; it goes only when the operator closes it or the sandbox stops
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BrowserWebViewCache (App/BrowserViews.swift) on ProjectTerminals keeps each browser tab's WKWebView via its coordinator, keyed by tab and port+select script, like TerminalViewCache. Released on Refresh/Check Again/started dashboard, tab close, show gone, sandbox stop. BrowserTab shows a kept view at once while the port is checked again. playwrightShown keeps the Playwright tab once it appeared until closed or the sandbox stops. Lint clean; not built or run on the Mac yet (the sandbox is Linux).
<!-- SECTION:NOTES:END -->
