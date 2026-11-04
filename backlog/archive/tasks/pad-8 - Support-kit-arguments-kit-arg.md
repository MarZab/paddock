---
id: PAD-8
title: Support kit arguments (--kit-arg)
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
labels:
  - kits
milestone: m-2
dependencies: []
priority: low
type: feature
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx create takes --kit-arg for kits that accept arguments. Paddock does not support them (doc: Kits). Arguments come only from paddock.toml [kits], never from a project's .paddock.toml.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A [kits.NAME] section can set arguments, validated like the rest of paddock.toml (no leading -, no whitespace in names)
- [ ] #2 sbx create gets them as --kit-arg in argv, never through a shell, with tests
- [ ] #3 A change of arguments shows recreate under Needs attention
<!-- AC:END -->
