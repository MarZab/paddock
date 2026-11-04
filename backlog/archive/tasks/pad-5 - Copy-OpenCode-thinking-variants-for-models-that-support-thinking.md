---
id: PAD-5
title: Copy OpenCode thinking variants for models that support thinking
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - agents
  - gateway
milestone: m-1
dependencies: []
priority: low
type: feature
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx's own OpenCode model kit adds variants that turn thinking on or off through chat_template_kwargs.enable_thinking. Paddock's OPENCODE_CONFIG_CONTENT does not have them yet. Read the model's capabilities from llmman's /api/show (capture a fixture first) and add the variants when it supports thinking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fixture of llmman's /api/show for a thinking and a non-thinking model is committed
- [ ] #2 OpenCode's config has thinking variants only for models that support thinking, with tests
- [ ] #3 The gateway still pins the model and forwards only allowlisted routes
<!-- AC:END -->
