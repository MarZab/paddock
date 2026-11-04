---
id: PAD-88
title: >-
  Gateway: bound open connections, header and idle time, and count requests
  while their body is still arriving
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - gateway
  - reliability
dependencies: []
priority: medium
type: task
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. ModelGateway buffers each request body up to maxBodyBytes (32 MB default) per connection before the per-project limiter (maxConcurrentPerProject = 2) is consulted, there is no limit on connections, and there is no read timeout, so a sandbox (or a local process) opening many slow connections ties up memory and sockets. The 429 path also writes no log entry, so the log drawer cannot show it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Limits on connections per listener and per project, an idle/read timeout on the inbound side, and a header size limit, all in AppConfig.models with defaults
- [ ] #2 A 429 and a 413 write a GatewayLogEntry like any other decision
- [ ] #3 Tests: many idle connections, a slow body, a body over the limit; the limiter is released on every exit path (client closes while waiting)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done: maxConnections (32) with admit/release, 429 logged, test connectionsAreBounded. Not done: idle/read timeout and header limit (an inbound idle timer would also cut a long generation; needs request-phase tracking), AppConfig keys. NOT compiled.
<!-- SECTION:NOTES:END -->
