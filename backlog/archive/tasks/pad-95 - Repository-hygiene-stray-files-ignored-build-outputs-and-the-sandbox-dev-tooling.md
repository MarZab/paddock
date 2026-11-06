---
id: PAD-95
title: >-
  Repository hygiene: stray files, ignored build outputs, and the sandbox dev
  tooling
status: Done
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
  - hygiene
dependencies: []
priority: low
type: chore
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. Findings: .DS_Store and .idea/ are in the working tree (ignored, but .idea is listed with .DS_Store in .gitignore only partly: check git ls-files); Packages/PaddockCore/.build exists next to the tracked sources and ordinary text searches walk 800 KB of dependency checkouts; tools/sandbox/run.sh create passes --force and replaces a sandbox of the same name without asking, and is outside shellcheck (see the lint ticket); scripts/ mixes Python, Node and shell with no README (m0-capture.sh is 632 lines, socket-capture.py 1017); m0/ and design/ at the root have no index; the dev sandbox moved from tools/sandbox/paddock-dev/ (dockerfile) to tools/sandbox/paddock/ (kit) in the working tree, uncommitted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tools/sandbox/run.sh create asks before replacing, or needs an explicit --replace flag
- [x] #2 scripts/README.md lists each script, who runs it (operator Mac, sandbox, CI) and what it writes
- [x] #3 m0/ and design/ each get a short README or move under docs/; .gitignore covers .idea/ and .DS_Store explicitly and git ls-files shows none of them
- [x] #4 The uncommitted dev-sandbox change is committed under its own ticket, with the docs that name tools/sandbox/paddock-dev updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done: tools/sandbox/run.sh create needs --replace, scripts/README.md. Wrong in the ticket: .idea and .DS_Store are ignored and untracked already. Not done: the uncommitted dev-sandbox change (the operator's own work) and m0/design READMEs.

2026-11-06: m0/ and design/ are gone rather than documented: m0/ held only ignored raw captures (now .tmp/captures, PAD-108), and design/app-icon.svg moved to App/AppIcon.svg beside the asset catalog it renders into (excluded from the app target). .gitignore lists .DS_Store and .idea/; git ls-files has none.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
run.sh create needs --replace; scripts/README.md became tools/tasks/README.md (PAD-105); m0/ and design/ are gone (raw captures in .tmp/captures, the icon source at App/AppIcon.svg, excluded from the app target); .DS_Store and .idea/ are ignored and untracked; the paddock-dev kit was replaced by tools/sandbox/paddock (PAD-22) and no doc names paddock-dev any more.
<!-- SECTION:FINAL_SUMMARY:END -->
