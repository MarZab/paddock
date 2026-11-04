---
id: PAD-14
title: README with prerequisites and setup
status: In Progress
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-10-25 17:33'
labels:
  - docs
milestone: m-3
dependencies: []
priority: low
type: docs
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
There is no README. Write one with what Paddock is, the prerequisites table (the same commands as DependencyCheck's table in PaddockCore), the dev setup (mise install, mise run generate, the SwiftTerm plugin approval), and pointers to backlog/docs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README.md exists with the prerequisites table matching DependencyCheck's
- [ ] #2 Setup steps work in a fresh checkout
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
README.md written; its commands match mise.toml. #2 (fresh checkout) needs a run on the Mac.
<!-- SECTION:NOTES:END -->
