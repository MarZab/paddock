---
id: PAD-3
title: OpenCode through the gateway end to end in the app
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - agents
  - gateway
  - verify
milestone: m-1
dependencies: []
priority: high
type: task
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OpenCode sandboxes get Paddock's OpenCode kit (2.1.4) and OPENCODE_CONFIG_CONTENT pointing at the project's gateway port (doc: ModelGateway, Wiring an agent to the gateway). Each piece was checked on its own; a full session in the app with tool calls on a local model has not been run. Open risk 1 in M0 findings: tool calling quality.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An OpenCode project on a local model, created in the app, answers through the gateway
- [ ] #2 opencode models in the sandbox lists only paddock/MODEL
- [ ] #3 A session that reads a file and runs a command works with the chosen model
- [ ] #4 Findings (model, quality) are noted in the ModelGateway doc
<!-- AC:END -->
