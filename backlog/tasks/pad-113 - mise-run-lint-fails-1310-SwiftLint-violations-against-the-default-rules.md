---
id: PAD-113
title: 'mise run lint fails: 1310 SwiftLint violations against the default rules'
status: In Progress
assignee: []
created_date: '2026-11-06 08:47'
updated_date: '2026-11-06 09:09'
labels:
  - tooling
  - lint
dependencies: []
priority: medium
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
.swiftlint.yml has used SwiftLint's default rules with --strict since the first commit, and the code does not follow them: a run on 2026-11-06 (Linux, swiftlint 0.65.1) found 1310 violations in 173 files, mostly line_length (120), then identifier_name, optional_data_string_conversion, trailing_comma, cyclomatic_complexity. So mise run lint, and CI's lint step, fail, and a new violation is lost among the old ones.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The rules match the code's chosen style (for example a longer line_length, trailing commas allowed), decided with the operator, in .swiftlint.yml
- [x] #2 Violations left after that are fixed or disabled where they are, each with a reason
- [ ] #3 mise run lint passes on the Mac and in a sandbox, and CI's lint step is green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided with the operator: loosen rules (line_length 210, trailing_comma off, higher length/complexity limits, four rules off with reasons). 0 violations in a Linux sandbox. AC3 needs the Mac and CI.
<!-- SECTION:NOTES:END -->
