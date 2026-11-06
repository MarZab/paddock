---
id: PAD-110
title: GatewayTests.forwardsOnlyAllowedHeaders sends a Host the gateway now refuses
status: Done
assignee: []
created_date: '2026-11-06 08:47'
updated_date: '2026-11-06 09:22'
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
- [x] #1 forwardsOnlyAllowedHeaders uses an allowed Host and still checks that only anthropic-version and content-type are forwarded
- [x] #2 A refused Host is covered by its own test (if PAD-82's tests do not already)
- [x] #3 mise run test passes this test on the Mac and in a sandbox
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed in Linux sandbox: test uses Host localhost:17500; refused hosts covered by refusesRebindingHostsAndBrowserOrigins. AC3 needs a run on the Mac.

AC3: forwardsOnlyAllowedHeaders passed on the Mac (.tmp/test-runs/2026-11-06_10-14-33.log, 85d5464) and in Linux (10-08-26).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
forwardsOnlyAllowedHeaders sends Host localhost:17500 and still checks that only anthropic-version and content-type are forwarded; refused hosts stay covered by refusesRebindingHostsAndBrowserOrigins. Passes on the Mac and in Linux.
<!-- SECTION:FINAL_SUMMARY:END -->
