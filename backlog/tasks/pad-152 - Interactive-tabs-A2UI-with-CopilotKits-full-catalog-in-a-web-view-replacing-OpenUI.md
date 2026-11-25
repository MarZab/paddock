---
id: PAD-152
title: >-
  Interactive tabs: A2UI with CopilotKit's full catalog in a web view, replacing
  OpenUI
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25 07:31'
labels: []
dependencies: []
priority: high
type: feature
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator wants all of the A2UI catalog that CopilotKit's A2UI Playground offers (https://a2ui.open.bot, MIT, catalog https://copilotkit.ai/a2ui/catalogs/playground/v1: 121 components, 16 functions, charts including SankeyChart, data tables, maps, cards, inputs), and chose (2026-11-25) to render it with CopilotKit's own React renderer in a web view instead of SwiftUI (the native path is on pr/2026-11-25 and stays there). It replaces OpenUI. Facts found: the playground renders surfaces without its chat (StaticSurface: CopilotKit's Gen UI 2.0 surface renderer fed A2UI 1.0 operations); a surface hands each user event to an agent (copilotkit.runAgent) with the A2UI action message in forwardedProps.copilotkit.ui.metadata.extensions.copilotkit_action, so a page-local agent receives every action; built with Vite the whole catalog is a 4.1 MB host.js (1.2 MB gzip) plus lazily loaded chunks (Shiki grammars, Mermaid, MapLibre), 23 MB in all. Security (CLAUDE.md): the bundle is the app's, the agent's messages are data, the page loads only the app's files, never the network; media and links go through the sandbox; what the page sends back is checked; what the operator types reaches the sandbox on stdin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Interactive tabs render A2UI 1.0 surfaces of the playground catalog with CopilotKit's renderer in a web view; OpenUI is gone from the app, the sandbox guide and the docs
- [ ] #2 Every subtask is Done
<!-- AC:END -->
