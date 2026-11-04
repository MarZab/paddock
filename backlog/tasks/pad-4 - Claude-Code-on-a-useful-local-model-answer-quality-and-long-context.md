---
id: PAD-4
title: 'Claude Code on a useful local model: answer quality and long context'
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - agents
  - models
  - verify
milestone: m-1
dependencies: []
priority: medium
type: spike
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The gateway trial verified Claude Code through the gateway on a 0.8B model (doc: M0 findings, open risk 2). Still open: answer quality and long context with a model worth using; Claude Code assumes a 200k context for unknown model names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Claude Code project on a larger local model completes a multi-step coding task in a scratch/ project
- [ ] #2 What happens when the context goes beyond the model's window is known and written down
- [ ] #3 If a setting is needed (such as a context size variable), a follow-up ticket exists
<!-- AC:END -->
