---
id: PAD-100
title: 'sandboxd socket: capture and support API 0.49'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 07:23'
updated_date: '2026-11-06 07:38'
labels:
  - sbx
  - socket
dependencies: []
priority: medium
type: task
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx was updated and sandboxd reports API 0.49.0; SandboxdReads.supportedAPIVersions has only 0.42, so Paddock falls back to the CLI for every read (status popover: Paddock does not know its socket yet). The routes and shapes must be captured from real traffic before 0.49 is accepted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 mise run socket proxy --swap run on the Mac against API 0.49; the raw capture is in m0/raw/socket
- [x] #2 Each route SandboxdReads uses is compared with the 0.42 capture; changed shapes get new sanitized fixtures and decoding
- [x] #3 0.49 is added to supportedAPIVersions only when every read decodes, with fixture tests for 0.49 next to the CLI output
- [x] #4 SbxService doc names the captured API versions
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Capture m0/raw/socket/proxy-swap-20261106-083051 (sbx 0.51.0, API 0.49.0). Shapes against 0.42: /daemon/health adds runtime_backend; /policy/network/rules adds policy_name and reason per rule; /policy/network/log, /user-prompts, /events unchanged; /sandbox adds additional_workspaces, host_mounts, ports, working_dir, effective_working_dir and new labels. The one that mattered: sbx ls lists additional_workspaces in workspaces (read-only with :ro), which SandboxdReads dropped, so a socket read would have lost extra folders and the sbxenv.yaml. sanitize-fixtures.py writes later APIs to sandboxd/<api>/, maps every path the same way in socket and CLI files, turns public IPs into 203.0.113.N, and swaps hosts in rule text before sandbox names (a private subdomain leaked otherwise).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
API 0.49 accepted. SandboxdReads maps additional_workspaces into workspaces as sbx ls does. Fixtures in sandboxd/0.49 (sanitized, checked for private names, hosts and IPs); the socket-vs-CLI tests run for 0.42 and 0.49 (47 sandboxd tests pass on Linux). doc SbxService updated.
<!-- SECTION:FINAL_SUMMARY:END -->
