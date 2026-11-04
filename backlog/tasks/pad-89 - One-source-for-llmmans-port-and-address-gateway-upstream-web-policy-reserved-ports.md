---
id: PAD-89
title: >-
  One source for llmman's port and address (gateway upstream, web policy,
  reserved ports)
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - architecture
  - security
  - gateway
dependencies: []
priority: low
type: chore
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. 17434 is written in ModelGateway.Configuration.upstream (as a URL string), LlmmanWebPolicy.port, and AppConfig.llmmanPort/reservedPorts. The security rules depend on all three agreeing (deny for llmman's port, no project may name it). Drift between them would silently weaken a deny.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A single LlmmanEndpoint constant (host, port, origin URL) used by all three, plus a test that the gateway default upstream, the web policy origin and the reserved port list agree
- [ ] #2 No literal 17434 left outside that constant and test fixtures
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AppConfig.llmmanPort is now the only definition (gateway upstream, LlmmanWebPolicy, LlmmanAPI, PolicyPlanner, LlmmanHealth); test LlmmanEndpointTests. NOT compiled.
<!-- SECTION:NOTES:END -->
