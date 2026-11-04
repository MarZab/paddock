---
id: PAD-84
title: >-
  sbx env create reads sbxenv.yaml after the operator's approval was checked:
  close the check-to-use gap
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - environment
dependencies: []
priority: high
type: bug
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. ProjectRunner.create calls confirmedEnvironment (reads sbxenv.yaml and local kits, compares the fingerprint to project.approvedEnvironment) and then, many steps later, runs 'sbx env create <project>/sbxenv.yaml overlay'. sbx reads the files again from the project folder. The agent writes that folder; on a recreate the old sandbox (read-write mount) may still run, and the real create takes seconds. A swap in that window makes sbx build from files the operator never confirmed (new hosts, privileged@1, a lifecycle hook). The same gap exists for local kit folders.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Create runs sbx from a snapshot Paddock owns: the checked bytes of sbxenv.yaml and each local kit are copied to a 0700 directory under the config dir and sbx is pointed at the copy, OR the fingerprint is recomputed after sbx finished and a mismatch removes the new sandbox and fails the create loudly
- [ ] #2 A test with a fake runner that changes the file between the check and the sbx call proves a changed file is never used
- [ ] #3 Project config file doc says which of the two guarantees Paddock gives
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Detect-and-remove variant: after sbx env create the fingerprint is recomputed; a mismatch runs sbx rm --force and throws environmentChangedDuringCreate. Test aFileChangedWhileSbxCreatesTheSandboxRemovesIt. A snapshot copy was not done (sbx resolves local kits relative to the file). NOT compiled.
<!-- SECTION:NOTES:END -->
