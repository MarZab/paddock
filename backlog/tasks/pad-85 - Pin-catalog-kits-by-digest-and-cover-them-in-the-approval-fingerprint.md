---
id: PAD-85
title: Pin catalog kits by digest and cover them in the approval fingerprint
status: To Do
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - environment
  - supply-chain
dependencies: []
priority: medium
type: task
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. ProjectEnvironment.isCatalog accepts docker.io/sbx/NAME and docker.io/docker/sbx-kit-NAME with any tag or digest (the character set allows : and @), and Fingerprint covers only the project's own files, so a catalog kit is whatever the tag points at when sbx pulls it. The operator approves a name, not content. A moved tag or compromised publisher changes what runs in the sandbox without a new approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spike result recorded in the Kits doc: can sbx report or pin a kit's resolved digest (sbx env plan, sbx env create --json)? Capture the output as a fixture first (CLAUDE.md: fixtures first)
- [ ] #2 If sbx can: the confirmation sheet shows the digest, the fingerprint includes it, and a changed digest asks again; if not: a ticket for the upstream gap and the sheet says the kit is unpinned
- [ ] #3 Tests for a tag-only reference, a digest reference, and a changed digest
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Not started in the 2026-11-04 fix pass: no Swift toolchain in that sandbox, and this change is too large to make uncompiled.
<!-- SECTION:NOTES:END -->
