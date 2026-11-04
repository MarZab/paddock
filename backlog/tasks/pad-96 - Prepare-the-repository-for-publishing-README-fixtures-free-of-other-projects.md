---
id: PAD-96
title: 'Prepare the repository for publishing: README, fixtures free of other projects'
status: In Progress
assignee: []
created_date: '2026-11-04 19:09'
updated_date: '2026-11-04 19:26'
labels:
  - publishing
dependencies: []
priority: medium
type: chore
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04 found a real project (another project) and a code audit of an unrelated product in the test fixtures, hardware details in the Overview doc, and a README that did not say what a newcomer needs (macOS 26, first run, forks). History is left as is and will be squashed later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No fixture, test, source or doc names another project or product (backlog task text that still names another project: PAD-73, 73.1, 73.3, 75)
- [ ] #2 README states the real requirements, how to make a fork, a first-run guide, the security model and how to contribute
- [x] #3 A LICENSE file chosen by the owner
- [ ] #4 mise run test passes on the Mac (fixtures were renamed without a compiler)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Other project names and an unrelated product audit were scrubbed from the tree, backlog text included; history is left for the squash. Checked with a case-insensitive search of the tracked files.
<!-- SECTION:NOTES:END -->
