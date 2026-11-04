---
id: PAD-29
title: 'Host pattern matching compiles each glob once, not on every render'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-28 19:57'
updated_date: '2026-10-28 22:42'
labels:
  - core
  - performance
dependencies: []
priority: high
type: bug
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A sample of the Release build while switching projects (scratch/hangs/20261028-205436) showed ProjectDetailView.body taking about 1.5 s of main-thread time in 10 s of switching, most of it in `HostPattern.hostMatches`: it builds a new NSRegularExpression (ICU regex compile) for every pattern/host comparison, and the network rows, rule rows, PolicyPlanner.plan, sync items, and host rows make many such comparisons on every render. Switching projects felt slow. The deeper fix, computing these rows in AppModel when their inputs change instead of in body, is separate work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each host glob is compiled to a regular expression at most once per run (while the cache has room), and later matches reuse it
- [x] #2 Matching results are unchanged, including patterns that fail to compile (they compare literally)
- [x] #3 The cache is safe to use from any thread and does not grow without bound
- [x] #4 Tests cover the reuse and the existing glob semantics
- [x] #5 HostRules.validated builds its allowed character set once, not per call; which hosts it accepts is unchanged
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HostGlobCache (Mutex, bounded, starts over at its limit) keeps each compiled glob, failed compiles included.
2. HostPattern.hostMatches takes the cache (shared by default) instead of compiling per call.
3. Tests: compile once per pattern, literal fallback cached, limit, concurrent use; existing glob cases unchanged.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Behavior unchanged; only compilation is cached. The rows are still computed in body on every render; moving them into AppModel is the follow-up the description names. Full PaddockCore suite: 397 passed on Linux. Not yet measured on the Mac: rerun mise run hang while switching projects to compare with scratch/hangs/20261028-205436 (ProjectDetailView.body about 1.5 s of 10 s).

Second sample after the cache (scratch/hangs/20261028-210047): body down from about 1520 to 400 ms per 10 s of switching, no regex compiles. HostRules.validated was then the largest part (about 230 ms): it built CharacterSet.alphanumerics.union(...) on every call. Added to this ticket.

HostRules.validated: the allowed CharacterSet is a static let now. Tests pin the accepted characters (letters of any script, digits, . - _ * ? [ ] ! :) and more rejected ones (/ @ ; "). Full suite 397 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Project switches were slow because ProjectDetailView.body compiled an NSRegularExpression for every host pattern comparison and built a Unicode CharacterSet for every HostRules.validated call, on every render. HostGlobCache (Mutex, bounded) compiles each glob once; the allowed character set is a static let. Matching and validation are unchanged and tested. Measured on the Mac (Release): body time while switching went from about 1520 ms to 400 ms per 10 s after the cache, and the operator confirmed switching is a lot faster. Follow-up idea, not filed: build the rows in AppModel instead of body.
<!-- SECTION:FINAL_SUMMARY:END -->
