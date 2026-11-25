---
id: PAD-150
title: >-
  paddock helper: wait keeps what came before it, a failed call frees the lock,
  valid tab ids in the guide
status: Done
assignee:
  - '@claude'
created_date: '2026-11-24 23:23'
updated_date: '2026-11-24 23:25'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 148000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while building A2UI tabs (pr/2026-11-25, PAD-146) and brought over on their own: (1) paddock wait printed only what happened after it started, so an answer or an event that came before the agent called it was lost (it now starts from what the agent last saw, agentSeen, which the other commands already keep); (2) fail() inside locked() exits the process without the finally, so the lock directory stayed and every paddock call waited up to 30 s for it; (3) the guide and the help used tab-k3f9 as the example id, which paddock never makes (ids are tab- and four lowercase hex digits).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 paddock wait prints operator events that came after the agent last looked but before wait started
- [x] #2 A paddock call that fails while holding the lock leaves no lock behind; the next call does not wait
- [x] #3 The guide and the help show a valid id (tab-a3f9); tests run the helper under Node for the first two
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
paddock wait starts from what the agent last saw (agentSeen), so an operator event before the call is printed; locked() frees the lock when fail() exits inside it; the guide and the help use tab-a3f9. PaddockHelperTests run the helper under Node for the first two; 607 + 36 tests and lint pass.
<!-- SECTION:FINAL_SUMMARY:END -->
