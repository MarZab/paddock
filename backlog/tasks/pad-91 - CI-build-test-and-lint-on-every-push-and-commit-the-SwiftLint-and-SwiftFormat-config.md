---
id: PAD-91
title: >-
  CI: build, test and lint on every push, and commit the SwiftLint and
  SwiftFormat config
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - tooling
  - ci
dependencies: []
priority: medium
type: chore
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. There is no .github, so nothing runs mise run test or mise run lint besides the operator's own machine, and there is no .swiftlint.yml or .swiftformat in the repository, so lint rules are whatever the pinned defaults are and strict mode treats them as the project's choice only by accident. Package.resolved files are committed (good) but nothing checks them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A GitHub Actions workflow on a macOS runner runs mise install, mise run lint, mise run test for both packages, and builds the app; the first-build plugin trust step is handled without -skipPackagePluginValidation (CLAUDE.md)
- [ ] #2 A Linux job runs the PaddockCore tests (the sandbox flow in CLAUDE.md already supports it)
- [ ] #3 .swiftlint.yml and .swiftformat are committed with the reasons for any disabled rule, and cover Packages, App and tests
- [ ] #4 Workflow pins actions by commit SHA and sets permissions: contents: read
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added .github/workflows/ci.yml (macOS lint+test, Linux test), .swiftlint.yml (paths only), shellcheck now also covers tools/sandbox/*.sh. Not done: app build in CI (needs SwiftTerm plugin trust), SHA-pinning of actions (SHAs not looked up), .swiftformat. Workflow never run.
<!-- SECTION:NOTES:END -->
