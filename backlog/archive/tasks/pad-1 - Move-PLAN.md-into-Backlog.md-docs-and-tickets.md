---
id: PAD-1
title: Move PLAN.md into Backlog.md docs and tickets
status: Done
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-10-25 15:57'
labels:
  - docs
dependencies: []
priority: medium
type: docs
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PLAN.md mixed the design, the state of the app, and what was still missing. Split it into Backlog.md docs that describe the app as it is, give every missing piece a ticket, and make every commit start with its ticket ID.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Backlog.md is set up in the repo with task prefix PAD
- [x] #2 Every PLAN.md section is a doc under backlog/docs describing the current state
- [x] #3 Everything PLAN.md still listed as missing or unverified has a ticket
- [x] #4 Code comments point at the docs instead of PLAN.md
- [x] #5 CLAUDE.md describes the Backlog workflow and the ticket prefix on commits
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PLAN.md is replaced by 17 Backlog.md docs (doc-1 Overview to doc-17 M0 findings), one per section, corrected to what the code does today (no Reconciler, gateway log not shown, no Settings sheet, repo layout, milestone status in Overview). PAD-2 to PAD-21 cover everything PLAN.md listed as missing or unverified, in milestones M3.5 to M7. Code comments name docs instead of PLAN.md (comment-only changes, not built here: the sandbox is Linux). CLAUDE.md has the Backlog workflow and the PAD-N commit prefix; mise.toml pins backlog.md 1.54.0.
<!-- SECTION:FINAL_SUMMARY:END -->
