---
id: PAD-75
title: 'mise kit in the kit list by default, not preselected'
status: Done
assignee: []
created_date: '2026-11-04 09:58'
updated_date: '2026-11-04 09:59'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Projects that pin their tools with mise (this repo, among others) need sbx's mise kit, which today only appears after the operator adds `[kits.mise]` to paddock.toml. The operator asked (2026-11-04) for it to be in the list by default but off.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `mise` is one of AppConfig.defaultKits, sbx's contrib kit pinned by digest, not recommended, offered for every agent
- [x] #2 paddock.toml's template and backlog doc Kits list it among the built-in kits; tests updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `mise` to AppConfig.defaultKits: sbx's contrib v2 kit `docker.io/sbx/mise-kit`, pinned to the digest of its 2026-10-26 `latest` (sha256:9c71...4083, from Docker Hub), not recommended, offered for every agent. The paddock.toml template and the contrib-kit examples now use `gh`, since an empty `[kits.mise]` section now changes the built-in instead of naming the unpinned contrib kit. KitsTests updated; full swift test on Linux passes (545). Not checked on the Mac: a sandbox created with the pinned mise kit.
<!-- SECTION:FINAL_SUMMARY:END -->
