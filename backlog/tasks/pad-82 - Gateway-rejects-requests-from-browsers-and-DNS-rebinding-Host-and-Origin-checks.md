---
id: PAD-82
title: >-
  Gateway rejects requests from browsers and DNS rebinding (Host and Origin
  checks)
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - gateway
dependencies: []
priority: high
type: bug
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. The gateway listens on 127.0.0.1:<port> and, by design, has no token: the port identifies the project (backlog doc ModelGateway, Security rules). GatewayPolicy.decide never looks at the Host or Origin header. Any web page in the operator's Mac browser can POST to http://127.0.0.1:<port>/v1/messages (a simple CORS request with text/plain passes pinModel's JSON parse), and a DNS-rebinding page can read the replies. Any other local process can use the operator's model the same way. The sandbox traffic arrives through sbx's host proxy, so its Host header is predictable and can be allowlisted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A request whose Host header is not 127.0.0.1:<its port>, localhost:<its port>, [::1]:<its port> or host.docker.internal:<its port> gets 403, checked before routing; after finding out what sbx sends, the allowlist is exactly that
- [ ] #2 A request with an Origin header gets 403 (agents and sandbox proxies send none), and OPTIONS preflights get 403 with no CORS headers
- [ ] #3 Tests in GatewayTests: rebinding host, browser origin, correct host passes, IPv6 literal; the gateway trial script (mise run gateway) still works against a real sandbox
- [ ] #4 backlog doc ModelGateway and Security rules name the new rule
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Host/Origin checks in GatewayPolicy.decide with tests in GatewayTests; docs ModelGateway and Security rules updated. Written in a sandbox without a Swift toolchain (swift.org download blocked): NOT compiled or run. Run mise run test on the Mac, then check AC1's allowlist against what sbx really sends as Host (mise run gateway), then close the ACs.
<!-- SECTION:NOTES:END -->
