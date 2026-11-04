---
id: PAD-11
title: 'Show the gateway''s metadata log: log drawer and per-project model activity'
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-10-25 17:33'
labels:
  - app
  - gateway
milestone: m-3
dependencies: []
priority: medium
type: feature
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The gateway records a metadata entry per request (time, project, route, status, bytes, duration, token usage; never bodies or headers) and AppModel keeps the last 500 in gatewayLog, but no view shows them (doc: ModelGateway, Logging; UI). Add the log drawer and each project's model activity (requests, tokens in and out, errors).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A log drawer shows the gateway's entries, newest first, filterable by project
- [ ] #2 A project's Info shows its requests, tokens in and out, and errors
- [ ] #3 Nothing shown or kept includes a request or response body or header (test)
- [ ] #4 Error strings shown in the drawer are redacted of anything that looks like a key or token (test)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The Log window (App/LogFile.swift, ActivityLog.swift) now exists for image builds and errors; the gateway entries should join it rather than a second drawer.

Core done: GatewayActivity.summarize and newestFirst (PaddockCore/Gateway/GatewayActivity.swift, tests pass on Linux). Left: the SwiftUI views (gateway entries in the Log window with a project filter, activity in a project's Info) and the redaction test, which needs error strings the log entries do not carry yet. Views not built here (no Xcode).
<!-- SECTION:NOTES:END -->
