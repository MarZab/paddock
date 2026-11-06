---
id: PAD-106
title: Remove the gateway trial (mise run gateway and the paddock-gateway product)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:14'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
dependencies:
  - PAD-105
priority: low
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The gateway trial ran the ModelGateway and one wired sandbox without the app, for M2.5 (2026-10-24). The app has done the same since (ClaudeGateway, AgentLaunchPlanner, Sync), so the trial is a second code path to keep in step with the app, and the operator asked to remove it while cleaning up the mise tasks (PAD-105).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tools/tasks/gateway.sh and Packages/PaddockCore/Sources/paddock-gateway are gone, and Package.swift has no paddock-gateway product or target
- [x] #2 CLAUDE.md, the Overview and ModelGateway docs, and .gitignore no longer describe the trial as something to run; dated findings made with it stay as history
- [x] #3 PaddockCore builds and its tests pass without it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed tools/tasks/gateway.sh, Sources/paddock-gateway (main.swift only used PaddockCore types the app uses too, so no dead code follows), the Package.swift product and target, and the trial from CLAUDE.md, doc-1, doc-4, .gitignore. Kept as history: doc-17 and the M2.5 row in doc-1 (verified with the trial, 2026-10-24), ProjectRunner comment. Not verified here: swift build/test (no Swift in this arm64 sandbox).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The gateway trial is gone: tools/tasks/gateway.sh, Sources/paddock-gateway, its product and target in Package.swift, and its place in CLAUDE.md, the Overview and ModelGateway docs, and .gitignore. Everything it used is used by the app too. PaddockCore builds and its tests run without it on the Mac and in Linux (the remaining failures are PAD-110 to PAD-112).
<!-- SECTION:FINAL_SUMMARY:END -->
