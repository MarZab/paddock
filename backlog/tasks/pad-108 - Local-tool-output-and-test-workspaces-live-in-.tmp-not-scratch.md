---
id: PAD-108
title: 'Local tool output and test workspaces live in .tmp, not scratch'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:26'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
dependencies: []
priority: low
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repo had two ignored folders for throwaway output: scratch/ (test workspaces, hang and M0 captures) and .tmp/ (test runs, PAD-107). One hidden folder keeps the root tidy and gives agents one place to look.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 mise run hang writes to .tmp/hangs, mise run capture:cli its throwaway projects and builds to .tmp/m0
- [x] #2 CLAUDE.md, README.md, the Overview doc, .swiftlint.yml and .gitignore name .tmp; committed fixtures keep the scratch paths they were captured with
- [x] #3 An existing scratch/ folder stays ignored until the operator moves or deletes it (its folders may be Paddock projects with sandboxes)
- [x] #4 mise run capture:cli, capture:socket and capture:fixtures use .tmp/captures (was m0/raw) and .tmp/capture-projects; the build tasks and icon write to .tmp/build (was build/); the operator's existing captures (m0/raw, scratch/hangs) are moved there
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixture paths (scratch/m0/run/...) are recorded sbx output and stay; a new capture records .tmp/m0. FolderPolicy refuses only its sensitive entries, so trial projects under .tmp/ pass. The operator's scratch/ (app1, app2, hangs, kitcheck, m0, sandbox, ...) was left in place.

Moved m0/raw (257 files) to .tmp/captures and scratch/hangs (3) to .tmp/hangs; m0/ held only a .DS_Store and is gone. build/ (7 GB) left for mise run clean, which removes it as the old build output.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Local output lives in .tmp/ (gitignored): .tmp/build (Xcode builds, icon tools), .tmp/test-runs, .tmp/captures (was m0/raw), .tmp/capture-projects, .tmp/hangs. The operator's captures were moved there; m0/ is gone. scratch/ stays ignored until the operator moves its projects. Committed fixtures keep the paths they were captured with.
<!-- SECTION:FINAL_SUMMARY:END -->
