---
id: PAD-110
title: GatewayTests.forwardsOnlyAllowedHeaders sends a Host the gateway now refuses
status: To Do
assignee: []
created_date: '2026-11-06 08:47'
labels:
  - tests
  - gateway
dependencies: []
priority: medium
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The test sends Host: evil among the headers it expects to be stripped, but since PAD-82 GatewayRoutes refuses a request whose Host is not one of allowedHostNames (DNS rebinding), so the decision is a refusal and the test records "not forwarded". Fails on the Mac and in Linux, and at 81f2c45, so it predates today's tooling changes. The header filter itself is not what fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 forwardsOnlyAllowedHeaders uses an allowed Host and still checks that only anthropic-version and content-type are forwarded
- [ ] #2 A refused Host is covered by its own test (if PAD-82's tests do not already)
- [ ] #3 mise run test passes this test on the Mac and in a sandbox
<!-- AC:END -->
