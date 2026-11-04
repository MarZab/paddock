---
id: PAD-13
title: Turn llmman's prompt history off through a confirmed sbx daemon restart
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - models
  - security
milestone: m-3
dependencies: []
priority: medium
type: spike
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
llmman writes the last user message of every request to prompts.jsonl; sbx does not set LLMMAN_NOHISTORY (doc: Models, Hardening; M0 findings, open risk 7). Paddock shows the file's size and offers Clear. Still open: whether LLMMAN_NOHISTORY=1 sbx daemon restart reaches llmman, and whether a daemon restart interrupts running sandboxes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both questions are answered on the Mac and written in the Models doc
- [ ] #2 If it works: an opt-in action restarts the daemon with the variable, only after operator confirmation, and the hardening check reflects it
- [ ] #3 If it does not: the Models doc says so and the action is not offered
<!-- AC:END -->
