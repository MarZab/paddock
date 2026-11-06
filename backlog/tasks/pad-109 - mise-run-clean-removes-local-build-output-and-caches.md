---
id: PAD-109
title: mise run clean removes local build output and caches
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:30'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
dependencies: []
priority: low
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Builds, SwiftPM caches, test runs and capture projects pile up in the checkout (over 8 GB), and a SwiftPM cache from before the repo moved (plane to paddock) broke swift test with module cache path errors. One task clears what the next run rebuilds, and on request the raw captures too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 mise run clean removes .tmp/build, .tmp/test-runs, .tmp/capture-projects, both packages' .build, and an old build/, printing each with its size
- [x] #2 --all also removes .tmp/captures and .tmp/hangs; without it they are kept and the task says so
- [x] #3 -n / --dry-run lists what would go and removes nothing
- [x] #4 scratch/ and any other folder in .tmp/ (projects) are never touched
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checked on a copy of the layout in a temp folder: plain run removes the six, keeps captures and hangs and says so; --all removes those; a project folder in .tmp and scratch/ stay; unknown argument exits 2; mise run clean --help shows the flags; dry runs on the real checkout list PaddockCore/.build 1.1G, build 7.0G, and with --all captures 30M, hangs 13M.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
mise run clean removes .tmp/build, .tmp/test-runs, .tmp/capture-projects, both packages' .build, an old build/, and in a Linux sandbox ~/.cache/paddock-build, each printed with its size; --all also .tmp/captures and .tmp/hangs; -n only lists. It never touches scratch/ or projects in .tmp/. Checked on a copy of the layout; on the real checkout only as a dry run.
<!-- SECTION:FINAL_SUMMARY:END -->
