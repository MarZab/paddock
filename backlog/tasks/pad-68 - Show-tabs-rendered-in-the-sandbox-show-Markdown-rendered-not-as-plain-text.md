---
id: PAD-68
title: 'Show tabs rendered in the sandbox show Markdown rendered, not as plain text'
status: To Do
assignee: []
created_date: '2026-11-01 15:42'
labels:
  - kits
  - browser
dependencies:
  - PAD-67
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PAD-67 made `paddock open FILE.md --native` render Markdown on the Mac. Without `--native` the file opens in the sandbox Chromium as a file: URL, where a .md file is plain text, so agents that show a report the default way still get raw Markdown. Paddock never renders sandbox content on the Mac outside native tabs, so the rendering has to happen in the sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `paddock open x.md` (no --native) shows the file rendered in its show tab: headings, tables, lists, code
- [ ] #2 Rendering happens inside the sandbox; nothing new runs on the Mac and no network is needed (a vendored renderer, integrity-checked like OpenUI)
- [ ] #3 Relative images beside the file still load; reload and goto re-render after the file changes
- [ ] #4 Browser doc updated
<!-- AC:END -->
