---
id: PAD-113
title: 'mise run lint fails: 1310 SwiftLint violations against the default rules'
status: To Do
assignee: []
created_date: '2026-11-06 08:47'
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
- [ ] #1 The rules match the code's chosen style (for example a longer line_length, trailing commas allowed), decided with the operator, in .swiftlint.yml
- [ ] #2 Violations left after that are fixed or disabled where they are, each with a reason
- [ ] #3 mise run lint passes on the Mac and in a sandbox, and CI's lint step is green
<!-- AC:END -->
