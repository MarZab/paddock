---
id: PAD-20
title: Decide on an automatic reconcile for Paddock's own per-sandbox rules
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - core
  - network
dependencies: []
priority: low
type: spike
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The design had a Reconciler actor that applied differences on launch, on config changes, and on events. What exists: GatewayHost.sync keeps the gateway listeners in line with the projects, and SandboxSync lists differences (missing sandbox, recreate, missing service denies, missing gateway rule) for the operator to Apply (doc: App config, Sync). A gateway rule went missing once (doc: ModelGateway). Decide whether Paddock's own per-sandbox rules (gateway allow, llmman deny) should be re-applied without asking. Global rules stay the operator's either way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision recorded in the App config doc
- [ ] #2 If automatic: only Paddock's own per-sandbox rules are touched, with tests that no global rule is changed
<!-- AC:END -->
