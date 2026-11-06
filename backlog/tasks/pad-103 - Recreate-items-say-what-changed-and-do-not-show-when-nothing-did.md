---
id: PAD-103
title: 'Recreate items say what changed, and do not show when nothing did'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06 07:43'
updated_date: '2026-11-06 07:46'
labels:
  - sync
  - app
dependencies: []
priority: medium
type: feature
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator request 2026-11-06: the sync items saying the sandbox differs from what it was created from ("The project's sbxenv.yaml or its kit changed since the sandbox was created", "The sandbox was created with other kits, or older versions of Paddock's") give no details, and show when nothing that matters changed. Paddock kept only a fingerprint of the sbxenv.yaml and kit files and the --kit values, so it could not say what differs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A create records each sbxenv.yaml and project-kit file by hash; the environment item names the files added, removed, or changed since
- [x] #2 Formatting or comments alone in sbxenv.yaml, and Finder files (.DS_Store) in a kit folder, are not a change: no item
- [x] #3 The kits item names the kits added and removed, and Paddock kits that are a newer version; the same kits in another order are not a change
- [x] #4 A sandbox created before the record keeps a plain message saying Paddock has no details for it
- [x] #5 Core tests cover each case; doc names it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
EnvironmentRecord (Core) keeps each sbxenv.yaml key by its parsed value and each project-kit file by hash, without .DS_Store; ProjectRunner stores it as Project.sandboxEnvironmentRecord at create; SandboxSync.environmentSummary and kitChanges word the items, nil/empty when nothing counts. EnvironmentRecordTests pass on Linux; the full suite has only the 3 failures origin/main has. App/AppModel.syncItems passes the record of the confirmed version: NOT compiled here, needs a Mac build. Sandboxes created before this keep a plain item until recreated.
<!-- SECTION:NOTES:END -->
