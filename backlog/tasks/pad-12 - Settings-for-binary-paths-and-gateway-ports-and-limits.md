---
id: PAD-12
title: Settings for binary paths and gateway ports and limits
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - app
  - config
milestone: m-3
dependencies: []
priority: low
type: feature
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The design had a Settings sheet for binary paths and the gateway's ports and limits. Today these come from paddock.toml (File > Edit paddock.toml) and the binary lookup (doc: App config, ProcessRunner). Decide whether a Settings window is still wanted; if so, it edits paddock.toml through AppConfigFile with the same validation as a hand edit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision recorded in this ticket
- [ ] #2 If built: Settings shows the binary paths found and the models section, and writes paddock.toml only after validation
<!-- AC:END -->
