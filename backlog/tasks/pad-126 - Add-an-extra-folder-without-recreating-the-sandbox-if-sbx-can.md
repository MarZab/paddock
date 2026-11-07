---
id: PAD-126
title: 'Add an extra folder without recreating the sandbox, if sbx can'
status: Done
assignee: []
created_date: '2026-11-07 10:24'
updated_date: '2026-11-07 10:25'
labels:
  - sbx
dependencies: []
type: spike
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator question 2026-11-07: an added extra folder takes effect only at the sandbox's next create (a recreate item). sbx 0.51's help documents no way to add a mount to an existing sandbox, but sbx secret set warns about 'mounts added to a running sandbox later'. mise run capture:cli mounts probes it on throwaway sandboxes: sbx run --name with more workspaces, sbx create on an existing name, and sbx env create after adding additionalWorkspaces (with sbx env plan first). Copying files in (sbx cp) is ruled out by the operator. (backlog doc App config, Sync)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Captures of mise run capture:cli mounts are in .tmp/captures (mounts-*) and read: which, if any, of the three tries mounts the new folder in the existing sandbox, and what sbx keeps (state, session)
- [x] #2 If one works: Paddock adds extra folders that way (fixtures, tests, the recreate item goes), else the Sync doc says sbx cannot, with the captures
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
mise run capture:cli mounts (sbx 0.51.0, 2026-11-07): sbx run --name with more workspaces fails with "already exists and can't be given new workspaces"; sbx create on the name fails ("connect to the existing sandbox"); sbx env plan lists the new workspace but sbx env create fails ("already exists ... remove it with sbx env rm and create it again"). Nothing new was mounted in either sandbox (sbx ls and a look from inside). A recreate stays the only way; the Sync doc says so. The probe phase stays in tools/tasks/capture/cli.sh to recheck with later sbx versions.
<!-- SECTION:FINAL_SUMMARY:END -->
