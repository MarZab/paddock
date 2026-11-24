---
id: PAD-146
title: 'Interactive tabs: A2UI v1.0 rendered natively, replacing OpenUI'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-24 20:26'
updated_date: '2026-11-24 20:27'
labels: []
dependencies: []
references:
  - 'https://a2ui.org/specification/v1.0-a2ui/'
  - 'https://github.com/a2ui-project/a2ui'
documentation:
  - backlog/docs/doc-9 - Browser.md
priority: high
type: feature
ordinal: 148000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive tabs (`paddock ui`) render OpenUI Lang with a vendored React bundle in a WebView. The operator chose to replace OpenUI with A2UI v1.0 (Google, Apache-2.0), rendered natively with the official Swift/SwiftUI library (github.com/a2ui-project/a2ui, tag v0.12.0+swift: A2UICore, BasicCatalog, A2UISwiftUI, BasicCatalogSwiftUI). Native rendering removes the WebView, CSP, paddock-ui:// scheme and vendored bundle; no code from the sandbox runs. The agent gets everything in the basic catalog (all 18 components and 14 functions, including Image, Video, AudioPlayer, openUrl and v1.0 agent/renderer function calls); the MCP catalog (McpApp runs sandbox HTML) is out.

Decided with the operator (2026-11-24):
- Protocol v1.0 only.
- Media (Image, Video, AudioPlayer URLs) is fetched inside the sandbox (sbx network rules apply), relative paths read sandbox files, data: is decoded on the Mac; the Mac never fetches an agent-chosen URL (it would bypass sandbox policy and reach llmman, gateway ports and the LAN).
- openUrl (user-activated only) opens a browser tab in the sandbox, like `paddock open URL`.
- A2UICore imports Combine, so it does not build on Linux (checked: OpenCombine builds, but its tests crash with signal 11 and 4 expression conformance cases fail). PaddockCore therefore never imports A2UI: it treats A2UI messages as JSON (framing, caps, catalog allowlist, media policy), Linux-tested. A new macOS-only package `Packages/PaddockA2UI` links A2UI.
- Paddock passes A2UI messages through unchanged in both directions (MessageProcessor.process(payload:) in, outboundListener out); Paddock events on `paddock wait` use their own shape.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Interactive tabs render A2UI v1.0 basic-catalog surfaces natively in SwiftUI; OpenUI is gone from the app, the sandbox guide and the docs
- [ ] #2 Every subtask is Done
<!-- AC:END -->
